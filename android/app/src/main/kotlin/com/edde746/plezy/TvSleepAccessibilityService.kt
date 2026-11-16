package com.edde746.plezy

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.view.accessibility.AccessibilityEvent

/** User-enabled screen lock only. No window content, gestures, or key events are requested. */
class TvSleepAccessibilityService : AccessibilityService() {
  companion object {
    private var connectedService: TvSleepAccessibilityService? = null

    val isConnected: Boolean get() = connectedService != null

    fun sleep(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
      connectedService?.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN) == true
  }

  override fun onServiceConnected() {
    // The timer invokes the service explicitly. It never needs accessibility events.
    serviceInfo = serviceInfo.apply { eventTypes = 0 }
    connectedService = this
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

  override fun onInterrupt() = Unit

  override fun onUnbind(intent: Intent?): Boolean {
    if (connectedService === this) connectedService = null
    return super.onUnbind(intent)
  }

  override fun onDestroy() {
    if (connectedService === this) connectedService = null
    super.onDestroy()
  }
}
