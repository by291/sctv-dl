package dev.sctvdl.flutter

import android.app.Activity
import android.content.Context
import android.media.AudioManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.round

private const val DEFAULT_SYSTEM_BRIGHTNESS = 128
private const val MAX_SYSTEM_BRIGHTNESS = 255.0
private const val GESTURE_PREFERENCES = "player_gestures"
private const val GESTURE_HINT_SEEN = "hint_seen"

/** Owns window brightness; system media volume intentionally survives playback. */
internal class PlayerEnvironment(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : AutoCloseable {
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val preferences =
        activity.getSharedPreferences(GESTURE_PREFERENCES, Context.MODE_PRIVATE)
    private val channel = MethodChannel(messenger, "dev.sctvdl.flutter/player_environment")

    private var enteringBrightness: Float? = null

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "brightness" -> result.success(readBrightness())
            "beginBrightness" -> {
                captureBrightness()
                result.success(readBrightness())
            }
            "setBrightness" -> setBrightness(call, result)
            "restoreBrightness" -> {
                restoreBrightness()
                result.success(null)
            }
            "volume" -> result.success(readVolume())
            "setVolume" -> setVolume(call, result)
            "needsGestureHint" -> {
                result.success(!preferences.getBoolean(GESTURE_HINT_SEEN, false))
            }
            "acknowledgeGestureHint" -> {
                preferences.edit().putBoolean(GESTURE_HINT_SEEN, true).apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun readBrightness(): Double {
        val current = activity.window.attributes.screenBrightness
        if (current >= 0) {
            return current.toDouble()
        }

        // An unset window follows the system's byte-scale brightness setting.
        val systemBrightness =
            Settings.System.getInt(
                activity.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                DEFAULT_SYSTEM_BRIGHTNESS,
            )
        return systemBrightness / MAX_SYSTEM_BRIGHTNESS
    }

    private fun captureBrightness() {
        if (enteringBrightness == null) {
            // Retain the raw window value so restoration can resume following the system.
            enteringBrightness = activity.window.attributes.screenBrightness
        }
    }

    private fun setBrightness(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val value = (call.arguments as? Number)?.toFloat()
        if (value == null || !value.isFinite()) {
            result.error("invalid_brightness", "Expected a finite brightness", null)
            return
        }

        captureBrightness()
        applyBrightness(value.coerceIn(0f, 1f))
        result.success(null)
    }

    private fun applyBrightness(brightness: Float) {
        activity.window.attributes =
            activity.window.attributes.apply {
                screenBrightness = brightness
            }
    }

    private fun restoreBrightness() {
        val original = enteringBrightness ?: return
        applyBrightness(original)
        enteringBrightness = null
    }

    private fun readVolume(): Double {
        val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return current.toDouble() / maximum
    }

    private fun setVolume(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val value = (call.arguments as? Number)?.toDouble()
        if (value == null || !value.isFinite()) {
            result.error("invalid_volume", "Expected a finite volume", null)
            return
        }

        val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val level = round(value.coerceIn(0.0, 1.0) * maximum).toInt()
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, level, 0)
        result.success(null)
    }

    /** Unregisters this screen's handler and restores any active brightness override. */
    override fun close() {
        try {
            restoreBrightness()
        } finally {
            channel.setMethodCallHandler(null)
        }
    }
}
