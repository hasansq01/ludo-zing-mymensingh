package com.flipfold.ludozing.notifications

import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * The content provider that serves the share picture to the app the player picks in the system share sheet. Its own
 * class (and authority, "<applicationId>.lzshare") so it can't clash with a FileProvider of another library; the
 * served folder is only the cache's lz_share/ (res/xml/lz_share_paths.xml).
 */
class ShareFileProvider : FileProvider()

/** The system share sheet: text, or a picture with text. Used by NotificationsPlugin.share(). */
internal object Share {
    private const val TAG = Notifs.TAG
    private const val DIR = "lz_share"
    private const val AUTHORITY_SUFFIX = ".lzshare"

    /**
     * Opens the chooser for [text] (and the PNG at [imagePath], an absolute path the game can read: it is copied into
     * the cache first, so the provider never serves the game's own files). A picture that can't be read is skipped:
     * the text still goes. Returns false when nothing could be shown.
     */
    fun send(act: Activity, text: String, imagePath: String): Boolean {
        val uri = copyToCache(act, imagePath)
        val send = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_TEXT, text)
        if (uri != null) {
            send.type = "image/png"
            send.putExtra(Intent.EXTRA_STREAM, uri)
            // the chooser's own preview reads the picture too, and some targets only honour the clip
            send.clipData = ClipData.newRawUri("", uri)
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            send.type = "text/plain"
        }
        val chooser = Intent.createChooser(send, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            act.startActivity(chooser)
            true
        } catch (t: Throwable) {
            Log.w(TAG, "share: no chooser", t)
            false
        }
    }

    private fun copyToCache(ctx: Context, path: String): Uri? {
        if (path.isEmpty()) return null
        return try {
            val src = File(path)
            if (!src.isFile) return null
            val dir = File(ctx.cacheDir, DIR).apply { mkdirs() }
            // one file per picture name, so repeated shares don't pile up in the cache
            val dst = File(dir, src.name)
            src.copyTo(dst, overwrite = true)
            FileProvider.getUriForFile(ctx, ctx.packageName + AUTHORITY_SUFFIX, dst)
        } catch (t: Throwable) {
            Log.w(TAG, "share: picture skipped", t)
            null
        }
    }
}
