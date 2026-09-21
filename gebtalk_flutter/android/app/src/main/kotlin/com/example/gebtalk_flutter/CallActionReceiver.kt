package com.example.gebtalk_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class CallActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ANSWER = "com.example.gebtalk_flutter.ACTION_ANSWER"
        const val ACTION_DECLINE = "com.example.gebtalk_flutter.ACTION_DECLINE"
        private const val TAG = "CallActionReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val callId = intent.getStringExtra("call_id")
        val callerId = intent.getStringExtra("caller_id")
        val callerName = intent.getStringExtra("caller_name")

        Log.d(TAG, "Received call action: $action for call $callId")

        // Stop the ringing immediately
        GebtalkBackgroundService.stopRinging()

        when (action) {
            ACTION_ANSWER -> {
                // Launch MainActivity directly into the call
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    this.action = "ACTION_ANSWER_CALL"
                    putExtra("call_id", callId)
                    putExtra("caller_id", callerId)
                    putExtra("caller_name", callerName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                context.startActivity(launchIntent)
            }

            ACTION_DECLINE -> {
                // Post call decline to backend in a background thread
                if (!callId.isNullOrEmpty()) {
                    val prefs = context.getSharedPreferences(GebtalkBackgroundService.PREFS_NAME, Context.MODE_PRIVATE)
                    var baseUrl = prefs.getString(GebtalkBackgroundService.PREF_BASE_URL, null)
                    if (!baseUrl.isNullOrEmpty()) {
                        if (baseUrl.endsWith("/")) baseUrl = baseUrl.substring(0, baseUrl.length - 1)
                        if (!baseUrl.endsWith("/api")) baseUrl = "$baseUrl/api"

                        val token = prefs.getString(GebtalkBackgroundService.PREF_AUTH_TOKEN, null)

                        thread {
                            try {
                                val url = URL("$baseUrl/calls/end")
                                val conn = url.openConnection() as HttpURLConnection
                                conn.requestMethod = "POST"
                                conn.connectTimeout = 4000
                                conn.readTimeout = 4000
                                conn.doOutput = true
                                conn.setRequestProperty("Content-Type", "application/json")
                                if (!token.isNullOrEmpty()) {
                                    conn.setRequestProperty("Authorization", "Bearer $token")
                                }

                                val body = JSONObject().apply {
                                    put("call_id", callId)
                                    put("status", "declined")
                                }

                                val writer = OutputStreamWriter(conn.outputStream)
                                writer.write(body.toString())
                                writer.flush()
                                writer.close()

                                Log.d(TAG, "Call $callId declined response code: ${conn.responseCode}")
                                conn.disconnect()
                            } catch (e: Exception) {
                                Log.e(TAG, "Error declining call on server: ${e.message}")
                            }
                        }
                    }
                }
            }
        }
    }
}
