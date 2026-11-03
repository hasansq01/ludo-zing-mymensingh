package com.flipfold.ludozing.notifications

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/**
 * FirebaseApp without google-services.json: push_init() builds the FirebaseOptions from the four project settings
 * and saves them, so the messaging service can initialise the same app when it starts in a process the game didn't
 * start (a push arriving while the game is closed). Until push_init() has run once nothing of Firebase runs at all:
 * the export plugin removes FirebaseInitProvider, and no token exists, so no message can arrive.
 */
internal object Push {
    private const val OPTIONS = "push_options"

    fun options(projectId: String, appId: String, apiKey: String, senderId: String): FirebaseOptions =
        FirebaseOptions.Builder()
            .setProjectId(projectId)
            .setApplicationId(appId)
            .setApiKey(apiKey)
            .setGcmSenderId(senderId)
            .build()

    fun save(ctx: Context, o: FirebaseOptions) {
        val json = JSONObject()
            .put("project_id", o.projectId).put("app_id", o.applicationId)
            .put("api_key", o.apiKey).put("sender_id", o.gcmSenderId)
        Notifs.prefs(ctx).edit().putString(OPTIONS, json.toString()).apply()
    }

    fun hasSaved(ctx: Context): Boolean = Notifs.prefs(ctx).contains(OPTIONS)

    private fun saved(ctx: Context): FirebaseOptions? {
        val s = Notifs.prefs(ctx).getString(OPTIONS, null) ?: return null
        return try {
            val o = JSONObject(s)
            options(o.getString("project_id"), o.getString("app_id"), o.getString("api_key"), o.getString("sender_id"))
        } catch (t: Throwable) {
            Log.w(Notifs.TAG, "bad saved push options", t)
            null
        }
    }

    private fun defaultApp(ctx: Context): FirebaseApp? =
        FirebaseApp.getApps(ctx).firstOrNull { it.name == FirebaseApp.DEFAULT_APP_NAME }

    /** The default FirebaseApp with [o] (re-created when the options changed). Throws on bad options. */
    @Synchronized
    fun init(ctx: Context, o: FirebaseOptions): FirebaseApp {
        val app = defaultApp(ctx)
        if (app != null) {
            if (app.options == o) return app
            app.delete()
        }
        return FirebaseApp.initializeApp(ctx, o)
    }

    /** The default FirebaseApp, initialised from the saved options when needed; null when push was never set up. */
    @Synchronized
    fun ensureApp(ctx: Context): FirebaseApp? {
        defaultApp(ctx)?.let { return it }
        val o = saved(ctx) ?: return null
        return try {
            FirebaseApp.initializeApp(ctx, o)
        } catch (t: Throwable) {
            Log.w(Notifs.TAG, "FirebaseApp from saved options failed", t)
            null
        }
    }

    /** {title, body, link, cid, kind} of a message (notification part first, then the data part). */
    fun data(msg: RemoteMessage): Map<String, String> {
        val n = msg.notification
        val d = msg.data
        return mapOf(
            "title" to (n?.title ?: d["title"] ?: ""),
            "body" to (n?.body ?: d["body"] ?: ""),
            "link" to (d["link"] ?: ""),
            "cid" to (d["cid"] ?: ""),
            "kind" to (d["kind"] ?: ""),
        )
    }
}

/**
 * FCM entry point (replaces firebase-messaging's own service in the manifest).
 *
 * Android shows a notification message by itself while the game is in the background (channel from the message, our
 * icon and the "game" channel by default: manifest meta-data). onMessageReceived only sees it when the app is in the
 * foreground; with the game on screen it becomes the plugin signal push_received and nothing is shown. Data-only
 * messages, or a message arriving while the game isn't the resumed activity, are posted by us on their channel.
 */
class PushService : FirebaseMessagingService() {

    override fun onCreate() {
        // before anything of FCM's handling, which needs the default FirebaseApp in this process
        Push.ensureApp(applicationContext)
        super.onCreate()
    }

    override fun onNewToken(token: String) {
        Log.i(Notifs.TAG, "push token refreshed")
        NotificationsPlugin.running()?.onPushToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = Push.data(message)
        val game = NotificationsPlugin.foreground()
        if (game != null) {
            game.onPushReceived(data)
            return
        }
        val title = data.getValue("title")
        val body = data.getValue("body")
        if (title.isEmpty() && body.isEmpty()) return
        val channel = message.notification?.channelId ?: message.data["channel"] ?: "game"
        val tag = "push:" + (message.notification?.tag ?: message.collapseKey ?: message.messageId ?: title)
        Notifs.post(applicationContext, tag, channel, title, body, mapOf(
            Notifs.EXTRA_LINK to data.getValue("link"),
            Notifs.EXTRA_CID to data.getValue("cid"),
            Notifs.EXTRA_SOURCE to "push",
        ))
    }
}
