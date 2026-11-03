package com.flipfold.ludozing.notifications

import android.app.Activity
import android.util.Log
import com.google.android.play.core.review.ReviewManagerFactory

/**
 * Google Play In-App Review (com.google.android.play:review) for the game's AppRating
 * (res://scripts/net/app_rating.gd), reached through NotificationsPlugin.review_request().
 *
 * Play decides whether its rating card actually shows (a quota per user, never for an app not installed from Play)
 * and never says whether the player rated, so the one answer is `review_done` (ok, error): ok true = the flow ran to
 * its end (shown or not), false = it could not start ("request:<m>" | "launch:<m>" | "no_activity").
 */
internal class Review(private val emit: (String, Any, Any) -> Unit) {

    companion object {
        private const val TAG = Notifs.TAG
        const val SIG_DONE = "review_done"
    }

    @Volatile private var busy = false

    /** Runs on the UI thread: asks Play for a review flow, then launches it over [activity]. */
    fun request(activity: Activity) {
        if (busy) return
        busy = true
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnCompleteListener { req ->
            if (!req.isSuccessful) {
                done(false, "request:" + (req.exception?.message ?: "failed"))
                return@addOnCompleteListener
            }
            try {
                manager.launchReviewFlow(activity, req.result).addOnCompleteListener { flow ->
                    done(flow.isSuccessful, if (flow.isSuccessful) "" else "launch:" + (flow.exception?.message ?: "failed"))
                }
            } catch (t: Throwable) {
                done(false, "launch:" + (t.message ?: t.javaClass.simpleName))
            }
        }
    }

    private fun done(ok: Boolean, error: String) {
        busy = false
        Log.i(TAG, "review: ${if (ok) "flow done" else error}")
        emit(SIG_DONE, ok, error)
    }
}
