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
        case "identify":
            identify(call, result)
        case "collect":
            FingerlyBridge.collect { json, error in
                Self.settle(json, error, result)
            }
        case "sdkVersion":
            result(FingerlyBridge.sdkVersion)
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
            platform: arguments["platform"] as? String ?? "flutter-ios"
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
                result(FlutterError(
                    // Native transport errors use the HTTP status as their
                    // code, which Dart preserves on `FingerlyException`.
                    code: "\(error.code)",
                    message: error.localizedDescription,
                    details: nil
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
