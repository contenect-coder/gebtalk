package com.example.gebtalk_flutter

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "gebtalk/audio_control"
    private val PERMISSION_REQ_CODE = 1001

    private var audioManager: AudioManager? = null
    private var toneGenerator: ToneGenerator? = null
    private var incomingRingtone: Ringtone? = null
    private var dialToneRunnable: Runnable? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager

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
                    result.success(true)
                }
                else -> result.notImplemented()
            }
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
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val playbackAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(playbackAttributes)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener { /* maintain VoIP audio state */ }
                    .build()
                audioFocusRequest = request
                am.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN)
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
            requestAudioFocusForCall()

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

            // Re-apply after a short delay to handle race with flutter_webrtc's
            // internal audio session management that may reset our routing.
            mainHandler.postDelayed({
                try {
                    if (am.mode != AudioManager.MODE_IN_COMMUNICATION) {
                        am.mode = AudioManager.MODE_IN_COMMUNICATION
                    }
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                        @Suppress("DEPRECATION")
                        am.isSpeakerphoneOn = isSpeaker
                    }
                } catch (_: Exception) {}
            }, 150)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun resetAudioMode() {
        val am = audioManager ?: return
        try {
            stopAllTones()
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

            // Cadenced ringback tone: 1.2s tone on, 2.8s tone off
            // This prevents continuous mixer overload and keeps hardware Acoustic Echo Canceller clean
            toneGenerator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80)
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
            mainHandler.post(dialToneRunnable!!)
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
                toneGenerator = ToneGenerator(AudioManager.STREAM_RING, 85)
                toneGenerator?.startTone(ToneGenerator.TONE_CDMA_HIGH_L, -1)
            } catch (_) {}
        }
    }

    private fun playCallConnectedChime() {
        stopAllTones()
        try {
            val tg = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80)
            tg.startTone(ToneGenerator.TONE_PROP_BEEP, 200)
            mainHandler.postDelayed({
                try {
                    tg.release()
                } catch (_) {}
            }, 300)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun playCallEndedTone() {
        stopAllTones()
        try {
            val tg = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80)
            tg.startTone(ToneGenerator.TONE_SUP_BUSY, 700)
            mainHandler.postDelayed({
                try {
                    tg.release()
                } catch (_) {}
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
        } catch (_) {}
        try {
            incomingRingtone?.stop()
            incomingRingtone = null
        } catch (_) {}
    }

    override fun onDestroy() {
        resetAudioMode()
        super.onDestroy()
    }
}

