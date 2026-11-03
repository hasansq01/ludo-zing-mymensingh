package com.flipfold.ludozing.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** A scheduled local notification is due (our own alarm, see Notifs.schedule): post it. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Notifs.ACTION_FIRE) return
        val id = intent.getStringExtra(Notifs.EXTRA_ID) ?: return
        Notifs.fire(context, id)
    }
}

/** Alarms are lost on a reboot (and may be on an app update): arm the stored schedule again. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val armed = Notifs.rearm(context)
                Log.i(Notifs.TAG, "${intent.action}: re-armed $armed")
            }
        }
    }
}
