package com.flipfold.ludozing.notifications

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream

/**
 * Crash / unexpected-exit diagnostics for the game's CrashWatch (res://scripts/core/crash_watch.gd), reached through
 * NotificationsPlugin.diag_info() / diag_set_state() (this plugin is in every Gradle export, so it is always loaded).
 *
 * info(): the device and app facts plus, on Android 11+, the last few ApplicationExitInfo records of this app's main
 * process (ActivityManager.getHistoricalProcessExitReasons): why the previous process ended (low memory, a crash, a
 * native crash, an ANR, the user ...), its importance (foreground / cached ...), PSS / RSS, time, description and the
 * process-state summary the game set (its session id). For the newest native crash or ANR newer than `sinceMs`, the
 * trace too: an ANR's is text (the start is kept), a native crash's (Android 12+) is a protobuf tombstone, turned
 * here into debuggerd's text format (signal, abort message, the crashing thread's backtrace with BuildIds, the
 * process's last log lines) so ndk-stack can symbolicate it. Traces are capped at TRACE_MAX characters.
 * Everything is best effort: any failure leaves the field out (and is logged), never throws.
 */
internal object Diag {
    private const val TAG = "LZDiag"
    const val TRACE_MAX = 64 * 1024
    private const val TRACE_READ_MAX = 4 * 1024 * 1024   // bytes read from a trace stream at most
    private const val SUMMARY_MAX = 128                  // ActivityManager.setProcessStateSummary's limit

    private val REASONS = arrayOf(
        "unknown", "exit_self", "signaled", "low_memory", "crash", "crash_native", "anr", "initialization_failure",
        "permission_change", "excessive_resource_usage", "user_requested", "user_stopped", "dependency_died", "other",
        "freezer", "package_state_change", "package_updated",
    )

    fun reasonName(r: Int): String = REASONS.getOrNull(r) ?: "reason_$r"

    fun importanceName(i: Int): String = when {
        i <= 100 -> "foreground"
        i <= 125 -> "foreground_service"
        i <= 200 -> "visible"
        i <= 230 -> "perceptible"
        i <= 300 -> "service"
        i <= 325 -> "top_sleeping"
        i <= 350 -> "cant_save_state"
        i <= 400 -> "cached"
        else -> "gone"
    }

    /** The game's session id (or any short text), returned with this process's exit record on the next launch. */
    fun setSummary(ctx: Context, summary: String) {
        if (Build.VERSION.SDK_INT < 30) return
        try {
            var bytes = summary.toByteArray(Charsets.UTF_8)
            if (bytes.size > SUMMARY_MAX) bytes = bytes.copyOf(SUMMARY_MAX)
            ctx.getSystemService(ActivityManager::class.java)?.setProcessStateSummary(bytes)
        } catch (t: Throwable) {
            Log.w(TAG, "setProcessStateSummary failed", t)
        }
    }

    fun info(ctx: Context, sinceMs: Long, maxExits: Int): JSONObject {
        val o = JSONObject()
        guard("build") {
            o.put("sdk", Build.VERSION.SDK_INT)
            o.put("release", Build.VERSION.RELEASE ?: "")
            o.put("manufacturer", Build.MANUFACTURER ?: "")
            o.put("brand", Build.BRAND ?: "")
            o.put("model", Build.MODEL ?: "")
            o.put("device", Build.DEVICE ?: "")
            o.put("hardware", Build.HARDWARE ?: "")
            o.put("abi", Build.SUPPORTED_ABIS.firstOrNull() ?: "")
            if (Build.VERSION.SDK_INT >= 31) {
                o.put("soc", "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}".trim())
            }
            o.put("fingerprint", Build.FINGERPRINT ?: "")
        }
        val pkg = ctx.packageName
        guard("package") {
            val pi = ctx.packageManager.getPackageInfo(pkg, 0)
            o.put("version_code", if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else @Suppress("DEPRECATION") pi.versionCode.toLong())
            o.put("version_name", pi.versionName ?: "")
            o.put("installer", installer(ctx, pkg))
        }
        val am = ctx.getSystemService(ActivityManager::class.java)
        if (am != null) {
            guard("memory") {
                val mi = ActivityManager.MemoryInfo()
                am.getMemoryInfo(mi)
                o.put("ram_total_mb", mi.totalMem / 1048576L)
                o.put("ram_avail_mb", mi.availMem / 1048576L)
                o.put("ram_threshold_mb", mi.threshold / 1048576L)
                o.put("ram_low_now", mi.lowMemory)
                o.put("low_ram_device", am.isLowRamDevice)
                o.put("mem_class_mb", am.memoryClass)
                o.put("large_mem_class_mb", am.largeMemoryClass)
            }
            if (Build.VERSION.SDK_INT >= 30) guard("exits") { o.put("exits", exits(am, pkg, sinceMs, maxExits)) }
        }
        return o
    }

    private fun installer(ctx: Context, pkg: String): String = try {
        if (Build.VERSION.SDK_INT >= 30) {
            ctx.packageManager.getInstallSourceInfo(pkg).installingPackageName ?: ""
        } else {
            @Suppress("DEPRECATION") ctx.packageManager.getInstallerPackageName(pkg) ?: ""
        }
    } catch (t: Throwable) {
        ""
    }

    @android.annotation.TargetApi(30)
    private fun exits(am: ActivityManager, pkg: String, sinceMs: Long, maxExits: Int): JSONArray {
        val out = JSONArray()
        var traced = false
        for (e in am.getHistoricalProcessExitReasons(pkg, 0, maxExits.coerceIn(1, 16))) {
            if (e.processName != pkg) continue                 // (a :service process, if one ever exists)
            val x = JSONObject()
            x.put("reason", reasonName(e.reason))
            x.put("code", e.reason)
            x.put("status", e.status)
            x.put("importance", e.importance)
            x.put("importance_name", importanceName(e.importance))
            x.put("pss_kb", e.pss)
            x.put("rss_kb", e.rss)
            x.put("at", e.timestamp)
            x.put("description", (e.description ?: "").take(2000))
            x.put("pid", e.pid)
            val sum = e.processStateSummary
            if (sum != null && sum.isNotEmpty()) x.put("summary", String(sum, Charsets.UTF_8))
            val wantTrace = !traced && e.timestamp > sinceMs &&
                (e.reason == ApplicationExitInfo.REASON_ANR || e.reason == ApplicationExitInfo.REASON_CRASH_NATIVE)
            if (wantTrace) {
                traced = true
                guard("trace") {
                    val text = e.traceInputStream?.use { readTrace(it, e.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) }
                    if (!text.isNullOrEmpty()) x.put("trace", text)
                }
            }
            out.put(x)
        }
        return out
    }

    private fun readTrace(input: InputStream, native: Boolean): String {
        val bytes = readUpTo(input, TRACE_READ_MAX)
        if (native) {
            val text = try {
                Tombstone.toText(bytes)
            } catch (t: Throwable) {
                Log.w(TAG, "tombstone not parsed (${bytes.size} bytes)", t)
                null
            }
            if (text != null) return text.take(TRACE_MAX)
        }
        if (looksLikeText(bytes)) return String(bytes, Charsets.UTF_8).take(TRACE_MAX)
        return "[binary trace, ${bytes.size} bytes, not parsed]"
    }

    private fun readUpTo(input: InputStream, max: Int): ByteArray {
        val buf = java.io.ByteArrayOutputStream()
        val chunk = ByteArray(16384)
        while (buf.size() < max) {
            val n = input.read(chunk, 0, minOf(chunk.size, max - buf.size()))
            if (n <= 0) break
            buf.write(chunk, 0, n)
        }
        return buf.toByteArray()
    }

    private fun looksLikeText(b: ByteArray): Boolean {
        val n = minOf(b.size, 2048)
        if (n == 0) return false
        var bad = 0
        for (i in 0 until n) {
            val c = b[i].toInt() and 0xff
            if (c < 9 || (c in 14..31)) bad++
        }
        return bad * 50 < n
    }

    private inline fun guard(what: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.w(TAG, "$what failed", t)
        }
    }

    /**
     * The Android 12+ native-crash tombstone (AOSP system/core/debuggerd/proto/tombstone.proto) as debuggerd's text:
     * header, signal / abort / cause, the crashing thread's backtrace (rel_pc, file, function, BuildId), then the
     * process's last log lines. A tiny protobuf reader: only the fields used here are decoded.
     */
    object Tombstone {
        private val ARCH = arrayOf("arm", "arm64", "x86", "x86_64", "riscv64")
        private const val LOG_LINES = 80

        private class Reader(val b: ByteArray, var p: Int, val end: Int) {
            fun more() = p < end
            fun varint(): Long {
                var r = 0L
                var s = 0
                while (true) {
                    require(p < end) { "truncated varint" }
                    val x = b[p++].toInt() and 0xff
                    r = r or ((x and 0x7f).toLong() shl s)
                    if (x and 0x80 == 0) return r
                    s += 7
                    require(s < 64) { "bad varint" }
                }
            }
            /** The next field as (number, wire type, value): Long for varint / fixed, Reader for length-delimited. */
            fun next(): Triple<Int, Int, Any> {
                val key = varint()
                val field = (key ushr 3).toInt()
                return when (val wire = (key and 7).toInt()) {
                    0 -> Triple(field, wire, varint())
                    1 -> { require(p + 8 <= end); var v = 0L; for (i in 0 until 8) v = v or ((b[p + i].toLong() and 0xff) shl (8 * i)); p += 8; Triple(field, wire, v) }
                    2 -> { val n = varint().toInt(); require(n >= 0 && p + n <= end) { "bad length" }; val r = Reader(b, p, p + n); p += n; Triple(field, wire, r) }
                    5 -> { require(p + 4 <= end); var v = 0L; for (i in 0 until 4) v = v or ((b[p + i].toLong() and 0xff) shl (8 * i)); p += 4; Triple(field, wire, v) }
                    else -> throw IllegalArgumentException("wire type $wire")
                }
            }
            fun str(): String = String(b, p, end - p, Charsets.UTF_8)
        }

        private class Frame(var relPc: Long = 0, var fn: String = "", var fnOff: Long = 0, var file: String = "",
                            var mapOff: Long = 0, var buildId: String = "")

        private class Thread(var id: Long = 0, var name: String = "", val frames: MutableList<Frame> = mutableListOf(),
                             val notes: MutableList<String> = mutableListOf())

        fun toText(bytes: ByteArray): String {
            val r = Reader(bytes, 0, bytes.size)
            var arch = -1L
            var fingerprint = ""
            var revision = ""
            var timestamp = ""
            var pid = 0L
            var tid = 0L
            var uid = 0L
            var uptime = -1L
            val cmd = mutableListOf<String>()
            var sig = ""
            var abort = ""
            val causes = mutableListOf<String>()
            val threads = HashMap<Long, Thread>()
            val logs = ArrayList<String>()
            while (r.more()) {
                val (f, _, v) = r.next()
                when (f) {
                    1 -> arch = v as Long
                    2 -> fingerprint = (v as Reader).str()
                    3 -> revision = (v as Reader).str()
                    4 -> timestamp = (v as Reader).str()
                    5 -> pid = v as Long
                    6 -> tid = v as Long
                    7 -> uid = v as Long
                    9 -> cmd.add((v as Reader).str())
                    10 -> sig = signal(v as Reader)
                    14 -> abort = (v as Reader).str()
                    15 -> cause(v as Reader)?.let { causes.add(it) }
                    16 -> threadEntry(v as Reader)?.let { threads[it.id] = it }
                    18 -> logBuffer(v as Reader, logs)
                    20 -> uptime = v as Long
                }
            }
            val sb = StringBuilder()
            sb.append("*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***\n")
            if (fingerprint.isNotEmpty()) sb.append("Build fingerprint: '").append(fingerprint).append("'\n")
            if (revision.isNotEmpty()) sb.append("Revision: '").append(revision).append("'\n")
            if (arch >= 0) sb.append("ABI: '").append(ARCH.getOrNull(arch.toInt()) ?: "arch$arch").append("'\n")
            if (timestamp.isNotEmpty()) sb.append("Timestamp: ").append(timestamp).append('\n')
            if (uptime >= 0) sb.append("Process uptime: ").append(uptime).append("s\n")
            if (cmd.isNotEmpty()) sb.append("Cmdline: ").append(cmd.joinToString(" ")).append('\n')
            val crashed = threads[tid]
            sb.append("pid: ").append(pid).append(", tid: ").append(tid).append(", name: ")
                .append(crashed?.name ?: "?").append("  >>> ").append(cmd.firstOrNull() ?: "?").append(" <<<\n")
            sb.append("uid: ").append(uid).append('\n')
            if (sig.isNotEmpty()) sb.append(sig).append('\n')
            if (abort.isNotEmpty()) sb.append("Abort message: '").append(abort).append("'\n")
            for (c in causes) sb.append("Cause: ").append(c).append('\n')
            if (crashed != null) {
                for (n in crashed.notes) sb.append("  NOTE: ").append(n).append('\n')
                sb.append("\nbacktrace:\n")
                appendFrames(sb, crashed, arch == 1L || arch == 3L || arch == 4L)
            }
            // the other threads' names (their stacks would not fit; the crashing one is what matters)
            val others = threads.values.filter { it.id != tid }.sortedBy { it.id }
            if (others.isNotEmpty()) {
                sb.append("\nother threads (").append(others.size).append("): ")
                sb.append(others.joinToString(", ") { "${it.id} ${it.name}" }.take(4000)).append('\n')
            }
            if (logs.isNotEmpty()) {
                sb.append("\n--- log (last ").append(minOf(logs.size, LOG_LINES)).append(" lines) ---\n")
                for (l in logs.takeLast(LOG_LINES)) sb.append(l).append('\n')
            }
            return sb.toString()
        }

        private fun appendFrames(sb: StringBuilder, t: Thread, wide: Boolean) {
            for ((i, fr) in t.frames.withIndex()) {
                sb.append("      #").append(String.format("%02d", i)).append(" pc ")
                sb.append(if (wide) String.format("%016x", fr.relPc) else String.format("%08x", fr.relPc))
                sb.append("  ").append(if (fr.file.isEmpty()) "<unknown>" else fr.file)
                if (fr.mapOff != 0L) sb.append(" (offset 0x").append(java.lang.Long.toHexString(fr.mapOff)).append(')')
                if (fr.fn.isNotEmpty()) sb.append(" (").append(fr.fn).append('+').append(fr.fnOff).append(')')
                if (fr.buildId.isNotEmpty()) sb.append(" (BuildId: ").append(fr.buildId).append(')')
                sb.append('\n')
                if (sb.length > TRACE_MAX) return
            }
        }

        private fun signal(r: Reader): String {
            var number = 0L
            var name = ""
            var code = 0L
            var codeName = ""
            var hasFault = false
            var fault = 0L
            while (r.more()) {
                val (f, _, v) = r.next()
                when (f) {
                    1 -> number = v as Long
                    2 -> name = (v as Reader).str()
                    3 -> code = v as Long
                    4 -> codeName = (v as Reader).str()
                    8 -> hasFault = (v as Long) != 0L
                    9 -> fault = v as Long
                }
            }
            val addr = if (hasFault) "0x" + java.lang.Long.toHexString(fault) else "--------"
            return "signal ${number.toInt()} ($name), code ${code.toInt()} ($codeName), fault addr $addr"
        }

        private fun cause(r: Reader): String? {
            while (r.more()) {
                val (f, _, v) = r.next()
                if (f == 1) return (v as Reader).str()
            }
            return null
        }

        /** One entry of map<uint32, Thread>: {1: key, 2: Thread}. */
        private fun threadEntry(r: Reader): Thread? {
            var t: Thread? = null
            while (r.more()) {
                val (f, _, v) = r.next()
                if (f == 2) t = thread(v as Reader)
            }
            return t
        }

        private fun thread(r: Reader): Thread {
            val t = Thread()
            while (r.more()) {
                val (f, _, v) = r.next()
                when (f) {
                    1 -> t.id = (v as Long).toInt().toLong()
                    2 -> t.name = (v as Reader).str()
                    4 -> t.frames.add(frame(v as Reader))
                    7 -> t.notes.add((v as Reader).str())
                }
            }
            return t
        }

        private fun frame(r: Reader): Frame {
            val fr = Frame()
            while (r.more()) {
                val (f, _, v) = r.next()
                when (f) {
                    1 -> fr.relPc = v as Long
                    4 -> fr.fn = (v as Reader).str()
                    5 -> fr.fnOff = v as Long
                    6 -> fr.file = (v as Reader).str()
                    7 -> fr.mapOff = v as Long
                    8 -> fr.buildId = (v as Reader).str()
                }
            }
            return fr
        }

        /** LogBuffer {1 name, 2 repeated LogMessage {1 timestamp, 2 pid, 3 tid, 4 priority, 5 tag, 6 message}}. */
        private fun logBuffer(r: Reader, out: MutableList<String>) {
            var name = ""
            while (r.more()) {
                val (f, _, v) = r.next()
                when (f) {
                    1 -> name = (v as Reader).str()
                    2 -> {
                        val m = v as Reader
                        var ts = ""
                        var prio = 0L
                        var tag = ""
                        var msg = ""
                        while (m.more()) {
                            val (g, _, w) = m.next()
                            when (g) {
                                1 -> ts = (w as Reader).str()
                                4 -> prio = w as Long
                                5 -> tag = (w as Reader).str()
                                6 -> msg = (w as Reader).str()
                            }
                        }
                        val p = "??VDIWEF".getOrElse(prio.toInt()) { '?' }
                        out.add("$ts $p $tag: ${msg.trimEnd().take(400)}" + if (name == "crash") " [crash]" else "")
                        if (out.size > 4 * LOG_LINES) out.subList(0, out.size - LOG_LINES).clear()
                    }
                }
            }
        }
    }
}
