package com.flipfold.ludozing.notifications

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.util.Log
import org.json.JSONObject

/**
 * Local notifications without the game: the stored schedule (SharedPreferences), the alarms, the channels and the
 * posting. Used by the plugin and by the receivers, which run while the game is closed.
 *
 * A scheduled item is armed with an inexact AlarmManager.setAndAllowWhileIdle (no exact-alarm permission; Android may
 * deliver it some minutes late, also in Doze) and kept in the preferences until it fires or is canceled, so the
 * BootReceiver can arm it again after a reboot (alarms don't survive one). Items whose time has passed by then are
 * dropped.
 */
internal object Notifs {
    const val TAG = "Notifications"
    private const val PREFS = "lz_notifications"
    private const val ITEM = "n:"                     // + id -> Item JSON
    const val ACTION_FIRE = "com.flipfold.ludozing.notifications.FIRE"
    const val EXTRA_ID = "lz_id"

    // extras on the launcher intent of a tapped notification (read back by NotificationsPlugin.takeLaunch)
    const val EXTRA_LINK = "lz_link"
    const val EXTRA_CID = "lz_cid"
    const val EXTRA_SOURCE = "lz_source"              // "local" | "push"
    // a push notification shown by the system (game in the background) opens the launcher intent with the message's
    // data as extras (link, cid, kind) plus FCM's own keys; this one marks it
    private const val FCM_MESSAGE_ID = "google.message_id"

    // every notification is told apart by its tag (the item id, or "push:<tag>"), the int id is the same for all
    private const val NOTIFY_ID = 1

    class Channel(val id: String, val name: String, val importance: Int, val description: String)

    /** server/NOTIFICATIONS.md "Ids and texts": the names are what the phone's settings show. */
    val CHANNELS = listOf(
        Channel("rewards", "Rewards", NotificationManager.IMPORTANCE_DEFAULT,
            "Your daily reward, free spin and free coins are ready"),
        Channel("reminders", "Reminders", NotificationManager.IMPORTANCE_DEFAULT,
            "A nudge when you haven't played for a while"),
        Channel("game", "Game alerts", NotificationManager.IMPORTANCE_HIGH,
            "Your turn, friends joining your room, rematches and weekly results"),
        Channel("offers", "News & offers", NotificationManager.IMPORTANCE_DEFAULT,
            "News, events and offers from Ludo Zing"),
    )
    private const val FALLBACK_CHANNEL = "reminders"

    /** One scheduled local notification. [atMs]: wall-clock time in milliseconds. */
    class Item(val id: String, val atMs: Long, val channel: String, val title: String, val body: String, val link: String) {
        fun toJson(): String = JSONObject()
            .put("id", id).put("at", atMs).put("channel", channel)
            .put("title", title).put("body", body).put("link", link)
            .toString()

        companion object {
            fun fromJson(s: String): Item? = try {
                val o = JSONObject(s)
                Item(o.getString("id"), o.getLong("at"), o.optString("channel", FALLBACK_CHANNEL),
                    o.optString("title"), o.optString("body"), o.optString("link"))
            } catch (t: Throwable) {
                Log.w(TAG, "bad stored item dropped", t)
                null
            }
        }
    }

    fun prefs(ctx: Context): SharedPreferences = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun channelOrFallback(channel: String): String =
        if (CHANNELS.any { it.id == channel }) channel else FALLBACK_CHANNEL

    /** Creates (or renames) the four channels. Android keeps the player's own choices for existing ones. */
    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannels(CHANNELS.map { c ->
            NotificationChannel(c.id, c.name, c.importance).apply { description = c.description }
        })
    }

    // ---------- schedule ----------

    /** Stores [item] (replacing the same id) and arms its alarm. */
    fun schedule(ctx: Context, item: Item) {
        prefs(ctx).edit().putString(ITEM + item.id, item.toJson()).apply()
        arm(ctx, item)
    }

    /** Drops the item [id]: its alarm and, when it has fired already, its notification in the shade. */
    fun cancel(ctx: Context, id: String) {
        prefs(ctx).edit().remove(ITEM + id).apply()
        disarm(ctx, id)
        ctx.getSystemService(NotificationManager::class.java)?.cancel(id, NOTIFY_ID)
    }

    fun cancelAll(ctx: Context) {
        for (id in ids(ctx)) cancel(ctx, id)
    }

    fun ids(ctx: Context): List<String> =
        prefs(ctx).all.keys.filter { it.startsWith(ITEM) }.map { it.removePrefix(ITEM) }.sorted()

    fun load(ctx: Context, id: String): Item? = prefs(ctx).getString(ITEM + id, null)?.let { Item.fromJson(it) }

    /** After a reboot / app update: arms every stored item again, dropping those already past. */
    fun rearm(ctx: Context): Int {
        val now = System.currentTimeMillis()
        var armed = 0
        for (id in ids(ctx)) {
            val item = load(ctx, id)
            if (item == null || item.atMs < now) {
                prefs(ctx).edit().remove(ITEM + id).apply()
                continue
            }
            arm(ctx, item)
            armed++
        }
        return armed
    }

    /** The alarm for [id] went off (AlarmReceiver): post it and forget it. */
    fun fire(ctx: Context, id: String) {
        val item = load(ctx, id)
        if (item == null) {
            Log.i(TAG, "fire $id: not scheduled any more")
            return
        }
        prefs(ctx).edit().remove(ITEM + id).apply()
        val posted = post(ctx, id, item.channel, item.title, item.body,
            mapOf(EXTRA_LINK to item.link, EXTRA_SOURCE to "local"))
        Log.i(TAG, "fire $id: ${if (posted) "posted on ${channelOrFallback(item.channel)}" else "not posted"}")
    }

    private fun arm(ctx: Context, item: Item) {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return
        val pi = alarmIntent(ctx, item.id, create = true) ?: return
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.atMs, pi)
    }

    private fun disarm(ctx: Context, id: String) {
        val pi = alarmIntent(ctx, id, create = false) ?: return
        ctx.getSystemService(AlarmManager::class.java)?.cancel(pi)
        pi.cancel()
    }

    /** One PendingIntent per id: the id is in the intent's data, which (unlike extras) makes the intents distinct. */
    private fun alarmIntent(ctx: Context, id: String, create: Boolean): PendingIntent? {
        val intent = Intent(ctx, AlarmReceiver::class.java)
            .setAction(ACTION_FIRE)
            .setData(Uri.fromParts("lznotif", id, null))
            .putExtra(EXTRA_ID, id)
        val flags = PendingIntent.FLAG_IMMUTABLE or
            if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
        return PendingIntent.getBroadcast(ctx, 0, intent, flags)
    }

    // ---------- posting ----------

    /**
     * Shows a notification now: our small icon, [channel] (unknown -> reminders), tap = the game's launcher activity
     * with [extras]. False when it can't be shown (notifications off for the app, no launcher intent).
     */
    fun post(ctx: Context, tag: String, channel: String, title: String, body: String, extras: Map<String, String>): Boolean {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return false
        if (!nm.areNotificationsEnabled()) return false
        ensureChannels(ctx)
        val ch = channelOrFallback(channel)
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return false
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        for ((k, v) in extras) if (v.isNotEmpty()) launch.putExtra(k, v)
        val tap = PendingIntent.getActivity(ctx, tag.hashCode(), launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, ch)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx).setPriority(
                if (ch == "game") Notification.PRIORITY_HIGH else Notification.PRIORITY_DEFAULT)
        }
        b.setSmallIcon(R.drawable.lz_notif_icon)
            .setColor(ctx.getColor(R.color.lz_notif_color))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setShowWhen(true)
            .setContentIntent(tap)
        return try {
            nm.notify(tag, NOTIFY_ID, b.build())
            true
        } catch (t: Throwable) {
            Log.w(TAG, "post $tag failed", t)
            false
        }
    }

    // ---------- launch data ----------

    /** {link, cid, source} when [intent] comes from tapping one of our notifications (local or push), else null. */
    fun launchData(intent: Intent?): Map<String, String>? {
        val ex = try { intent?.extras } catch (t: Throwable) { null } ?: return null
        if (ex.containsKey(EXTRA_SOURCE) || ex.containsKey(EXTRA_LINK)) {
            return mapOf("link" to (ex.getString(EXTRA_LINK) ?: ""), "cid" to (ex.getString(EXTRA_CID) ?: ""),
                "source" to (ex.getString(EXTRA_SOURCE) ?: "local"))
        }
        if (ex.containsKey(FCM_MESSAGE_ID)) {
            return mapOf("link" to (ex.getString("link") ?: ""), "cid" to (ex.getString("cid") ?: ""),
                "source" to "push")
        }
        return null
    }

    /** Takes the markers off [intent] so the same tap is never reported twice (e.g. on the next resume). */
    fun consumeLaunch(intent: Intent) {
        for (k in listOf(EXTRA_LINK, EXTRA_CID, EXTRA_SOURCE, FCM_MESSAGE_ID)) intent.removeExtra(k)
    }
}
