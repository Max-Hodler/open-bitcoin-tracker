package com.openbitcointracker.app

import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
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
