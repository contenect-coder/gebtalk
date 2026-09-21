package com.example.gebtalk_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            Log.d(TAG, "Device reboot completed. Checking saved user credentials for GebtalkBackgroundService.")
            
            val prefs = context.getSharedPreferences(GebtalkBackgroundService.PREFS_NAME, Context.MODE_PRIVATE)
            val userId = prefs.getString(GebtalkBackgroundService.PREF_USER_ID, null)
            val baseUrl = prefs.getString(GebtalkBackgroundService.PREF_BASE_URL, null)

            if (!userId.isNullOrEmpty() && !baseUrl.isNullOrEmpty()) {
                Log.d(TAG, "Restarting GebtalkBackgroundService for user: $userId")
                val serviceIntent = Intent(context, GebtalkBackgroundService::class.java).apply {
                    putExtra("user_id", userId)
                    putExtra("base_url", baseUrl)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
        }
    }
}
