package com.flipfold.ludozing.playgames

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.view.View
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayGamesSdk
import com.google.android.gms.tasks.Task
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Google Play Games Services v2 for Ludo Zing (Godot v2 Android plugin, Engine singleton "PlayGamesPlugin";
 * not "PlayGames", which would shadow the GDScript class_name PlayGames).
 *
 * The GDScript side is res://scripts/net/play_games.gd (class PlayGames). Every async call answers with exactly
 * one signal; errors are short codes ("disabled", "no_activity", "canceled", "not_signed_in", "api:<status>",
 * "error:<message>").
 *
 * Disabled mode: when the app manifest has no com.google.android.gms.games.APP_ID meta-data (the project setting
 * ludo_zing/play_games/app_id was empty at export) the plugin never touches the Games SDK, because any Games call
 * without an APP_ID ends in a fatal developer error. Every request then answers "disabled".
 */
class PlayGamesPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "PlayGames"
        private const val APP_ID_KEY = "com.google.android.gms.games.APP_ID"
        private const val RC_UI = 0x4C5A   // "LZ": request code for the leaderboard / achievement screens

        private val STRING = String::class.java
        private val BOOL = Boolean::class.javaObjectType
        private val DICT = Dictionary::class.java

        // (enabled, reason) reason: "" | "no_app_id" | "no_play_services:<code>" | "error:<message>"
        val SIG_INITIALIZED = SignalInfo("initialized", BOOL, STRING)
        // (authenticated, error)
        val SIG_AUTH_CHECKED = SignalInfo("auth_checked", BOOL, STRING)
        // (success, error)
        val SIG_SIGN_IN = SignalInfo("sign_in_completed", BOOL, STRING)
        // (success, server_auth_code, error)
        val SIG_SERVER_AUTH = SignalInfo("server_auth_code_completed", BOOL, STRING, STRING)
        // (success, {display_name, player_id}, error)
        val SIG_PLAYER = SignalInfo("player_info_completed", BOOL, DICT, STRING)
        // (leaderboard_id, success, error)
        val SIG_SCORE = SignalInfo("score_submitted", STRING, BOOL, STRING)
        // (achievement_id, success, error)
        val SIG_ACHIEVEMENT = SignalInfo("achievement_unlocked", STRING, BOOL, STRING)
        // (kind, success, error) kind: "leaderboards" | "leaderboard" | "achievements"; success = the screen opened
        val SIG_UI = SignalInfo("ui_completed", STRING, BOOL, STRING)
        // (kind) the Play Games screen opened by a ui_completed(kind, true, "") call was closed
        val SIG_UI_CLOSED = SignalInfo("ui_closed", STRING)
    }

    // written on the UI thread (onMainCreate, task listeners) and read on the render thread (GDScript calls)
    @Volatile private var appId = ""
    @Volatile private var playServices = -1
    @Volatile private var initialized = false
    @Volatile private var initError = ""
    @Volatile private var openUi = ""

    override fun getPluginName() = "PlayGamesPlugin"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SIG_INITIALIZED, SIG_AUTH_CHECKED, SIG_SIGN_IN, SIG_SERVER_AUTH, SIG_PLAYER, SIG_SCORE, SIG_ACHIEVEMENT,
        SIG_UI, SIG_UI_CLOSED,
    )

    /** UI thread, while the Godot activity is created: initialize the SDK early (it also signs in by itself). */
    override fun onMainCreate(mainActivity: Activity?): View? {
        appId = readAppId()
        Log.i(TAG, "plugin loaded: app_id ${if (appId.isEmpty()) "not set (disabled)" else "set"}")
        if (appId.isNotEmpty() && mainActivity != null) setUp(mainActivity)
        return super.onMainCreate(mainActivity)
    }

    // ---------- status ----------

    /** True when an APP_ID is configured, Play services are usable and PlayGamesSdk.initialize() succeeded. */
    @UsedByGodot
    fun isEnabled(): Boolean = initialized && initError.isEmpty()

    /** {app_id_set, play_services (ConnectionResult code, -1 = not checked), initialized, error, sdk_int}. */
    @UsedByGodot
    fun getStatus(): Dictionary {
        val d = Dictionary()
        d["app_id_set"] = appId.isNotEmpty()
        d["play_services"] = playServices
        d["initialized"] = initialized
        d["error"] = initError
        d["sdk_int"] = Build.VERSION.SDK_INT
        return d
    }

    /**
     * PlayGamesSdk.initialize() (normally already done at activity creation). Safe to call more than once: emits
     * initialized(enabled, reason) every time and returns the same enabled flag. Never touches the Games SDK when
     * no APP_ID is set.
     */
    @UsedByGodot
    fun initialize(): Boolean {
        if (!initialized) {
            if (appId.isEmpty()) appId = readAppId()
            val act = activity
            if (appId.isNotEmpty() && act != null) setUp(act)
        }
        val reason = when {
            initialized -> initError
            appId.isEmpty() -> "no_app_id"
            else -> "no_activity"
        }
        val enabled = initialized && reason.isEmpty()
        Log.i(TAG, "initialize: ${if (enabled) "enabled" else "disabled ($reason)"}")
        emitSignal(SIG_INITIALIZED.name, enabled, reason)
        return enabled
    }

    /** Checks Play services and runs PlayGamesSdk.initialize once; the outcome is final for this process. */
    @Synchronized
    private fun setUp(act: Activity) {
        if (initialized) return
        initError = try {
            playServices = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(act)
            if (playServices != ConnectionResult.SUCCESS) {
                "no_play_services:$playServices"
            } else {
                PlayGamesSdk.initialize(act)
                ""
            }
        } catch (t: Throwable) {
            Log.w(TAG, "PlayGamesSdk.initialize failed", t)
            "error:${t.message ?: t.javaClass.simpleName}"
        }
        initialized = true
        Log.i(TAG, "setup: play_services=$playServices ${if (initError.isEmpty()) "sdk initialized" else initError}")
    }

    // ---------- sign-in ----------

    /** Automatic sign-in result (the SDK signs in at launch by itself): auth_checked(authenticated, error). */
    @UsedByGodot
    fun isAuthenticated() {
        val act = ready { err -> emitSignal(SIG_AUTH_CHECKED.name, false, err) } ?: return
        guard({ err -> emitSignal(SIG_AUTH_CHECKED.name, false, err) }) {
            PlayGames.getGamesSignInClient(act).isAuthenticated().addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    emitSignal(SIG_AUTH_CHECKED.name, task.result?.isAuthenticated == true, "")
                } else {
                    emitSignal(SIG_AUTH_CHECKED.name, false, errorCode(task))
                }
            }
        }
    }

    /** Manual sign-in (the "Sign in with Play Games" button): sign_in_completed(success, error). */
    @UsedByGodot
    fun signIn() {
        val act = ready { err -> emitSignal(SIG_SIGN_IN.name, false, err) } ?: return
        guard({ err -> emitSignal(SIG_SIGN_IN.name, false, err) }) {
            PlayGames.getGamesSignInClient(act).signIn().addOnCompleteListener { task ->
                when {
                    !task.isSuccessful -> emitSignal(SIG_SIGN_IN.name, false, errorCode(task))
                    task.result?.isAuthenticated == true -> emitSignal(SIG_SIGN_IN.name, true, "")
                    else -> emitSignal(SIG_SIGN_IN.name, false, "canceled")
                }
            }
        }
    }

    /**
     * One-time server auth code for the game server (POST /v1/auth/google), for the Web OAuth client id.
     * server_auth_code_completed(success, code, error).
     */
    @UsedByGodot
    fun requestServerSideAccess(webClientId: String, forceRefreshToken: Boolean) {
        val fail = { err: String -> emitSignal(SIG_SERVER_AUTH.name, false, "", err) }
        if (webClientId.isBlank()) {
            fail("no_web_client_id")
            return
        }
        val act = ready(fail) ?: return
        guard(fail) {
            PlayGames.getGamesSignInClient(act).requestServerSideAccess(webClientId, forceRefreshToken)
                .addOnCompleteListener { task ->
                    val code = if (task.isSuccessful) task.result else null
                    if (!code.isNullOrEmpty()) {
                        emitSignal(SIG_SERVER_AUTH.name, true, code, "")
                    } else {
                        fail(if (task.isSuccessful) "empty_code" else errorCode(task))
                    }
                }
        }
    }

    /** Display name and player id of the signed-in player, for UI only: player_info_completed(success, info, error). */
    @UsedByGodot
    fun getPlayerInfo() {
        val fail = { err: String -> emitSignal(SIG_PLAYER.name, false, Dictionary(), err) }
        val act = ready(fail) ?: return
        guard(fail) {
            PlayGames.getPlayersClient(act).currentPlayer.addOnCompleteListener { task ->
                val p = if (task.isSuccessful) task.result else null
                if (p == null) {
                    fail(if (task.isSuccessful) "not_signed_in" else errorCode(task))
                } else {
                    val d = Dictionary()
                    d["display_name"] = p.displayName ?: ""
                    d["player_id"] = p.playerId ?: ""
                    emitSignal(SIG_PLAYER.name, true, d, "")
                }
            }
        }
    }

    // ---------- leaderboards / achievements ----------

    /** score_submitted(leaderboard_id, success, error). Uses submitScoreImmediate so the result is known. */
    @UsedByGodot
    fun submitScore(leaderboardId: String, score: Long) {
        val fail = { err: String -> emitSignal(SIG_SCORE.name, leaderboardId, false, err) }
        val act = ready(fail) ?: return
        guard(fail) {
            PlayGames.getLeaderboardsClient(act).submitScoreImmediate(leaderboardId, score)
                .addOnCompleteListener { task ->
                    if (task.isSuccessful) emitSignal(SIG_SCORE.name, leaderboardId, true, "") else fail(errorCode(task))
                }
        }
    }

    /** The Play Games "all leaderboards" screen: ui_completed("leaderboards", opened, error), then ui_closed. */
    @UsedByGodot
    fun showAllLeaderboards() {
        val act = ready { err -> emitSignal(SIG_UI.name, "leaderboards", false, err) } ?: return
        showIntent(act, "leaderboards") { PlayGames.getLeaderboardsClient(act).allLeaderboardsIntent }
    }

    /** One leaderboard's screen: ui_completed("leaderboard", opened, error), then ui_closed. */
    @UsedByGodot
    fun showLeaderboard(leaderboardId: String) {
        val act = ready { err -> emitSignal(SIG_UI.name, "leaderboard", false, err) } ?: return
        showIntent(act, "leaderboard") { PlayGames.getLeaderboardsClient(act).getLeaderboardIntent(leaderboardId) }
    }

    @UsedByGodot
    fun showAchievements() {
        val act = ready { err -> emitSignal(SIG_UI.name, "achievements", false, err) } ?: return
        showIntent(act, "achievements") { PlayGames.getAchievementsClient(act).achievementsIntent }
    }

    /** achievement_unlocked(achievement_id, success, error). */
    @UsedByGodot
    fun unlockAchievement(achievementId: String) {
        val fail = { err: String -> emitSignal(SIG_ACHIEVEMENT.name, achievementId, false, err) }
        val act = ready(fail) ?: return
        guard(fail) {
            PlayGames.getAchievementsClient(act).unlockImmediate(achievementId).addOnCompleteListener { task ->
                if (task.isSuccessful) emitSignal(SIG_ACHIEVEMENT.name, achievementId, true, "") else fail(errorCode(task))
            }
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onMainActivityResult(requestCode, resultCode, data)
        if (requestCode == RC_UI && openUi.isNotEmpty()) {
            val kind = openUi
            openUi = ""
            emitSignal(SIG_UI_CLOSED.name, kind)
        }
    }

    // ---------- helpers ----------

    private fun showIntent(act: Activity, kind: String, intent: () -> Task<Intent>) {
        val fail = { err: String -> emitSignal(SIG_UI.name, kind, false, err) }
        guard(fail) {
            intent().addOnCompleteListener { task ->
                val i = if (task.isSuccessful) task.result else null
                if (i == null) {
                    fail(if (task.isSuccessful) "no_intent" else errorCode(task))
                    return@addOnCompleteListener
                }
                runOnUiThread {
                    try {
                        openUi = kind
                        act.startActivityForResult(i, RC_UI)
                        emitSignal(SIG_UI.name, kind, true, "")
                    } catch (t: Throwable) {
                        openUi = ""
                        Log.w(TAG, "start $kind failed", t)
                        fail("error:${t.message ?: t.javaClass.simpleName}")
                    }
                }
            }
        }
    }

    /** The activity when the SDK is usable, else reports why through [fail] and returns null. */
    private fun ready(fail: (String) -> Unit): Activity? {
        if (!initialized) {
            if (appId.isEmpty()) appId = readAppId()
            activity?.let { if (appId.isNotEmpty()) setUp(it) }
        }
        if (!isEnabled()) {
            fail("disabled")
            return null
        }
        val act = activity
        if (act == null) fail("no_activity")
        return act
    }

    private inline fun guard(fail: (String) -> Unit, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.w(TAG, "call failed", t)
            fail("error:${t.message ?: t.javaClass.simpleName}")
        }
    }

    private fun errorCode(task: Task<*>): String {
        if (task.isCanceled) return "canceled"
        val e = task.exception ?: return "error:unknown"
        Log.w(TAG, "task failed", e)
        return if (e is ApiException) "api:${e.statusCode}" else "error:${e.message ?: e.javaClass.simpleName}"
    }

    /** APP_ID from the app manifest; any non-blank value (string or, if unescaped, a number) counts. */
    private fun readAppId(): String {
        val ctx = activity ?: context
        return try {
            val pm = ctx.packageManager
            val info = if (Build.VERSION.SDK_INT >= 33) {
                pm.getApplicationInfo(ctx.packageName, PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()))
            } else {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(ctx.packageName, PackageManager.GET_META_DATA)
            }
            info.metaData?.get(APP_ID_KEY)?.toString()?.trim().orEmpty()
        } catch (t: Throwable) {
            Log.w(TAG, "reading $APP_ID_KEY failed", t)
            ""
        }
    }
}
