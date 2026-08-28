/// The Flutter plugin.
///
/// It does three things: hand the configuration to the native SDK, call it, and
/// return the JSON it produced. There is deliberately no logic here at all —
/// every decision about what to collect and how to weigh it lives in `Badele`,
/// beside the React Native module's identical arrangement. A plugin that made
/// judgements would be a fourth place to keep a rule in step.
///
/// # Why the result crosses as a string
///
/// Flutter's standard method codec has its own idea of what a nested map is,
/// and the report is a deep one — twenty sources, each with a value of a
/// different shape. Marshalling it into the codec's types by hand would mean
/// another mapping to keep in step with the wire format, and the wire format is
/// JSON already. The Dart side parses it into the same classes a native app
/// gets as Swift structs.

import Badele
import Flutter
import UIKit

public class BadelePlugin: NSObject, FlutterPlugin {
    /// Matches `_channelName` in `badele.dart`. A mismatch is not a compile
    /// error in either language; it is a call that never arrives.
    private static let channelName = "io.badele.sdk/flutter"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(BadelePlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            configure(call, result)
        case "identify":
            identify(call, result)
        case "collect":
            BadeleBridge.collect { json, error in
                Self.settle(json, error, result)
            }
        case "sdkVersion":
            result(BadeleBridge.sdkVersion)
        default:
            // The channel is ours and every method on it is declared in
            // `badele.dart`, so this is a Dart side newer than the native one —
            // which `FlutterMethodNotImplemented` is exactly the answer for.
            result(FlutterMethodNotImplemented)
        }
    }

    private func configure(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any] else {
            result(Self.argumentError("configure needs apiKey, endpoint and platform"))
            return
        }

        BadeleBridge.configure(
            apiKey: arguments["apiKey"] as? String ?? "",
            endpoint: arguments["endpoint"] as? String ?? "",
            platform: arguments["platform"] as? String ?? "flutter-ios"
        )
        result(nil)
    }

    private func identify(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]

        BadeleBridge.identify(
            tag: arguments["tag"] as? String,
            // Defaulting to true: the Dart signature defaults to submitting, and
            // an argument lost in transit must not silently turn a submission
            // into a collection the caller then waits for a request id from.
            submit: arguments["submit"] as? Bool ?? true
        ) { json, error in
            Self.settle(json, error, result)
        }
    }

    /// Deliver the answer on the platform thread.
    ///
    /// `FlutterResult` must be called on the platform thread, and the SDK's
    /// completion runs on whatever cooperative thread finished the work.
    /// Calling it from there is the kind of bug that works on a fast device and
    /// crashes on a slow one.
    private static func settle(
        _ json: String?,
        _ error: NSError?,
        _ result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async {
            if let error {
                result(FlutterError(
                    // The HTTP status where there was one, as a string, so the
                    // Dart side can parse it back into `BadeleException.status`
                    // and a caller can tell 401 from 402 without reading a
                    // message.
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
