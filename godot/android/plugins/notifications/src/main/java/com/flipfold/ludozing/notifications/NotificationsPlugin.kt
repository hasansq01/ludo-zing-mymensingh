package com.flipfold.ludozing.notifications

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.View
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.tasks.Task
import com.google.firebase.messaging.FirebaseMessaging
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.lang.ref.WeakReference

/**
 * Local and push notifications for Ludo Zing (Godot v2 Android plugin, Engine singleton "NotificationsPlugin").
 * Contract: server/NOTIFICATIONS.md "N-PLUG". The GDScript side is res://scripts/net/notifier.gd (class Notifier),
 * and the method names below are the contract's (snake_case on purpose: GDScript calls them by these names).
 *
 * Every method is safe to call at any time and never throws into GDScript; asynchronous answers come as signals.
 * Push stays off until push_init() is called with the four Firebase values: before that no Firebase code runs.
 *
 * Opening the game from a notification: the tap starts the launcher activity with the extras lz_link / lz_cid /
 * lz_source (ours) or the message data (a push shown by the system). godot-lib 4.7.2 has no onNewIntent hook for
 * plugins, but GodotActivity.onNewIntent calls setIntent() and Android always resumes the activity right after, so
 * the plugin reads activity.intent in onMainCreate (cold start) and onMainResume (warm start) and takes the markers
 * off the intent once read. A relaunch from the recents list (FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) re-delivers the
 * old intent and is ignored.
 */
class NotificationsPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = Notifs.TAG
        private const val PERMISSION = "android.permission.POST_NOTIFICATIONS"
        private const val ASKED_KEY = "permission_asked"
        private const val RC_PERMISSION = 0x4C5B   // "L[": request code of the POST_NOTIFICATIONS dialog

        private val STRING = String::class.java
        private val BOOL = Boolean::class.javaObjectType
        private val DICT = Dictionary::class.java

        // (granted) answer to request_permission()
        val SIG_PERMISSION = SignalInfo("permission_result", BOOL)
        // ({link, cid, source}) a notification was tapped while the game was running
        val SIG_OPENED = SignalInfo("opened", DICT)
        // (token) after push_init(), and whenever FCM refreshes it
        val SIG_PUSH_TOKEN = SignalInfo("push_token", STRING)
        // (code) "not_configured" | "no_play_services:<n>" | "not_initialized" | "error:<m>" | "subscribe:<m>" |
        // "unsubscribe:<m>" | "delete:<m>"
        val SIG_PUSH_FAILED = SignalInfo("push_failed", STRING)
        // ({title, body, link, cid, kind}) a push arrived while the game is in the foreground (nothing is shown)
        val SIG_PUSH_RECEIVED = SignalInfo("push_received", DICT)

        @Volatile private var live: WeakReference<NotificationsPlugin>? = null

        /** The plugin of the running game, if any (the messaging service runs without it too). */
        internal fun running(): NotificationsPlugin? = live?.get()

        /** The plugin while the game activity is resumed (on screen), else null. */
        internal fun foreground(): NotificationsPlugin? = running()?.takeIf { it.resumed }
    }

    @Volatile private var resumed = false
    @Volatile private var loopStarted = false
    @Volatile private var pushReady = false
    @Volatile private var asking = false                 // the POST_NOTIFICATIONS dialog is showing
    private val launchLock = Any()
    private var launch: Map<String, String>? = null      // the tap that opened the game, until take_launch_data()

    override fun getPluginName() = "NotificationsPlugin"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SIG_PERMISSION, SIG_OPENED, SIG_PUSH_TOKEN, SIG_PUSH_FAILED, SIG_PUSH_RECEIVED,
    )

    override fun onMainCreate(mainActivity: Activity?): View? {
        live = WeakReference(this)
        val ctx = appContext()
        guard("setup") { Notifs.ensureChannels(ctx) }
        if (mainActivity != null) readLaunch(mainActivity, notify = false)
        Log.i(TAG, "plugin loaded: sdk ${Build.VERSION.SDK_INT}, permission ${permission_state()}, " +
            "${Notifs.ids(ctx).size} scheduled, push ${if (Push.hasSaved(ctx)) "set up before" else "off"}")
        return super.onMainCreate(mainActivity)
    }

    override fun onGodotMainLoopStarted() {
        super.onGodotMainLoopStarted()
        loopStarted = true
    }

    override fun onMainResume() {
        super.onMainResume()
        resumed = true
        activity?.let { readLaunch(it, notify = loopStarted) }
    }

    override fun onMainPause() {
        super.onMainPause()
        resumed = false
    }

    override fun onMainDestroy() {
        resumed = false
        if (live?.get() === this) live = null
        super.onMainDestroy()
    }

    // ---------- permission ----------

    /**
     * "granted" | "denied" | "ask" | "unsupported". Below Android 13 there is no runtime permission: "granted" unless
     * the player turned the app's notifications off ("denied"). On 13+: "ask" while the system dialog can still be
     * shown (never asked yet, or refused once: Android allows a second ask), "denied" when it can't any more or the
     * notifications are off in the settings.
     */
    @UsedByGodot
    fun permission_state(): String {
        return try {
            val ctx = appContext()
            val enabled = ctx.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: false
            if (Build.VERSION.SDK_INT < 33) return if (enabled) "granted" else "denied"
            if (ctx.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED) {
                return if (enabled) "granted" else "denied"
            }
            if (!Notifs.prefs(ctx).getBoolean(ASKED_KEY, false)) return "ask"
            val act = activity ?: return "denied"
            if (act.shouldShowRequestPermissionRationale(PERMISSION)) "ask" else "denied"
        } catch (t: Throwable) {
            Log.w(TAG, "permission_state failed", t)
            "unsupported"
        }
    }

    /** Android 13+: the POST_NOTIFICATIONS dialog. -> permission_result(granted); at once when there is nothing to ask. */
    @UsedByGodot
    fun request_permission() {
        val state = permission_state()
        val act = activity
        if (Build.VERSION.SDK_INT < 33 || state == "granted" || act == null) {
            emitSignal(SIG_PERMISSION.name, state == "granted")
            return
        }
        // the dialog is already up: its answer serves this call too (a second request would be refused at once)
        if (asking) return
        asking = true
        Notifs.prefs(appContext()).edit().putBoolean(ASKED_KEY, true).apply()
        runOnUiThread {
            try {
                act.requestPermissions(arrayOf(PERMISSION), RC_PERMISSION)
            } catch (t: Throwable) {
                Log.w(TAG, "requestPermissions failed", t)
                asking = false
                emitSignal(SIG_PERMISSION.name, false)
            }
        }
    }

    /** The phone's notification settings for this app (the way back once the dialog can't be shown any more). */
    @UsedByGodot
    fun open_settings() {
        val act = activity ?: return
        runOnUiThread {
            val pkg = act.packageName
            val intents = listOf(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg),
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", pkg, null)),
            )
            for (i in intents) {
                try {
                    act.startActivity(i)
                    return@runOnUiThread
                } catch (t: Throwable) {
                    Log.w(TAG, "open_settings: ${i.action} failed", t)
                }
            }
        }
    }

    // ---------- share ----------

    /**
     * The system share sheet with [text] and, when [imagePath] (an absolute path to a PNG) is not empty, that picture.
     * Returns true when the chooser is being started (the player may still cancel it), false when there is no activity.
     */
    @UsedByGodot
    fun share(text: String, imagePath: String): Boolean {
        val act = activity ?: return false
        runOnUiThread {
            guard("share") { Share.send(act, text, imagePath) }
        }
        return true
    }

    override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<String>?, grantResults: IntArray?) {
        super.onMainRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != RC_PERMISSION) return
        asking = false
        val granted = grantResults != null && grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        Log.i(TAG, "permission ${if (granted) "granted" else "refused"} -> ${permission_state()}")
        emitSignal(SIG_PERMISSION.name, granted && permission_state() == "granted")
    }

    // ---------- local notifications ----------

    /** Schedules (or replaces) the local notification [id] at [atUnix] (seconds). Unknown channel -> reminders. */
    @UsedByGodot
    fun schedule(id: String, atUnix: Long, channel: String, title: String, body: String, link: String) {
        if (id.isEmpty()) return
        guard("schedule $id") {
            Notifs.schedule(appContext(), Notifs.Item(id, atUnix * 1000L, Notifs.channelOrFallback(channel), title,
                body, link))
        }
    }

    /** Cancels [id]: not shown any more, and taken out of the shade if it was shown already. */
    @UsedByGodot
    fun cancel(id: String) {
        guard("cancel $id") { Notifs.cancel(appContext(), id) }
    }

    /** Every local notification (push ones are not touched). */
    @UsedByGodot
    fun cancel_all() {
        guard("cancel_all") { Notifs.cancelAll(appContext()) }
    }

    /** Ids of the local notifications still to come. */
    @UsedByGodot
    fun scheduled(): Array<String> = try {
        Notifs.ids(appContext()).toTypedArray()
    } catch (t: Throwable) {
        Log.w(TAG, "scheduled failed", t)
        arrayOf()
    }

    /** {link, cid, source} of the notification that opened the game, once; then {}. */
    @UsedByGodot
    fun take_launch_data(): Dictionary {
        val data = synchronized(launchLock) { launch.also { launch = null } }
        return dict(data ?: emptyMap())
    }

    /** For logs / debugging: {sdk_int, permission, scheduled, push_ready, push_saved}. */
    @UsedByGodot
    fun get_status(): Dictionary {
        val ctx = appContext()
        val d = Dictionary()
        d["sdk_int"] = Build.VERSION.SDK_INT
        d["permission"] = permission_state()
        d["scheduled"] = Notifs.ids(ctx).size
        d["push_ready"] = pushReady
        d["push_saved"] = Push.hasSaved(ctx)
        return d
    }

    // ---------- diagnostics (crash / unexpected-exit reports: Diag.kt, res://scripts/core/crash_watch.gd) ----------

    /**
     * JSON text: the device and app facts {sdk, release, manufacturer, model, soc, version_code, version_name,
     * installer, ram_*, low_ram_device, mem_class_mb, ...} and, on Android 11+, `exits`: the last [maxExits]
     * ApplicationExitInfo records of this app {reason, code, status, importance, importance_name, pss_kb, rss_kb, at,
     * description, pid, summary?, trace?}. Only the newest ANR / native crash newer than [sinceMs] carries its trace.
     * Never throws ("{}" at worst).
     */
    @UsedByGodot
    fun diag_info(sinceMs: Long, maxExits: Int): String = try {
        Diag.info(appContext(), sinceMs, maxExits).toString()
    } catch (t: Throwable) {
        Log.w(TAG, "diag_info failed", t)
        "{}"
    }

    /** Android 11+: [summary] (the game's session id, <= 128 bytes) comes back with this process's exit record. */
    @UsedByGodot
    fun diag_set_state(summary: String) {
        guard("diag_set_state") { Diag.setSummary(appContext(), summary) }
    }

    // ---------- push (FCM) ----------

    /** Initialises Firebase from the four values and fetches the FCM token. -> push_token(token) or push_failed(code). */
    @UsedByGodot
    fun push_init(projectId: String, appId: String, apiKey: String, senderId: String) {
        val values = listOf(projectId, appId, apiKey, senderId).map { it.trim() }
        if (values.any { it.isEmpty() }) {
            emitSignal(SIG_PUSH_FAILED.name, "not_configured")
            return
        }
        val ctx = appContext()
        val gms = try {
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(ctx)
        } catch (t: Throwable) {
            ConnectionResult.SERVICE_MISSING
        }
        if (gms != ConnectionResult.SUCCESS) {
            emitSignal(SIG_PUSH_FAILED.name, "no_play_services:$gms")
            return
        }
        guardPush("error") {
            val options = Push.options(values[0], values[1], values[2], values[3])
            Push.init(ctx, options)
            Push.save(ctx, options)
            pushReady = true
            Log.i(TAG, "push: firebase initialised, fetching token")
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful && !task.result.isNullOrEmpty()) {
                    emitSignal(SIG_PUSH_TOKEN.name, task.result)
                } else {
                    emitSignal(SIG_PUSH_FAILED.name, "error:" + taskError(task))
                }
            }
        }
    }

    /** Subscribes this phone to [topic] (e.g. "promos"). A failure -> push_failed("subscribe:<m>"). */
    @UsedByGodot
    fun push_subscribe(topic: String) {
        if (!pushReady) return emitSignal(SIG_PUSH_FAILED.name, "not_initialized")
        guardPush("subscribe") {
            FirebaseMessaging.getInstance().subscribeToTopic(topic).addOnCompleteListener { task ->
                if (!task.isSuccessful) emitSignal(SIG_PUSH_FAILED.name, "subscribe:" + taskError(task))
            }
        }
    }

    @UsedByGodot
    fun push_unsubscribe(topic: String) {
        if (!pushReady) return emitSignal(SIG_PUSH_FAILED.name, "not_initialized")
        guardPush("unsubscribe") {
            FirebaseMessaging.getInstance().unsubscribeFromTopic(topic).addOnCompleteListener { task ->
                if (!task.isSuccessful) emitSignal(SIG_PUSH_FAILED.name, "unsubscribe:" + taskError(task))
            }
        }
    }

    /** Sign-out: the token stops working (a later push_init() makes a new one). */
    @UsedByGodot
    fun push_delete_token() {
        if (!pushReady) return emitSignal(SIG_PUSH_FAILED.name, "not_initialized")
        guardPush("delete") {
            FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener { task ->
                if (task.isSuccessful) Log.i(TAG, "push token deleted")
                else emitSignal(SIG_PUSH_FAILED.name, "delete:" + taskError(task))
            }
        }
    }

    /** PushService: FCM gave this phone a new token. */
    internal fun onPushToken(token: String) {
        if (pushReady) emitSignal(SIG_PUSH_TOKEN.name, token)
    }

    /** PushService: a message arrived while the game is on screen. */
    internal fun onPushReceived(data: Map<String, String>) {
        Log.i(TAG, "push received in the foreground (kind ${data["kind"]})")
        emitSignal(SIG_PUSH_RECEIVED.name, dict(data))
    }

    // ---------- helpers ----------

    /** The tap that started or resumed [act], if any: kept for take_launch_data(), and signalled when [notify]. */
    private fun readLaunch(act: Activity, notify: Boolean) {
        try {
            val intent = act.intent ?: return
            val data = Notifs.launchData(intent) ?: return
            Notifs.consumeLaunch(intent)
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
            synchronized(launchLock) { launch = data }
            Log.i(TAG, "opened from a ${data["source"]} notification (link ${data["link"]})")
            if (notify) emitSignal(SIG_OPENED.name, dict(data))
        } catch (t: Throwable) {
            Log.w(TAG, "reading the launch intent failed", t)
        }
    }

    private fun appContext(): Context = (activity ?: context).applicationContext

    private fun dict(m: Map<String, String>): Dictionary {
        val d = Dictionary()
        for ((k, v) in m) d[k] = v
        return d
    }

    private inline fun guard(what: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.w(TAG, "$what failed", t)
        }
    }

    private inline fun guardPush(prefix: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.w(TAG, "push $prefix failed", t)
            emitSignal(SIG_PUSH_FAILED.name, "$prefix:${t.message ?: t.javaClass.simpleName}")
        }
    }

    private fun taskError(task: Task<*>): String {
        if (task.isCanceled) return "canceled"
        val e = task.exception ?: return "unknown"
        Log.w(TAG, "push task failed", e)
        return e.message ?: e.javaClass.simpleName
    }
}
