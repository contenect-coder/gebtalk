package com.example.gebtalk_flutter

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "gebtalk/audio_control"
    private val BG_CHANNEL = "gebtalk/background_service"
    private val PERMISSION_REQ_CODE = 1001
    private val TAG = "MainActivity"

    private var bgMethodChannel: MethodChannel? = null
    private var pendingInitialCall: Map<String, String>? = null
    private var pendingInitialChat: Map<String, String>? = null

    private var audioManager: AudioManager? = null
    private var toneGenerator: ToneGenerator? = null
    private var incomingRingtone: Ringtone? = null
    private var dialToneRunnable: Runnable? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var speakerReapplyRunnable: Runnable? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        enableLockscreenDisplay()
        checkNotificationPermission()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAndRequestMicrophonePermission" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            PERMISSION_REQ_CODE
                        )
                    }
                }
                "setSpeakerphoneOn" -> {
                    val isSpeaker = call.argument<Boolean>("isSpeaker") ?: false
                    applySpeakerphone(isSpeaker)
                    result.success(true)
                }
                "resetAudioMode" -> {
                    resetAudioMode()
                    result.success(true)
                }
                "playOutgoingDialTone" -> {
                    playOutgoingDialTone()
                    result.success(true)
                }
                "playIncomingRingtone" -> {
                    playIncomingRingtone()
                    result.success(true)
                }
                "playCallConnectedChime" -> {
                    playCallConnectedChime()
                    result.success(true)
                }
                "playCallEndedTone" -> {
                    playCallEndedTone()
                    result.success(true)
                }
                "stopAllTones" -> {
                    stopAllTones()
                    GebtalkBackgroundService.stopRinging()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Background VoIP & Notification Service Channel
        bgMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BG_CHANNEL)
        bgMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val userId = call.argument<String>("user_id")
                    val baseUrl = call.argument<String>("base_url")
                    val token = call.argument<String>("auth_token")

                    val intent = Intent(this, GebtalkBackgroundService::class.java).apply {
                        putExtra("user_id", userId)
                        putExtra("base_url", baseUrl)
                        putExtra("auth_token", token)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopService" -> {
                    val intent = Intent(this, GebtalkBackgroundService::class.java).apply {
                        action = GebtalkBackgroundService.ACTION_STOP_SERVICE
                    }
                    startService(intent)
                    result.success(true)
                }
                "setAppForeground" -> {
                    val isFg = call.argument<Boolean>("is_foreground") ?: true
                    GebtalkBackgroundService.isAppInForeground = isFg
                    result.success(true)
                }
                "checkInitialCall" -> {
                    val callData = pendingInitialCall
                    pendingInitialCall = null
                    result.success(callData)
                }
                "checkInitialChat" -> {
                    val chatData = pendingInitialChat
                    pendingInitialChat = null
                    result.success(chatData)
                }
                else -> result.notImplemented()
            }
        }

        // Process any launch intent received when activity started
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        GebtalkBackgroundService.isAppInForeground = true
        GebtalkBackgroundService.instance?.stopRingtoneOnly()
    }

    override fun onPause() {
        super.onPause()
        GebtalkBackgroundService.isAppInForeground = false
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            "ACTION_ANSWER_CALL" -> {
                val callId = intent.getStringExtra("call_id")
                val callerId = intent.getStringExtra("caller_id")
                val callerName = intent.getStringExtra("caller_name")
                if (!callId.isNullOrEmpty()) {
                    val map = mapOf(
                        "call_id" to callId,
                        "caller_id" to (callerId ?: ""),
                        "caller_name" to (callerName ?: "")
                    )
                    pendingInitialCall = map
                    bgMethodChannel?.invokeMethod("onAnswerCall", map)
                }
            }
            "ACTION_VIEW_CALL" -> {
                // User clicked notification to view the call screen without auto-answering
                GebtalkBackgroundService.instance?.stopRingtoneOnly()
                Log.d(TAG, "Opened incoming call screen (ACTION_VIEW_CALL) without auto-answering")
            }
            "ACTION_OPEN_CHAT" -> {
                val contactId = intent.getStringExtra("contact_id")
                if (!contactId.isNullOrEmpty()) {
                    val map = mapOf("contact_id" to contactId)
                    pendingInitialChat = map
                    bgMethodChannel?.invokeMethod("onOpenChat", map)
                }
            }
        }
    }

    private fun enableLockscreenDisplay() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun checkNotificationPermission() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        1002
                    )
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQ_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun requestAudioFocusForCall() {
        val am = audioManager ?: return
        if (audioFocusRequest != null) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val playbackAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                    .setAudioAttributes(playbackAttributes)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener { /* maintain VoIP audio state */ }
                    .build()
                audioFocusRequest = request
                am.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun abandonAudioFocusForCall() {
        val am = audioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
                audioFocusRequest = null
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(null)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applySpeakerphone(isSpeaker: Boolean) {
        val am = audioManager ?: return
        try {
            am.mode = AudioManager.MODE_IN_COMMUNICATION

            // Guarantee hardware microphone is NOT muted
            try {
                am.isMicrophoneMute = false
            } catch (me: Exception) {}

            // Ensure voice call and music stream volumes are audible (at least 90% of max volume)
            try {
                val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                val curVol = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
                if (curVol < (maxVol * 0.70).toInt()) {
                    am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, (maxVol * 0.90).toInt(), 0)
                }
                val musicMax = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val musicCur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                if (musicCur < (musicMax * 0.70).toInt()) {
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, (musicMax * 0.90).toInt(), 0)
                }
            } catch (ve: Exception) {}

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = am.availableCommunicationDevices
                if (isSpeaker) {
                    val speakerDevice = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    if (speakerDevice != null) {
                        am.setCommunicationDevice(speakerDevice)
                    }
                    am.isSpeakerphoneOn = true
                } else {
                    // Check for wired/bluetooth headsets first, otherwise prioritize top earpiece receiver
                    val headsetDevice = devices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                        it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                    }
                    val earpieceDevice = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }

                    val targetDevice = headsetDevice ?: earpieceDevice
                    if (targetDevice != null) {
                        am.setCommunicationDevice(targetDevice)
                    } else {
                        am.clearCommunicationDevice()
                    }
                    am.isSpeakerphoneOn = false
                }
            } else {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = isSpeaker
            }

            // Cancel any previous re-apply to prevent stale device routing races
            speakerReapplyRunnable?.let { mainHandler.removeCallbacks(it) }
            speakerReapplyRunnable = Runnable {
                try {
                    if (am.mode != AudioManager.MODE_IN_COMMUNICATION) {
                        am.mode = AudioManager.MODE_IN_COMMUNICATION
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val devs = am.availableCommunicationDevices
                        if (isSpeaker) {
                            val spk = devs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                            if (spk != null) am.setCommunicationDevice(spk)
                            am.isSpeakerphoneOn = true
                        } else {
                            val hs = devs.firstOrNull {
                                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                            }
                            val ear = devs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
                            val tgt = hs ?: ear
                            if (tgt != null) am.setCommunicationDevice(tgt) else am.clearCommunicationDevice()
                            am.isSpeakerphoneOn = false
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        am.isSpeakerphoneOn = isSpeaker
                    }
                } catch (e: Exception) {}
            }

            speakerReapplyRunnable?.let { mainHandler.postDelayed(it, 250) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun resetAudioMode() {
        val am = audioManager ?: return
        try {
            stopAllTones()
            speakerReapplyRunnable?.let {
                mainHandler.removeCallbacks(it)
                speakerReapplyRunnable = null
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.clearCommunicationDevice()
            }
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = false
            am.mode = AudioManager.MODE_NORMAL
            abandonAudioFocusForCall()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun playOutgoingDialTone() {
        stopAllTones()
        try {
            requestAudioFocusForCall()
            val am = audioManager
            am?.mode = AudioManager.MODE_IN_COMMUNICATION
            applySpeakerphone(false) // Default outgoing ringback to top earpiece receiver

            // Use STREAM_NOTIFICATION so STREAM_VOICE_CALL is never locked when WebRTC's AudioTrack starts
            toneGenerator = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
            var isTonePlaying = false

            dialToneRunnable = object : Runnable {
                override fun run() {
                    if (toneGenerator == null) return
                    try {
                        if (!isTonePlaying) {
                            toneGenerator?.startTone(ToneGenerator.TONE_SUP_RINGTONE, 1200)
                            isTonePlaying = true
                            mainHandler.postDelayed(this, 1200)
                        } else {
                            toneGenerator?.stopTone()
                            isTonePlaying = false
                            mainHandler.postDelayed(this, 2800)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
            dialToneRunnable?.let { mainHandler.post(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun playIncomingRingtone() {
        stopAllTones()
        try {
            val notificationUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            incomingRingtone = RingtoneManager.getRingtone(applicationContext, notificationUri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                incomingRingtone?.isLooping = true
            }
            incomingRingtone?.play()
        } catch (e: Exception) {
            e.printStackTrace()
            // Fallback to ToneGenerator if RingtoneManager fails
            try {
                toneGenerator = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 85)
                toneGenerator?.startTone(ToneGenerator.TONE_CDMA_HIGH_L, -1)
            } catch (e: Exception) {}
        }
    }

    private fun playCallConnectedChime() {
        stopAllTones()
        try {
            // Use STREAM_NOTIFICATION so STREAM_VOICE_CALL is never locked when WebRTC's AudioTrack starts
            val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 70)
            tg.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
            mainHandler.postDelayed({
                try {
                    tg.release()
                } catch (e: Exception) {}
            }, 250)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun playCallEndedTone() {
        stopAllTones()
        try {
            val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
            tg.startTone(ToneGenerator.TONE_SUP_BUSY, 700)
            mainHandler.postDelayed({
                try {
                    tg.release()
                } catch (e: Exception) {}
            }, 800)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAllTones() {
        dialToneRunnable?.let {
            mainHandler.removeCallbacks(it)
            dialToneRunnable = null
        }
        try {
            toneGenerator?.stopTone()
            toneGenerator?.release()
            toneGenerator = null
        } catch (e: Exception) {}
        try {
            incomingRingtone?.stop()
            incomingRingtone = null
        } catch (e: Exception) {}
        abandonAudioFocusForCall()
    }

    override fun onDestroy() {
        resetAudioMode()
        super.onDestroy()
    }
}

