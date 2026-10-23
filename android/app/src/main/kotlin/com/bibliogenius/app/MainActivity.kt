package com.bibliogenius.app

import android.provider.Settings
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bibliogenius.app/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getAndroidId") {
                    val androidId = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID
                    )
                    result.success(androidId)
                } else if (call.method == "isGooglePlayServicesAvailable") {
                    // The ML Kit document scanner used for cover photos
                    // ships with Play services; without them the app keeps
                    // the plain camera.
                    val status = GoogleApiAvailability.getInstance()
                        .isGooglePlayServicesAvailable(this)
                    result.success(status == ConnectionResult.SUCCESS)
                } else {
                    result.notImplemented()
                }
            }
    }
}
