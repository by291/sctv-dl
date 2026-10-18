package dev.sctvdl.flutter

import android.app.Activity
import android.content.Context
import android.media.AudioManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.round

/** Owns window brightness; system media volume intentionally survives playback. */
class PlayerEnvironment(private val activity: Activity, messenger: BinaryMessenger) {
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var enteringBrightness: Float? = null

    init {
        MethodChannel(messenger, "dev.sctvdl.flutter/player_environment")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "brightness", "beginBrightness" -> {
                        if (call.method == "beginBrightness" && enteringBrightness == null) {
                            enteringBrightness = activity.window.attributes.screenBrightness
                        }
                        val current = activity.window.attributes.screenBrightness
                        result.success(
                            if (current >= 0) {
                                current.toDouble()
                            } else {
                                Settings.System.getInt(
                                    activity.contentResolver,
                                    Settings.System.SCREEN_BRIGHTNESS,
                                    128
                                ) /
                                    255.0
                            }
                        )
                    }
                    "setBrightness" -> {
                        val value = (call.arguments as? Number)?.toFloat()
                        if (value == null || !value.isFinite()) {
                            result.error("invalid_brightness", "Expected a finite brightness", null)
                        } else {
                            if (enteringBrightness == null) {
                                enteringBrightness = activity.window.attributes.screenBrightness
                            }
                            activity.window.attributes =
                                activity.window.attributes.apply {
                                    screenBrightness = value.coerceIn(0f, 1f)
                                }
                            result.success(null)
                        }
                    }
                    "restoreBrightness" -> {
                        restore()
                        result.success(null)
                    }
                    "volume" ->
                        result.success(
                            audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() /
                                audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        )
                    "setVolume" -> {
                        val value = (call.arguments as? Number)?.toDouble()
                        if (value == null || !value.isFinite()) {
                            result.error("invalid_volume", "Expected a finite volume", null)
                        } else {
                            val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val level = round(value.coerceIn(0.0, 1.0) * maximum).toInt()
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, level, 0)
                            result.success(null)
                        }
                    }
                    "needsGestureHint" -> {
                        val preferences = activity.getSharedPreferences("player_gestures", Context.MODE_PRIVATE)
                        val show = !preferences.getBoolean("hint_seen", false)
                        result.success(show)
                    }
                    "acknowledgeGestureHint" -> {
                        activity
                            .getSharedPreferences(
                                "player_gestures",
                                Context.MODE_PRIVATE
                            ).edit()
                            .putBoolean("hint_seen", true)
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    fun restore() {
        enteringBrightness?.let { brightness ->
            activity.window.attributes = activity.window.attributes.apply { screenBrightness = brightness }
        }
        enteringBrightness = null
    }
}
