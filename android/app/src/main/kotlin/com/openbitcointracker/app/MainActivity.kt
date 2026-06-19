package com.openbitcointracker.app

import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Allow content to render behind the display cutout (front camera) on
        // all edges. ALWAYS (API 31+) covers landscape edges too; SHORT_EDGES
        // only covers the short sides and misses the cutout in landscape on
        // some devices. Must reassign via window.attributes = ... for the
        // change to take effect — mutating the object in place is not enough.
        val attrs = window.attributes
        attrs.layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        } else {
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        window.attributes = attrs
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.openbitcointracker.app/platform_security",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // FLAG_SECURE is toggled (not set statically) so it tracks the
                // stacks-lock setting: enabled -> blank recents thumbnail and
                // block capture; disabled -> the user keeps screenshots.
                "setSecureScreen" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                // Monotonic ms since boot (counts through deep sleep). Used to
                // anchor the PIN cooldown so changing the wall clock in
                // Settings can't bypass it.
                "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())
                else -> result.notImplemented()
            }
        }
    }
}
