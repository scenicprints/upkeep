package com.scenicprints.upkeep

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Reads FuelWise's fuel log straight off the device.
 *
 * FuelWise records an odometer on every fill-up, and it's on the same phone.
 * Routing that through a cloud repo meant creating an access token and
 * pasting it into two apps; copying it by hand meant a chore forever. This
 * asks the neighbouring app directly — no token, no expiry, no network, and
 * nothing for anyone to set up.
 *
 * FuelWise hands over only the cars and each fill-up's odometer and date;
 * its trips and GPS traces are not exposed. Reading is all this does.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "upkeep/fuelwise"
        private const val LOG_URI = "content://com.fuelwise.fuelwise.upkeep/log"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readLog" -> result.success(readLog())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Returns FuelWise's log as JSON, or null when it can't be read —
     * FuelWise not installed, too old to expose the provider, or simply no
     * data yet. Null is not an error here; the Dart side turns each case
     * into something the user can act on.
     */
    private fun readLog(): String? {
        return try {
            contentResolver.query(Uri.parse(LOG_URI), null, null, null, null)
                ?.use { cursor ->
                    if (!cursor.moveToFirst()) return null
                    val text = cursor.getString(0)
                    if (text.isNullOrBlank()) null else text
                }
        } catch (e: Exception) {
            // SecurityException when the provider isn't exported to us, or
            // anything else. Never crash Upkeep over a neighbouring app.
            null
        }
    }
}
