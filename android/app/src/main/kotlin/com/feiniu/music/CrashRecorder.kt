package com.feiniu.music

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 记录上一次进程异常退出的原因，供下次启动写入 App 内调试日志。
 *
 * 低端设备（如 1GB 投影）闪退时用户手边往往没有 adb：
 * - Java/Kotlin 未捕获异常：写入堆栈文件后交回系统默认处理；
 * - Android 11+：读取系统记录的退出原因（原生崩溃、内存不足被杀、ANR 等）。
 */
object CrashRecorder {
    private const val TAG = "CrashRecorder"
    private const val CRASH_FILE = "last_crash.txt"
    private const val PREFS = "feiniu_diagnostics"
    private const val KEY_LAST_EXIT_TS = "last_exit_timestamp"
    private const val KEY_LAST_FATAL_LINE = "last_fatal_logcat_line"
    private const val LAUNCH_LOGCAT_FILE = "launch_logcat.txt"
    private const val LOGCAT_LINES = 3000

    /** logcat 中标志进程异常结束的行：原生信号、Java 崩溃、tombstone 摘要。 */
    private val FATAL_MARKERS = Regex(
        "Fatal signal|FATAL EXCEPTION|Abort message|" +
            " F DEBUG |backtrace:|#\\d{2} pc |Out of memory|OutOfMemoryError"
    )

    @Volatile
    private var installed = false

    fun install(context: Context) {
        if (installed) return
        installed = true
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                File(appContext.filesDir, CRASH_FILE).writeText(
                    "${timestamp(System.currentTimeMillis())} 未捕获异常 " +
                        "thread=${thread.name}\n${Log.getStackTraceString(error)}"
                )
            } catch (t: Throwable) {
                Log.w(TAG, "写入崩溃记录失败", t)
            }
            previous?.uncaughtException(thread, error)
        }
    }

    /** 取出（并清除）上一次异常退出的报告；没有则返回 null。 */
    fun takeLastExitReport(context: Context): String? {
        val parts = mutableListOf<String>()
        val crashFile = File(context.filesDir, CRASH_FILE)
        if (crashFile.exists()) {
            try {
                parts += crashFile.readText().take(16_000)
            } catch (t: Throwable) {
                Log.w(TAG, "读取崩溃记录失败", t)
            }
            crashFile.delete()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            exitInfoReport(context)?.let { parts += it }
        }
        // Android 10 及以下没有 ApplicationExitInfo：启动时抓一份 logcat 快照
        // （此时上一进程的日志通常还在缓冲区里），从中找原生崩溃等致命行。
        snapshotLaunchLogcat(context)?.let { parts += it }
        return if (parts.isEmpty()) null else parts.joinToString("\n\n")
    }

    /**
     * 读取本应用（同 uid，含已结束的上一进程）在 main/system/crash 缓冲区的
     * 最近日志。Android 4.1+ 应用无需权限即可读取自己的日志。
     */
    fun readLogcat(maxLines: Int = LOGCAT_LINES): String? = try {
        val process = ProcessBuilder(
            "logcat", "-d", "-v", "threadtime", "-t", maxLines.toString()
        ).redirectErrorStream(true).start()
        val text = process.inputStream.bufferedReader().use { it.readText() }
        process.waitFor()
        text
    } catch (t: Throwable) {
        Log.w(TAG, "读取 logcat 失败", t)
        null
    }

    /** 本次启动时保存的 logcat 快照（包含上一进程结束前的日志）。 */
    fun launchLogcat(context: Context): String? = try {
        File(context.filesDir, LAUNCH_LOGCAT_FILE).takeIf { it.exists() }?.readText()
    } catch (t: Throwable) {
        Log.w(TAG, "读取启动日志快照失败", t)
        null
    }

    /** 保存启动快照，并返回上一进程（未报告过的）致命日志摘录。 */
    private fun snapshotLaunchLogcat(context: Context): String? {
        val text = readLogcat() ?: return null
        try {
            File(context.filesDir, LAUNCH_LOGCAT_FILE).writeText(text)
        } catch (t: Throwable) {
            Log.w(TAG, "保存启动日志快照失败", t)
        }
        val myPid = android.os.Process.myPid().toString()
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val lastReported = prefs.getString(KEY_LAST_FATAL_LINE, "") ?: ""
        // threadtime 格式："MM-DD HH:MM:SS.mmm  PID  TID L TAG: msg"
        val fatal = text.lineSequence()
            .filter { FATAL_MARKERS.containsMatchIn(it) }
            .filter { line ->
                val pid = line.substring(minOf(18, line.length)).trim().substringBefore(' ')
                pid != myPid && line.take(18) > lastReported
            }
            .toList()
        if (fatal.isEmpty()) return null
        prefs.edit().putString(KEY_LAST_FATAL_LINE, fatal.last().take(18)).apply()
        return "logcat 中上一进程的致命日志（完整日志见「手机扫码查看日志」）：\n" +
            fatal.takeLast(80).joinToString("\n")
    }

    private fun exitInfoReport(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = am.getHistoricalProcessExitReasons(context.packageName, 0, 1)
                .firstOrNull() ?: return null
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (info.timestamp <= prefs.getLong(KEY_LAST_EXIT_TS, 0L)) return null
            prefs.edit().putLong(KEY_LAST_EXIT_TS, info.timestamp).apply()
            // 正常退出不报告，只关心异常结束。
            if (info.reason == ApplicationExitInfo.REASON_EXIT_SELF ||
                info.reason == ApplicationExitInfo.REASON_USER_REQUESTED ||
                info.reason == ApplicationExitInfo.REASON_USER_STOPPED ||
                info.reason == ApplicationExitInfo.REASON_PACKAGE_UPDATED
            ) {
                return null
            }
            "${timestamp(info.timestamp)} 系统记录的退出原因：" +
                "${reasonName(info.reason)} status=${info.status} " +
                "importance=${info.importance} pss=${info.pss / 1024}MB " +
                "rss=${info.rss / 1024}MB description=${info.description}"
        } catch (t: Throwable) {
            Log.w(TAG, "读取退出原因失败", t)
            null
        }
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_CRASH -> "CRASH（Java 崩溃）"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE（原生库崩溃）"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY（内存不足被系统结束）"
        ApplicationExitInfo.REASON_ANR -> "ANR（无响应）"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED（被信号结束）"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        else -> "UNKNOWN($reason)"
    }

    private fun timestamp(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(millis))
}
