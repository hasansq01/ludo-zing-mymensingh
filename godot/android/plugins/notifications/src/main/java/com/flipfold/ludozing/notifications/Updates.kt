package com.flipfold.ludozing.notifications

import android.app.Activity
import android.content.Context
import android.util.Log
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallState
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.ActivityResult
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import org.godotengine.godot.Dictionary

/**
 * Google Play In-App Updates (com.google.android.play:app-update) for the game's AppUpdate
 * (res://scripts/net/app_update.gd), reached through NotificationsPlugin.update_check() / update_start() /
 * update_complete(). Flexible: the update downloads in the background while the game goes on and the game restarts it
 * when it is ready. Immediate: Play's full-screen update, which restarts the app by itself.
 *
 * Answers go out through [emit] (the plugin's signals): `update_info` ({available, version_code, staleness_days,
 * flexible, immediate, in_progress, status, priority}), `update_state` ({status: "pending" | "downloading" |
 * "downloaded" | "installing" | "installed" | "failed" | "cancelled", bytes, total, error}) and `update_failed`
 * (code: "check:<m>" | "start:<m>" | "complete:<m>"). Play only answers for an app installed from Play (an
 * emulator, an APK from adb or a debug build answers with an error such as ERROR_APP_NOT_OWNED, -10): that is a
 * normal `update_failed`, the game's cue to use its fallback, never an exception.
 *
 * The update flow's result comes through Activity.onActivityResult (startUpdateFlowForResult with [REQUEST]):
 * NotificationsPlugin.onMainActivityResult hands it to [onResult].
 */
internal class Updates(private val emit: (String, Any) -> Unit) {

    companion object {
        private const val TAG = Notifs.TAG
        /** Request code of the update flow's activity result (next to the permission dialog's). */
        const val REQUEST = 0x4C5C

        const val SIG_INFO = "update_info"
        const val SIG_STATE = "update_state"
        const val SIG_FAILED = "update_failed"

        fun statusName(s: Int): String = when (s) {
            InstallStatus.PENDING -> "pending"
            InstallStatus.DOWNLOADING -> "downloading"
            InstallStatus.DOWNLOADED -> "downloaded"
            InstallStatus.INSTALLING -> "installing"
            InstallStatus.INSTALLED -> "installed"
            InstallStatus.FAILED -> "failed"
            InstallStatus.CANCELED -> "cancelled"
            else -> "unknown"
        }
    }

    private var manager: AppUpdateManager? = null
    private var info: AppUpdateInfo? = null
    private var listener: InstallStateUpdatedListener? = null
    private var flowType = -1                      // AppUpdateType of the flow Play is showing, -1 = none

    private fun manager(ctx: Context): AppUpdateManager =
        manager ?: AppUpdateManagerFactory.create(ctx.applicationContext).also { manager = it }

    private fun failed(code: String, t: Throwable) {
        Log.w(TAG, "update $code failed: ${t.message}")
        emit(SIG_FAILED, "$code:${t.message ?: t.javaClass.simpleName}")
    }

    /** Asks Play about a newer version -> update_info, or update_failed("check:<m>"). */
    fun check(ctx: Context) {
        try {
            manager(ctx).appUpdateInfo
                .addOnSuccessListener { i ->
                    info = i
                    Log.i(TAG, "update check: ${describe(i)}")
                    emit(SIG_INFO, toDict(i))
                }
                .addOnFailureListener { failed("check", it) }
        } catch (t: Throwable) {
            failed("check", t)
        }
    }

    /**
     * Starts Play's flexible ([immediate] false) or immediate update flow from the last check (asking again when there
     * has been none). The flexible download's progress comes as update_state until it is downloaded.
     */
    fun start(act: Activity, immediate: Boolean) {
        val type = if (immediate) AppUpdateType.IMMEDIATE else AppUpdateType.FLEXIBLE
        val known = info
        if (known != null && known.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE) {
            begin(act, known, type)
            return
        }
        try {
            manager(act).appUpdateInfo
                .addOnSuccessListener { i ->
                    info = i
                    if (i.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE) begin(act, i, type)
                    else emit(SIG_FAILED, "start:not_available")
                }
                .addOnFailureListener { failed("start", it) }
        } catch (t: Throwable) {
            failed("start", t)
        }
    }

    private fun begin(act: Activity, i: AppUpdateInfo, type: Int) {
        try {
            if (!i.isUpdateTypeAllowed(type)) {
                emit(SIG_FAILED, "start:not_allowed")
                return
            }
            val mgr = manager(act)
            if (type == AppUpdateType.FLEXIBLE) listen(mgr)
            flowType = type
            val shown = mgr.startUpdateFlowForResult(i, act, AppUpdateOptions.newBuilder(type).build(), REQUEST)
            if (!shown) {
                flowType = -1
                emit(SIG_FAILED, "start:not_shown")
            }
        } catch (t: Throwable) {
            flowType = -1
            failed("start", t)
        }
    }

    /** Installs a downloaded flexible update: the game restarts. */
    fun complete(ctx: Context) {
        try {
            manager(ctx).completeUpdate().addOnFailureListener { failed("complete", it) }
        } catch (t: Throwable) {
            failed("complete", t)
        }
    }

    /** NotificationsPlugin.onMainActivityResult: the player's answer to Play's update screen. */
    fun onResult(resultCode: Int) {
        val type = flowType
        flowType = -1
        Log.i(TAG, "update flow result $resultCode (type $type)")
        when (resultCode) {
            Activity.RESULT_OK -> Unit   // flexible: the listener reports the download; immediate: Play restarts the app
            Activity.RESULT_CANCELED -> {
                unlisten()
                emit(SIG_STATE, state("cancelled"))
            }
            ActivityResult.RESULT_IN_APP_UPDATE_FAILED -> {
                unlisten()
                emit(SIG_STATE, state("failed", error = "flow_failed"))
            }
            else -> {
                unlisten()
                emit(SIG_STATE, state("failed", error = "result_$resultCode"))
            }
        }
    }

    /**
     * The game came back to the foreground (Google's guidance): an immediate update that was in progress goes on (Play
     * must not be left half done), and a flexible download that finished while the game was away is "downloaded".
     * Quiet when Play can't answer (nothing to resume then).
     */
    fun onResume(act: Activity) {
        val mgr = manager ?: return                  // never asked Play: nothing was started by this process
        try {
            mgr.appUpdateInfo.addOnSuccessListener { i ->
                info = i
                if (i.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                    Log.i(TAG, "update: resuming the immediate update")
                    begin(act, i, AppUpdateType.IMMEDIATE)
                } else if (i.installStatus() == InstallStatus.DOWNLOADED) {
                    emit(SIG_STATE, state("downloaded"))
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "update resume check failed", t)
        }
    }

    fun onDestroy() {
        unlisten()
        manager = null
        info = null
    }

    private fun listen(mgr: AppUpdateManager) {
        if (listener != null) return
        val l = InstallStateUpdatedListener { s: InstallState ->
            val name = statusName(s.installStatus())
            val d = state(name, s.bytesDownloaded(), s.totalBytesToDownload(),
                if (s.installStatus() == InstallStatus.FAILED) "install_error_${s.installErrorCode()}" else "")
            emit(SIG_STATE, d)
            if (s.installStatus() == InstallStatus.INSTALLED || s.installStatus() == InstallStatus.FAILED ||
                s.installStatus() == InstallStatus.CANCELED) unlisten()
        }
        listener = l
        mgr.registerListener(l)
    }

    private fun unlisten() {
        val l = listener ?: return
        listener = null
        try {
            manager?.unregisterListener(l)
        } catch (t: Throwable) {
            Log.w(TAG, "unregisterListener failed", t)
        }
    }

    private fun state(status: String, bytes: Long = 0L, total: Long = 0L, error: String = ""): Dictionary {
        val d = Dictionary()
        d["status"] = status
        d["bytes"] = bytes
        d["total"] = total
        d["error"] = error
        return d
    }

    private fun toDict(i: AppUpdateInfo): Dictionary {
        val d = Dictionary()
        val availability = i.updateAvailability()
        d["available"] = availability == UpdateAvailability.UPDATE_AVAILABLE
        d["in_progress"] = availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
        d["version_code"] = i.availableVersionCode()
        d["staleness_days"] = i.clientVersionStalenessDays() ?: -1   // -1: Play doesn't know (not published long enough)
        d["priority"] = i.updatePriority()
        d["flexible"] = i.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)
        d["immediate"] = i.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)
        d["status"] = statusName(i.installStatus())
        return d
    }

    private fun describe(i: AppUpdateInfo): String =
        "availability ${i.updateAvailability()}, version ${i.availableVersionCode()}, " +
            "staleness ${i.clientVersionStalenessDays()}, flexible ${i.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)}, " +
            "immediate ${i.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)}, status ${statusName(i.installStatus())}"
}
