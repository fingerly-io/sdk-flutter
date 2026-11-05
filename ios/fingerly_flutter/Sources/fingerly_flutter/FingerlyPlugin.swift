/// The Flutter plugin.
///
/// It does three things: hand the configuration to the native SDK, call it, and
/// return the JSON it produced. There is deliberately no logic here at all —
/// every decision about what to collect and how to weigh it lives in `Fingerly`.
///
/// The result crosses as JSON because Flutter's standard method codec has its
/// own nested-map types, while JSON is already the native SDK's wire format.

import Fingerly
import Flutter
import UIKit

public class FingerlyPlugin: NSObject, FlutterPlugin {
    /// Matches `_channelName` in `fingerly.dart`. A mismatch is a call that never
    /// arrives rather than a compile error.
    private static let channelName = "io.fingerly.sdk/flutter"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(FingerlyPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            configure(call, result)
        case "setConsent":
            // Anything missing or unrecognised reaches the bridge as a string
            // it does not know, which it reads as `pending`.
            let arguments = call.arguments as? [String: Any] ?? [:]
            FingerlyBridge.setConsent(arguments["state"] as? String ?? "")
            result(nil)
        case "identify":
            identify(call, result)
        case "collect":
            FingerlyBridge.collect { json, error in
                Self.settle(json, error, result)
            }
        case "sdkVersion":
            result(FingerlyBridge.sdkVersion)
        case "deleteStoredIdentity":
            // A synchronous keychain delete, which is an IPC round trip to
            // securityd and can stall, so it runs off the platform thread
            // (this method is called on it) and answers back on it, as the
            // Android plugin does with its file delete. A refusal arrives as
            // `delete_failed`, as it does from Android.
            DispatchQueue.global(qos: .userInitiated).async {
                let error = FingerlyBridge.deleteStoredIdentity()
                DispatchQueue.main.async {
                    if let error {
                        result(FlutterError(
                            code: error.userInfo["code"] as? String ?? "\(error.code)",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    } else {
                        result(nil)
                    }
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func configure(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any] else {
            result(Self.argumentError("configure needs apiKey, endpoint and platform"))
            return
        }

        FingerlyBridge.configure(
            apiKey: arguments["apiKey"] as? String ?? "",
            endpoint: arguments["endpoint"] as? String ?? "",
            platform: arguments["platform"] as? String ?? "flutter-ios",
            // `fingerly.dart` always sends it, `pending` unless the app asked
            // for another state; the fallback is that same Dart default.
            consent: arguments["consent"] as? String ?? "pending"
        )
        result(nil)
    }

    private func identify(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]

        FingerlyBridge.identify(
            tag: arguments["tag"] as? String,
            // An argument lost in transit must not silently turn a submission
            // into a collection the caller waits for a request id from.
            submit: arguments["submit"] as? Bool ?? true
        ) { json, error in
            Self.settle(json, error, result)
        }
    }

    /// Flutter results must be delivered on the platform thread; native
    /// collection completes on whichever cooperative thread finished the work.
    private static func settle(
        _ json: String?,
        _ error: NSError?,
        _ result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async {
            if let error {
                // A refusal for want of consent carries its string code
                // (`consent_required`) and the refusing state in `userInfo`,
                // which Dart turns into `FingerlyConsentException`. A
                // transport failure whose response named a wait carries it as
                // `retryAfterMs`, which Dart turns into
                // `FingerlyException.retryAfter`.
                var details: [String: Any] = [:]
                if let state = error.userInfo["state"] as? String {
                    details["state"] = state
                }
                if let wait = error.userInfo["retryAfterMs"] as? NSNumber {
                    details["retryAfterMs"] = wait
                }
                result(FlutterError(
                    // Native transport errors use the HTTP status as their
                    // code, which Dart preserves on `FingerlyException`.
                    code: error.userInfo["code"] as? String ?? "\(error.code)",
                    message: error.localizedDescription,
                    details: details.isEmpty ? nil : details
                ))
                return
            }

            guard let json else {
                result(FlutterError(
                    code: "-1",
                    message: "The SDK produced no report",
                    details: nil
                ))
                return
            }

            result(json)
        }
    }

    private static func argumentError(_ message: String) -> FlutterError {
        FlutterError(code: "-1", message: message, details: nil)
    }
}
