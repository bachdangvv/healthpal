package com.example.healthpal

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "healthpal/health_connect"
    private val activityRecognitionRequestCode = 7042
    private var activityRecognitionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestActivityRecognition" -> requestActivityRecognition(result)
                    "openSettings" -> openHealthConnectSettings(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestActivityRecognition(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
                PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        activityRecognitionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
            activityRecognitionRequestCode,
        )
    }

    private fun openHealthConnectSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent("android.health.connect.action.MANAGE_HEALTH_PERMISSIONS")
                .putExtra("android.health.connect.extra.PACKAGE_NAME", packageName)
            startActivity(intent)
            result.success(null)
        } catch (_: Exception) {
            try {
                startActivity(Intent("android.health.connect.action.HEALTH_CONNECT_SETTINGS"))
                result.success(null)
            } catch (fallback: Exception) {
                result.error("SETTINGS_UNAVAILABLE", fallback.message, null)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == activityRecognitionRequestCode) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            activityRecognitionResult?.success(granted)
            activityRecognitionResult = null
        }
    }
}
