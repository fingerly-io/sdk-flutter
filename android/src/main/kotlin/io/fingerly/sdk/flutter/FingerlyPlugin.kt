package io.fingerly.sdk.flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.fingerly.sdk.bridge.FingerlyBridge
import io.fingerly.sdk.bridge.BridgeCallback
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * The Flutter plugin.
 *
 * It does three things: hand the configuration to the native SDK, call it, and
 * return the JSON it produced. There is deliberately no logic here at all —
 * every decision about what to collect and how to weigh it lives in the SDK,
 * beside the React Native module's identical arrangement. A plugin that made
 * judgements would be a fourth place to keep a rule in step.
 *
 * # Why the result crosses as a string
 *
 * Flutter's standard method codec has its own idea of what a nested map is, and
 * the report is a deep one — twenty-two sources, each with a value of a
 * different shape. Marshalling it into the codec's types by hand would mean
 * another mapping to keep in step with the wire format, and the wire format is
 * JSON already. The Dart side parses it into the same classes a native app gets
 * as Kotlin data classes.
 */
class FingerlyPlugin : FlutterPlugin, MethodCallHandler {

    private var channel: MethodChannel? = null
    private var context: Context? = null

    /**
     * Every result is delivered here.
     *
     * Flutter's `Result` must be called on the platform thread, and the SDK's
     * callback runs on whichever coroutine thread finished the work. Calling it
     * from there is the kind of bug that works on a fast device and crashes on
     * a slow one — the iOS plugin hops to the main queue for exactly the same
     * reason.
     */
    private val platformThread = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler(this@FingerlyPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> configure(call, result)
            "setConsent" -> {
                // Null or unrecognised is read as `pending` by the bridge.
                FingerlyBridge.setConsent(call.argument<String>("state"))
                result.success(null)
            }
            "identify" -> identify(call, result)
            "collect" -> FingerlyBridge.collect(settle(result))
            "deleteStoredIdentity" -> deleteStoredIdentity(result)
            "sdkVersion" -> result.success(FingerlyBridge.sdkVersion())
            // The channel is ours and every method on it is declared in
            // `fingerly.dart`, so this is a Dart side newer than the native one —
            // which `notImplemented` is exactly the answer for.
            else -> result.notImplemented()
        }
    }

    private fun configure(call: MethodCall, result: Result) {
        val context = this.context
        if (context == null) {
            result.error("-1", "Fingerly was configured before the plugin attached to an engine", null)
            return
        }

        FingerlyBridge.configure(
            context = context,
            apiKey = call.argument<String>("apiKey") ?: "",
            endpoint = call.argument<String>("endpoint") ?: "",
            platform = call.argument<String>("platform") ?: "flutter-android",
            // `fingerly.dart` always sends it, `pending` unless the app asked
            // for another state; the fallback is that same Dart default.
            consent = call.argument<String>("consent") ?: "pending",
        )
        result.success(null)
    }

    /**
     * Deletes the install record, for a user's erasure or account deletion.
     *
     * Needs neither `configure` nor consent, only a context. Done on a thread of
     * its own because this method is called on the platform thread and the
     * delete is disk I/O, which StrictMode rightly objects to there.
     */
    private fun deleteStoredIdentity(result: Result) {
        val context = this.context
        if (context == null) {
            result.error("-1", "Fingerly was called before the plugin attached to an engine", null)
            return
        }

        Thread {
            val deleted = try {
                FingerlyBridge.deleteStoredIdentity(context)
            } catch (error: Throwable) {
                false
            }
            platformThread.post {
                // `delete_failed`, the code the iOS plugin uses for the same
                // failure, so Dart handles both alike.
                if (deleted) {
                    result.success(null)
                } else {
                    result.error("delete_failed", "Fingerly could not delete its stored install record", null)
                }
            }
        }.start()
    }

    private fun identify(call: MethodCall, result: Result) {
        FingerlyBridge.identify(
            tag = call.argument<String>("tag"),
            // Defaulting to true: the Dart signature defaults to submitting, and
            // an argument lost in transit must not silently turn a submission
            // into a collection the caller then waits for a request id from.
            submit = call.argument<Boolean>("submit") ?: true,
            callback = settle(result),
        )
    }

    private fun settle(result: Result): BridgeCallback = object : BridgeCallback {
        override fun onSuccess(json: String) {
            platformThread.post { result.success(json) }
        }

        override fun onError(code: String, message: String) {
            // The HTTP status where there was one, as a string, so the Dart
            // side can parse it back into `FingerlyException.status` and a caller
            // can tell 401 from 402 without reading a message. A refusal for
            // want of consent arrives as `consent_required`, which Dart turns
            // into `FingerlyConsentException`.
            platformThread.post { result.error(code, message, null) }
        }
    }

    private companion object {
        /**
         * Matches `_channelName` in `fingerly.dart` and the iOS plugin's own
         * constant. A mismatch is not a compile error in any of the three
         * languages; it is a call that never arrives.
         */
        const val CHANNEL_NAME = "io.fingerly.sdk/flutter"
    }
}
