package com.example.gebtalk_flutter

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "gebtalk/audio_control"
    private var audioManager: AudioManager? = null
    private var toneGenerator: ToneGenerator? = null
    private var incomingRingtone: Ringtone? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
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

    private fun applySpeakerphone(isSpeaker: Boolean) {
        val am = audioManager ?: return
        try {
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = am.availableCommunicationDevices
                val targetType = if (isSpeaker) AudioDeviceInfo.TYPE_BUILTIN_SPEAKER else AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                val targetDevice = devices.firstOrNull { it.type == targetType }
                    ?: devices.firstOrNull { 
                        if (isSpeaker) {
                            it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER 
                        } else {
                            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET || 
                            it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || 
                            it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                        }
                    }

                if (targetDevice != null) {
                    am.setCommunicationDevice(targetDevice)
                }
            }
            am.isSpeakerphoneOn = isSpeaker
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
            am.isSpeakerphoneOn = false
            am.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun playOutgoingDialTone() {
        stopAllTones()
        try {
            val am = audioManager
            am?.mode = AudioManager.MODE_IN_COMMUNICATION
            toneGenerator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80)
            toneGenerator?.startTone(ToneGenerator.TONE_SUP_RINGTONE)
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
                toneGenerator = ToneGenerator(AudioManager.STREAM_RING, 100)
                toneGenerator?.startTone(ToneGenerator.TONE_CDMA_HIGH_L, -1)
            } catch (_) {}
        }
    }

    private fun playCallConnectedChime() {
        stopAllTones()
        try {
            val tg = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 90)
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
            val tg = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 90)
            tg.startTone(ToneGenerator.TONE_SUP_BUSY, 800)
            mainHandler.postDelayed({
                try {
                    tg.release()
                } catch (_) {}
            }, 900)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAllTones() {
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
