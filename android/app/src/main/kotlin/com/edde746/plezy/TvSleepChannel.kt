package com.edde746.plezy

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Activity
import android.app.UiModeManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class TvSleepChannel(private val activity: Activity) {
  private var channel: MethodChannel? = null

  fun attach(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, "com.vexilyze/tv_sleep").also {
      it.setMethodCallHandler(::onMethodCall)
    }
  }

  fun dispose() {
    channel?.setMethodCallHandler(null)
    channel = null
  }

  private fun isSupported(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
    val pm = activity.packageManager
    if (pm.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE)) return false
    val uiMode = activity.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
    return uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
      pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
      pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
      pm.hasSystemFeature("amazon.hardware.fire_tv")
  }

  private fun isEnabled(): Boolean {
    val manager = activity.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager ?: return false
    val component = ComponentName(activity, TvSleepAccessibilityService::class.java)
    return manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).any {
      val service = it.resolveInfo.serviceInfo
      ComponentName(service.packageName, service.name) == component
    }
  }

  private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      when (call.method) {
        "getStatus" -> result.success(
          mapOf(
            "supported" to isSupported(),
            "enabled" to isEnabled(),
            "ready" to TvSleepAccessibilityService.isConnected
          )
        )
        "openAccessibilitySettings" -> {
          if (!isSupported()) {
            result.success(false)
            return
          }
          activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
          result.success(true)
        }
        "sleep" -> {
          if (!isSupported()) {
            result.success("unsupported")
            return
          }
          if (!isEnabled() || !TvSleepAccessibilityService.isConnected) {
            result.success("permissionRequired")
            return
          }
          // Playback has paused and saved progress before this call. Do not let
          // the Activity's deep-link wake flags undo the requested screen lock.
          activity.window.clearFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
              WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
          )
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) activity.setTurnScreenOn(false)
          result.success(if (TvSleepAccessibilityService.sleep()) "requested" else "failed")
        }
        else -> result.notImplemented()
      }
    } catch (error: Exception) {
      result.error("TV_SLEEP_FAILED", error.message ?: error.javaClass.simpleName, null)
    }
  }
}
