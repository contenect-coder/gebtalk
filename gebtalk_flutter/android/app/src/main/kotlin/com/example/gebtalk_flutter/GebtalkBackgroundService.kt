package com.example.gebtalk_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.Collections
import java.util.LinkedHashSet
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class GebtalkBackgroundService : Service() {

    companion object {
        private const val TAG = "GebtalkBgService"
        const val PREFS_NAME = "gebtalk_bg_prefs"
        const val PREF_USER_ID = "pref_user_id"
        const val PREF_BASE_URL = "pref_base_url"
        const val PREF_AUTH_TOKEN = "pref_auth_token"
        const val PREF_LAST_MSG_ID = "pref_last_msg_id"

        const val ACTION_START_SERVICE = "com.example.gebtalk_flutter.START_SERVICE"
        const val ACTION_STOP_SERVICE = "com.example.gebtalk_flutter.STOP_SERVICE"
        const val ACTION_SET_FOREGROUND = "com.example.gebtalk_flutter.SET_FOREGROUND"

        const val CHANNEL_STATUS_ID = "gebtalk_status_channel"
        const val CHANNEL_CALLS_ID = "gebtalk_calls_channel_v2"
        const val CHANNEL_MESSAGES_ID = "gebtalk_messages_channel"

        const val STATUS_NOTIFICATION_ID = 9001
        const val CALL_NOTIFICATION_ID = 9002
        const val MESSAGE_NOTIFICATION_BASE_ID = 9100

        @Volatile
        var isAppInForeground: Boolean = false

        @Volatile
        var instance: GebtalkBackgroundService? = null

        fun stopRinging() {
            instance?.stopCallAlerts()
        }
    }

    private var executor: ScheduledExecutorService? = null
    private var incomingRingtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var activeRingingCallId: String? = null
    private var prefs: SharedPreferences? = null
    private val notifiedMsgIds = Collections.synchronizedSet(LinkedHashSet<Int>())

    override fun onCreate() {
        super.onCreate()
        instance = this
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibratorManager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val action = intent?.action

            if (action == ACTION_STOP_SERVICE) {
                Log.d(TAG, "Stopping GebtalkBackgroundService requested")
                stopCallAlerts()
                stopPolling()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            if (action == ACTION_SET_FOREGROUND) {
                val isFg = intent.getBooleanExtra("is_foreground", false)
                isAppInForeground = isFg
                Log.d(TAG, "App foreground state updated: $isAppInForeground")
                if (isFg) {
                    // When Flutter opens into foreground, silence service ringtone so only in-app audio plays
                    stopRingtoneOnly()
                }
                return START_STICKY
            }

            // Handle user credentials passed via Intent
            val userId = intent?.getStringExtra("user_id")
            val baseUrl = intent?.getStringExtra("base_url")
            val token = intent?.getStringExtra("auth_token")

            val editor = prefs?.edit()
            if (!userId.isNullOrEmpty()) editor?.putString(PREF_USER_ID, userId)
            if (!baseUrl.isNullOrEmpty()) editor?.putString(PREF_BASE_URL, baseUrl)
            if (!token.isNullOrEmpty()) editor?.putString(PREF_AUTH_TOKEN, token)
            editor?.apply()

            startAsForeground()
            startPolling()
        } catch (e: Exception) {
            Log.e(TAG, "onStartCommand error: ${e.message}")
            // Don't crash the host app — gracefully degrade
        }

        return START_STICKY
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // 1. Silent Background Status Channel
            val statusChannel = NotificationChannel(
                CHANNEL_STATUS_ID,
                "GEBTALK Service Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows that GEBTALK is active in background for incoming calls"
                setShowBadge(false)
            }
            nm.createNotificationChannel(statusChannel)

            // 2. High-Priority Calls Channel (Heads-Up & Lockscreen visibility)
            val callChannel = NotificationChannel(
                CHANNEL_CALLS_ID,
                "GEBTALK Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming voice & video calls alerts"
                // Channel sound is disabled because ringtone is managed cleanly by RingtoneManager loop
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
            }
            nm.createNotificationChannel(callChannel)

            // 3. Messages Channel
            val msgChannel = NotificationChannel(
                CHANNEL_MESSAGES_ID,
                "GEBTALK Chat Messages",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "New chat messages and group updates"
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            nm.createNotificationChannel(msgChannel)
        }
    }

    private fun startAsForeground() {
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            val pendingIntent = PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification: Notification = NotificationCompat.Builder(this, CHANNEL_STATUS_ID)
                .setContentTitle("GEBTALK Active")
                .setContentText("Listening for incoming calls & messages in background")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    startForeground(
                        STATUS_NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "Foreground type fallback: ${e.message}")
                    try {
                        startForeground(STATUS_NOTIFICATION_ID, notification)
                    } catch (e2: Exception) {
                        Log.e(TAG, "Foreground start completely failed: ${e2.message}")
                    }
                }
            } else {
                startForeground(STATUS_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startAsForeground fatal error: ${e.message}")
        }
    }

    private fun startPolling() {
        if (executor != null && !executor!!.isShutdown) return

        executor = Executors.newSingleThreadScheduledExecutor()
        executor?.scheduleWithFixedDelay({
            try {
                pollBackend()
            } catch (e: Exception) {
                Log.e(TAG, "Poll error: ${e.message}")
            }
        }, 1, 2500, TimeUnit.MILLISECONDS)
    }

    private fun stopPolling() {
        executor?.shutdownNow()
        executor = null
    }

    private fun pollBackend() {
        val userId = prefs?.getString(PREF_USER_ID, null) ?: return
        var baseUrl = prefs?.getString(PREF_BASE_URL, null) ?: return
        if (baseUrl.endsWith("/")) baseUrl = baseUrl.substring(0, baseUrl.length - 1)
        if (!baseUrl.endsWith("/api")) baseUrl = "$baseUrl/api"

        val lastMsgId = prefs?.getInt(PREF_LAST_MSG_ID, 0) ?: 0
        val activeCall = activeRingingCallId ?: ""

        val urlStr = "$baseUrl/notifications/poll?user_id=${Uri.encode(userId)}&last_msg_id=$lastMsgId&active_call_id=${Uri.encode(activeCall)}"

        var conn: HttpURLConnection? = null
        try {
            val url = URL(urlStr)
            conn = url.openConnection() as HttpURLConnection
            if (conn is javax.net.ssl.HttpsURLConnection) {
                try {
                    val trustAllCerts = arrayOf<javax.net.ssl.TrustManager>(object : javax.net.ssl.X509TrustManager {
                        override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate>? = null
                        override fun checkClientTrusted(certs: Array<java.security.cert.X509Certificate>?, authType: String?) {}
                        override fun checkServerTrusted(certs: Array<java.security.cert.X509Certificate>?, authType: String?) {}
                    })
                    val sc = javax.net.ssl.SSLContext.getInstance("TLS")
                    sc.init(null, trustAllCerts, java.security.SecureRandom())
                    conn.sslSocketFactory = sc.socketFactory
                    conn.hostnameVerifier = javax.net.ssl.HostnameVerifier { _, _ -> true }
                } catch (_: Exception) {}
            }
            conn.requestMethod = "GET"
            conn.connectTimeout = 4000
            conn.readTimeout = 4000
            conn.setRequestProperty("User-Agent", "GEBTALK-Android-Background")

            val token = prefs?.getString(PREF_AUTH_TOKEN, null)
            if (!token.isNullOrEmpty()) {
                conn.setRequestProperty("Authorization", "Bearer $token")
            }

            val code = conn.responseCode
            if (code == 200) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                val sb = StringBuilder()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    sb.append(line)
                }
                reader.close()

                val json = JSONObject(sb.toString())
                processPollResult(json)
            }
        } catch (e: Exception) {
            // Polling timeout or network reconnecting - expected in background
        } finally {
            conn?.disconnect()
        }
    }

    private fun processPollResult(json: JSONObject) {
        val incomingCallObj = json.optJSONObject("incoming_call")
        val callStatusObj = json.optJSONObject("call_status")
        val newMessagesArr = json.optJSONArray("new_messages")
        val maxMsgId = json.optInt("max_msg_id", 0)

        if (maxMsgId > 0) {
            val curLast = prefs?.getInt(PREF_LAST_MSG_ID, 0) ?: 0
            if (maxMsgId > curLast) {
                prefs?.edit()?.putInt(PREF_LAST_MSG_ID, maxMsgId)?.apply()
            }
        }

        // 1. Handle Incoming VoIP Call
        if (incomingCallObj != null) {
            val callId = incomingCallObj.optString("call_id")
            val callerId = incomingCallObj.optString("caller_id")
            val callerName = incomingCallObj.optString("caller_name", callerId)

            // Trigger alert exactly ONCE per unique ringing call ID
            if (activeRingingCallId != callId) {
                activeRingingCallId = callId
                Log.d(TAG, "New incoming call detected: $callId from $callerName")
                triggerIncomingCallAlert(callId, callerId, callerName)
            }
        } else {
            // No ringing call currently returned -> call was answered, declined, or ended
            if (activeRingingCallId != null) {
                Log.d(TAG, "Call $activeRingingCallId ended or cancelled by caller")
                stopCallAlerts()
            }
        }

        // Check if an active call was explicitly ended or connected
        if (callStatusObj != null) {
            val status = callStatusObj.optString("status")
            if (status == "ended" || status == "cancelled" || status == "declined" || status == "connected" || status == "answered") {
                stopCallAlerts()
            }
        }

        // 2. Handle New Messages (Show notification when app is not in foreground)
        if (!isAppInForeground && newMessagesArr != null && newMessagesArr.length() > 0) {
            for (i in 0 until newMessagesArr.length()) {
                val msgObj = newMessagesArr.optJSONObject(i) ?: continue
                val msgId = msgObj.optInt("id")
                if (msgId <= 0 || notifiedMsgIds.contains(msgId)) {
                    continue
                }
                notifiedMsgIds.add(msgId)
                if (notifiedMsgIds.size > 200) {
                    val it = notifiedMsgIds.iterator()
                    if (it.hasNext()) { it.next(); it.remove() }
                }

                val senderName = msgObj.optString("sender_name", "GEBTALK User")
                val text = msgObj.optString("text", "New message")
                val contactId = msgObj.optString("contact_id", "")

                showChatMessageNotification(msgId, senderName, text, contactId)
            }
        }
    }

    private fun triggerIncomingCallAlert(callId: String, callerId: String, callerName: String) {
        // Only start ringtone and vibration if the app is in the background
        // (If the app is already in the foreground, Flutter's in-app ringtone is already playing)
        if (!isAppInForeground) {
            startRingtoneAndVibration()
        }

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Intent for Answer action BUTTON (tapped explicitly)
        val answerIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_ANSWER
            putExtra("call_id", callId)
            putExtra("caller_id", callerId)
            putExtra("caller_name", callerName)
        }
        val answerPendingIntent = PendingIntent.getBroadcast(
            this, callId.hashCode(), answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent for Decline action BUTTON (tapped explicitly)
        val declineIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_DECLINE
            putExtra("call_id", callId)
        }
        val declinePendingIntent = PendingIntent.getBroadcast(
            this, callId.hashCode() + 1, declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent for tapping notification BODY or heads-up banner to VIEW incoming call (does NOT auto-answer)
        val viewCallIntent = Intent(this, MainActivity::class.java).apply {
            action = "ACTION_VIEW_CALL"
            putExtra("call_id", callId)
            putExtra("caller_id", callerId)
            putExtra("caller_name", callerName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val viewCallPendingIntent = PendingIntent.getActivity(
            this, callId.hashCode() + 2, viewCallIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_CALLS_ID)
            .setContentTitle("📞 Incoming Call")
            .setContentText("$callerName is calling you...")
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .setOngoing(true)
            .setContentIntent(viewCallPendingIntent)
            .setFullScreenIntent(viewCallPendingIntent, true)
            .addAction(android.R.drawable.sym_action_call, "ANSWER", answerPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "DECLINE", declinePendingIntent)
            .build()

        nm.notify(CALL_NOTIFICATION_ID, notification)
    }

    private fun startRingtoneAndVibration() {
        try {
            stopRingtoneOnly()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            incomingRingtone = RingtoneManager.getRingtone(applicationContext, uri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                incomingRingtone?.isLooping = true
            }
            incomingRingtone?.play()

            val pattern = longArrayOf(0, 800, 500, 800, 500, 800)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error playing call ringtone: ${e.message}")
        }
    }

    fun stopRingtoneOnly() {
        try {
            incomingRingtone?.stop()
            incomingRingtone = null
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping ringtone: ${e.message}")
        }
    }

    fun stopCallAlerts() {
        stopRingtoneOnly()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        nm?.cancel(CALL_NOTIFICATION_ID)
        activeRingingCallId = null
    }

    private fun showChatMessageNotification(msgId: Int, senderName: String, text: String, contactId: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val intent = Intent(this, MainActivity::class.java).apply {
            action = "ACTION_OPEN_CHAT"
            putExtra("contact_id", contactId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, msgId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_MESSAGES_ID)
            .setContentTitle(senderName)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()

        nm.notify(MESSAGE_NOTIFICATION_BASE_ID + (msgId % 100), notification)
    }

    override fun onDestroy() {
        stopCallAlerts()
        stopPolling()
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
