package com.pesaclarity.app

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// A FragmentActivity so local_auth can show BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    private var sms: SmsChannel? = null
    private var documents: DocumentsChannel? = null
    private var share: ShareChannel? = null

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
        documents = DocumentsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        share = ShareChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        DeviceChannel.register(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sms?.dispose()
        sms = null
        documents?.dispose()
        documents = null
        share?.dispose()
        share = null
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documents?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
