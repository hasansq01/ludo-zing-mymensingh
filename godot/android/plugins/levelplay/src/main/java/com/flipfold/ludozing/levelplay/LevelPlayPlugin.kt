package com.flipfold.ludozing.levelplay

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import com.google.android.ump.ConsentDebugSettings
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import com.unity3d.mediation.LevelPlay
import com.unity3d.mediation.LevelPlayAdError
import com.unity3d.mediation.LevelPlayAdInfo
import com.unity3d.mediation.LevelPlayConfiguration
import com.unity3d.mediation.LevelPlayInitError
import com.unity3d.mediation.LevelPlayInitListener
import com.unity3d.mediation.LevelPlayInitRequest
import com.unity3d.mediation.LevelPlayPrivacySettings
import com.unity3d.mediation.rewarded.LevelPlayReward
import com.unity3d.mediation.rewarded.LevelPlayRewardedAd
import com.unity3d.mediation.rewarded.LevelPlayRewardedAdListener
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Rewarded ads for Ludo Zing (Godot v2 Android plugin, Engine singleton "LevelPlay"): Unity LevelPlay mediation
 * (ironSource Ads only, no extra adapters) + Google's UMP consent form. The same methods and signals as the AdMob
 * plugin, so res://scripts/net/ads.gd (class Ads) drives either; the contract is server/ECONOMY_V1.md section 5.
 *
 * Rewarded only: no banners, no interstitials, and an ad is shown only inside show_rewarded(). Every SDK call runs
 * on the UI thread; every method is safe to call at any time and never throws into GDScript. Answers are signals.
 *
 * Consent: UMP as in the AdMob plugin (the same form, the same stored answer). UMP writes the IAB TCF / Google
 * Additional Consent strings, which LevelPlay reads by itself (SDK 7.7.0+); here we only flag the app as not
 * child-directed and pass a US "do not sell" opt-out when a US Privacy string says so. LevelPlay starts only when
 * UMP says ads may be requested.
 *
 * Server-to-server: show_rewarded(user_id, custom_data) sets LevelPlay_Rewarded_Server_Params "nonce=<custom_data>"
 * and "uid=<user_id>" before showing; LevelPlay then calls the server (/v1/ads/levelplay) with custom_nonce and
 * custom_uid. The server, not this plugin, grants.
 */
class LevelPlayPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "LevelPlay"
        /** <application> meta-data with the LevelPlay app key (godot/addons/levelplay/export_plugin.gd). */
        const val APP_KEY_META = "com.flipfold.ludozing.levelplay.APP_KEY"
        private const val SERVER_PARAMS = "LevelPlay_Rewarded_Server_Params"

        private val STRING = String::class.java
        private val INT = Int::class.javaObjectType
        private val BOOL = Boolean::class.javaObjectType

        // (can_request_ads, privacy_options_required) answer to request_consent()
        val SIG_CONSENT_DONE = SignalInfo("consent_done", BOOL, BOOL)
        val SIG_LOADED = SignalInfo("rewarded_loaded")
        // (code, message) load failed; code = LevelPlay's error code, or ours (-1 no activity, -2 consent, -3 no app
        // key; an init failure passes LevelPlay's init error code)
        val SIG_FAILED = SignalInfo("rewarded_failed", INT, STRING)
        // (type, amount) the player earned the reward (the server still has to confirm it)
        val SIG_EARNED = SignalInfo("rewarded_earned", STRING, INT)
        val SIG_CLOSED = SignalInfo("rewarded_closed")
        // (code, message) the ad could not be shown (code -1: none loaded / already showing / no activity)
        val SIG_SHOW_FAILED = SignalInfo("rewarded_show_failed", INT, STRING)
    }

    private enum class Init { NONE, STARTING, READY }

    // all on the UI thread, except the @Volatile ones that is_rewarded_ready() reads from Godot's thread
    private var init = Init.NONE
    private var pendingUnit: String? = null   // load_rewarded() asked while the SDK was starting
    private var ad: LevelPlayRewardedAd? = null
    private var loading = false
    @Volatile private var loaded = false
    @Volatile private var showing = false
    private var earnedThisShow = false
    private var testSuite = false

    override fun getPluginName() = "LevelPlay"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SIG_CONSENT_DONE, SIG_LOADED, SIG_FAILED, SIG_EARNED, SIG_CLOSED, SIG_SHOW_FAILED,
    )

    /** LevelPlay.init, once. Only after consent where required: nothing happens while UMP says no. */
    @UsedByGodot
    fun initialize() {
        ui("initialize") {
            val ctx = activity ?: return@ui
            if (!UserMessagingPlatform.getConsentInformation(ctx).canRequestAds()) {
                Log.i(TAG, "initialize skipped: consent doesn't allow ads yet")
                return@ui
            }
            startSdk()
        }
    }

    /**
     * Dev only (project setting ludo_zing/ads/levelplay_test_suite): enables LevelPlay's integration test suite and
     * the adapters' debug logs, and opens the suite once the SDK is ready. Call before initialize / load_rewarded.
     */
    @UsedByGodot
    fun set_test_suite(on: Boolean) {
        ui("set_test_suite") {
            testSuite = on
            LevelPlay.setAdaptersDebug(on)
            if (on) LevelPlay.setMetaData("is_test_suite", "enable")
            Log.i(TAG, "test suite: $on")
        }
    }

    /** Opens LevelPlay's integration test suite (only after set_test_suite(true) and a ready SDK). */
    @UsedByGodot
    fun launch_test_suite() {
        ui("launch_test_suite") {
            val ctx = activity ?: return@ui
            if (testSuite && init == Init.READY) LevelPlay.launchTestSuite(ctx.applicationContext)
        }
    }

    private fun appKey(ctx: Context): String = try {
        @Suppress("DEPRECATION")
        val info = ctx.packageManager.getApplicationInfo(ctx.packageName, PackageManager.GET_META_DATA)
        info.metaData?.get(APP_KEY_META)?.toString()?.trim() ?: ""
    } catch (t: Throwable) {
        ""
    }

    /** Starts LevelPlay (once; again after a failed init). Answers the pending load when it is ready or fails. */
    private fun startSdk() {
        val act = activity ?: return
        if (init != Init.NONE) return
        val key = appKey(act)
        if (key.isEmpty()) {
            Log.w(TAG, "no app key ($APP_KEY_META): LevelPlay not started")
            pendingUnit?.let {
                pendingUnit = null
                emitSignal(SIG_FAILED.name, -3, "no app key")
            }
            return
        }
        applyPrivacy(act)
        init = Init.STARTING
        Log.i(TAG, "init: app key $key, SDK ${LevelPlay.getSdkVersion()}")
        LevelPlay.init(act.applicationContext, LevelPlayInitRequest.Builder(key).build(), object : LevelPlayInitListener {
            override fun onInitSuccess(configuration: LevelPlayConfiguration) {
                ui("init success") {
                    init = Init.READY
                    Log.i(TAG, "LevelPlay ready")
                    if (testSuite) LevelPlay.launchTestSuite(act.applicationContext)
                    pendingUnit?.let {
                        pendingUnit = null
                        loadNow(it)
                    }
                }
            }

            override fun onInitFailed(error: LevelPlayInitError) {
                ui("init failed") {
                    // LevelPlay's advice: try again later. The next load_rewarded() (Ads' backoff) does.
                    init = Init.NONE
                    Log.w(TAG, "init failed: ${error.errorCode} ${error.errorMessage}")
                    pendingUnit?.let {
                        pendingUnit = null
                        emitSignal(SIG_FAILED.name, error.errorCode, "init: ${error.errorMessage}")
                    }
                }
            }
        })
    }

    /**
     * Privacy signals for LevelPlay, before init and after the privacy options form: the app is not child-directed
     * (13+), and a US Privacy string ("1YYN": the third letter Y = opted out of sale) becomes setCCPA. GDPR: LevelPlay
     * reads UMP's IAB TCF and Additional Consent strings itself.
     */
    private fun applyPrivacy(ctx: Context) {
        LevelPlayPrivacySettings.setCOPPA(false)
        val usp = ctx.getSharedPreferences("${ctx.packageName}_preferences", Context.MODE_PRIVATE)
            .all["IABUSPrivacy_String"]?.toString() ?: ""
        if (usp.length >= 3 && (usp[2] == 'Y' || usp[2] == 'N')) LevelPlayPrivacySettings.setCCPA(usp[2] == 'Y')
    }

    /**
     * UMP: request the consent info, show the form when required. -> consent_done(can_request_ads,
     * privacy_options_required). `test_device_hashed_id` (may be "") = a test device for forcing the form in dev.
     * When ads may be requested LevelPlay is started right away.
     */
    @UsedByGodot
    fun request_consent(test_device_hashed_id: String) {
        ui("request_consent") {
            val act = activity
            if (act == null) {
                done(false, false)
                return@ui
            }
            val info = UserMessagingPlatform.getConsentInformation(act)
            val params = ConsentRequestParameters.Builder().apply {
                if (test_device_hashed_id.isNotBlank()) {
                    setConsentDebugSettings(
                        ConsentDebugSettings.Builder(act).addTestDeviceHashedId(test_device_hashed_id.trim()).build()
                    )
                }
            }.build()
            info.requestConsentInfoUpdate(act, params, {
                UserMessagingPlatform.loadAndShowConsentFormIfRequired(act) { formError ->
                    if (formError != null) Log.w(TAG, "consent form: ${formError.errorCode} ${formError.message}")
                    done(info.canRequestAds(), info)
                }
            }, { err ->
                Log.w(TAG, "consent info update: ${err.errorCode} ${err.message}")
                // a previous session's consent may still allow ads
                done(info.canRequestAds(), info)
            })
        }
    }

    private fun done(can: Boolean, info: ConsentInformation) =
        done(can, info.privacyOptionsRequirementStatus == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED)

    private fun done(can: Boolean, privacyRequired: Boolean) {
        if (can) startSdk()
        emitSignal(SIG_CONSENT_DONE.name, can, privacyRequired)
    }

    /** The UMP "privacy options" form (Settings > Privacy choices). Answers nothing; the form is its own feedback. */
    @UsedByGodot
    fun show_privacy_options() {
        ui("show_privacy_options") {
            val act = activity ?: return@ui
            UserMessagingPlatform.showPrivacyOptionsForm(act) { formError ->
                if (formError != null) Log.w(TAG, "privacy options: ${formError.errorCode} ${formError.message}")
                applyPrivacy(act)
            }
        }
    }

    /** Loads a rewarded ad of `unit_id` (one at a time). -> rewarded_loaded or rewarded_failed(code, message). */
    @UsedByGodot
    fun load_rewarded(unit_id: String) {
        ui("load_rewarded") {
            val act = activity
            when {
                act == null -> emitSignal(SIG_FAILED.name, -1, "no activity")
                !UserMessagingPlatform.getConsentInformation(act).canRequestAds() ->
                    emitSignal(SIG_FAILED.name, -2, "consent")
                loading || pendingUnit != null -> Log.i(TAG, "load_rewarded: already loading")
                loaded && ad?.adUnitId == unit_id -> emitSignal(SIG_LOADED.name)
                init == Init.READY -> loadNow(unit_id)
                else -> {
                    Log.i(TAG, "load_rewarded: waiting for init")
                    pendingUnit = unit_id
                    startSdk()
                }
            }
        }
    }

    private fun loadNow(unit: String) {
        val current = ad?.takeIf { it.adUnitId == unit }
            ?: LevelPlayRewardedAd(unit).also { it.setListener(listener); ad = it }
        loading = true
        loaded = false
        Log.i(TAG, "loading rewarded ad $unit")
        current.loadAd()
    }

    private val listener = object : LevelPlayRewardedAdListener {
        override fun onAdLoaded(adInfo: LevelPlayAdInfo) {
            loading = false
            loaded = true
            Log.i(TAG, "rewarded ad loaded (${adInfo.adNetwork})")
            emitSignal(SIG_LOADED.name)
        }

        override fun onAdLoadFailed(error: LevelPlayAdError) {
            loading = false
            loaded = false
            Log.i(TAG, "rewarded ad load failed: ${error.errorCode} ${error.errorMessage}")
            emitSignal(SIG_FAILED.name, error.errorCode, error.errorMessage)
        }

        override fun onAdDisplayed(adInfo: LevelPlayAdInfo) {
            Log.i(TAG, "rewarded ad shown")
        }

        override fun onAdRewarded(reward: LevelPlayReward, adInfo: LevelPlayAdInfo) {
            if (earnedThisShow) return
            earnedThisShow = true
            emitSignal(SIG_EARNED.name, reward.name, reward.amount)
        }

        override fun onAdDisplayFailed(error: LevelPlayAdError, adInfo: LevelPlayAdInfo) {
            showing = false
            Log.i(TAG, "rewarded ad show failed: ${error.errorCode} ${error.errorMessage}")
            emitSignal(SIG_SHOW_FAILED.name, error.errorCode, error.errorMessage)
        }

        override fun onAdClosed(adInfo: LevelPlayAdInfo) {
            showing = false
            emitSignal(SIG_CLOSED.name)
        }
    }

    /** True when a rewarded ad is loaded and none is showing. */
    @UsedByGodot
    fun is_rewarded_ready(): Boolean = loaded && !showing

    /**
     * Shows the loaded rewarded ad, with the server-to-server custom parameters (nonce, uid) set first.
     * -> rewarded_earned(type, amount) (at most once), rewarded_closed, or rewarded_show_failed(code, message).
     * The ad is used up either way: load_rewarded() again for the next one.
     */
    @UsedByGodot
    fun show_rewarded(user_id: String, custom_data: String) {
        ui("show_rewarded") {
            val act = activity
            val current = ad
            if (act == null || current == null || !loaded || showing || !current.isAdReady()) {
                if (!showing) loaded = false
                emitSignal(SIG_SHOW_FAILED.name, -1, if (showing) "already showing" else "not loaded")
                return@ui
            }
            loaded = false
            showing = true
            earnedThisShow = false
            LevelPlay.setMetaData(SERVER_PARAMS, listOf("nonce=$custom_data", "uid=$user_id"))
            current.showAd(act)
        }
    }

    private fun ui(what: String, block: () -> Unit) {
        runOnUiThread {
            try {
                block()
            } catch (t: Throwable) {
                Log.w(TAG, "$what failed", t)
            }
        }
    }
}
