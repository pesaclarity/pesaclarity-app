package com.pesaclarity.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// A FragmentActivity so local_auth can show BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    private var sms: SmsChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Blocks screenshots, screen recording and app-switcher previews of financial data.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sms = SmsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sms?.dispose()
        sms = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        sms?.onRequestPermissionsResult(requestCode, grantResults)
    }
}
