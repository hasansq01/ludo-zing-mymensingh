package com.flipfold.ludozing.admob

import android.util.Log
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import com.google.android.gms.ads.rewarded.ServerSideVerificationOptions
import com.google.android.ump.ConsentDebugSettings
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Rewarded ads for Ludo Zing (Godot v2 Android plugin, Engine singleton "AdMob"): Google Mobile Ads + UMP consent.
 * The GDScript side is res://scripts/net/ads.gd (class Ads); the contract is server/ECONOMY_V1.md section 5.
 *
 * Rewarded only: no banners, no interstitials, and an ad is shown only inside show_rewarded(). Every SDK call runs
 * on the UI thread; every method is safe to call at any time and never throws into GDScript. Answers are signals.
 *
 * Server-side verification: show_rewarded(user_id, custom_data) sets ServerSideVerificationOptions on the loaded ad
 * before showing it; AdMob then calls the server (/v1/ads/ssv) with them. The server, not this plugin, grants.
 */
class AdMobPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "AdMob"

        private val STRING = String::class.java
        private val INT = Int::class.javaObjectType
        private val BOOL = Boolean::class.javaObjectType

        // (can_request_ads, privacy_options_required) answer to request_consent()
        val SIG_CONSENT_DONE = SignalInfo("consent_done", BOOL, BOOL)
        val SIG_LOADED = SignalInfo("rewarded_loaded")
        // (code, message) load failed; code = AdMob's error code
        val SIG_FAILED = SignalInfo("rewarded_failed", INT, STRING)
        // (type, amount) the player earned the reward (the server still has to confirm it)
        val SIG_EARNED = SignalInfo("rewarded_earned", STRING, INT)
        val SIG_CLOSED = SignalInfo("rewarded_closed")
        // (code, message) the ad could not be shown (code -1: none loaded / no activity)
        val SIG_SHOW_FAILED = SignalInfo("rewarded_show_failed", INT, STRING)
    }

    private val initStarted = AtomicBoolean(false)
    // written on the UI thread; read by is_rewarded_ready() from any thread
    @Volatile private var ad: RewardedAd? = null
    private var loading = false
    @Volatile private var showing = false

    override fun getPluginName() = "AdMob"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SIG_CONSENT_DONE, SIG_LOADED, SIG_FAILED, SIG_EARNED, SIG_CLOSED, SIG_SHOW_FAILED,
    )

    /** MobileAds.initialize, once. Only after consent where required: nothing happens while UMP says no. */
    @UsedByGodot
    fun initialize() {
        ui("initialize") {
            val ctx = activity ?: return@ui
            val info = UserMessagingPlatform.getConsentInformation(ctx)
            // canRequestAds() is true when consent isn't required, was given, or the status is unknown (the SDK
            // docs: initialise right away if a previous session already got consent).
            if (!info.canRequestAds()) {
                Log.i(TAG, "initialize skipped: consent doesn't allow ads yet")
                return@ui
            }
            startSdk()
        }
    }

    private fun startSdk() {
        val ctx = activity ?: return
        if (!initStarted.compareAndSet(false, true)) return
        MobileAds.initialize(ctx) { Log.i(TAG, "Mobile Ads SDK ready") }
    }

    /**
     * UMP: request the consent info, show the form when required. -> consent_done(can_request_ads,
     * privacy_options_required). `test_device_hashed_id` (may be "") = a test device for forcing the form in dev.
     * When ads may be requested the SDK is initialised right away.
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
            }
        }
    }

    /** Loads a rewarded ad (one at a time). -> rewarded_loaded or rewarded_failed(code, message). */
    @UsedByGodot
    fun load_rewarded(unit_id: String) {
        ui("load_rewarded") {
            val act = activity
            when {
                act == null -> emitSignal(SIG_FAILED.name, -1, "no activity")
                !UserMessagingPlatform.getConsentInformation(act).canRequestAds() ->
                    emitSignal(SIG_FAILED.name, -2, "consent")
                loading -> Log.i(TAG, "load_rewarded: already loading")
                ad != null -> emitSignal(SIG_LOADED.name)
                else -> {
                    startSdk()
                    loading = true
                    RewardedAd.load(act, unit_id, AdRequest.Builder().build(), object : RewardedAdLoadCallback() {
                        override fun onAdLoaded(loaded: RewardedAd) {
                            loading = false
                            ad = loaded
                            emitSignal(SIG_LOADED.name)
                        }

                        override fun onAdFailedToLoad(error: LoadAdError) {
                            loading = false
                            ad = null
                            emitSignal(SIG_FAILED.name, error.code, error.message)
                        }
                    })
                }
            }
        }
    }

    /** True when a rewarded ad is loaded and can be shown. */
    @UsedByGodot
    fun is_rewarded_ready(): Boolean = ad != null && !showing

    /**
     * Shows the loaded rewarded ad, with server-side verification options (userId, customData) set first.
     * -> rewarded_earned(type, amount) (at most once), rewarded_closed, or rewarded_show_failed(code, message).
     * The ad is used up either way: load_rewarded() again for the next one.
     */
    @UsedByGodot
    fun show_rewarded(user_id: String, custom_data: String) {
        ui("show_rewarded") {
            val act = activity
            val current = ad
            if (act == null || current == null || showing) {
                emitSignal(SIG_SHOW_FAILED.name, -1, if (showing) "already showing" else "not loaded")
                return@ui
            }
            ad = null
            showing = true
            current.setServerSideVerificationOptions(
                ServerSideVerificationOptions.Builder().setUserId(user_id).setCustomData(custom_data).build()
            )
            current.fullScreenContentCallback = object : FullScreenContentCallback() {
                override fun onAdDismissedFullScreenContent() {
                    showing = false
                    emitSignal(SIG_CLOSED.name)
                }

                override fun onAdFailedToShowFullScreenContent(error: AdError) {
                    showing = false
                    emitSignal(SIG_SHOW_FAILED.name, error.code, error.message)
                }
            }
            current.show(act) { reward -> emitSignal(SIG_EARNED.name, reward.type, reward.amount) }
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
