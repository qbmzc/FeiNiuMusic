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
        return if (parts.isEmpty()) null else parts.joinToString("\n\n")
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
