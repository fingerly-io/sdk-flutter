/// Fingerly for Flutter.
///
/// # This package collects nothing
///
/// That is the design, not a limitation. Every signal worth having on a phone
/// is unreachable from Dart: `lstat` on `/var/jb`, the dyld image list, the
/// thread names Frida leaves behind, the `P_TRACED` flag, the DeviceCheck token
/// Apple signs, the TLS chain the app was actually served. A method channel can
/// reach none of them.
///
/// So a plugin that collected what it *could* reach from Dart would report a
/// jailbroken, instrumented device as clean — which is worse than reporting
/// nothing, because a customer would believe it. This package calls the native
/// SDK and hands back what it produced.
///
/// The consequence worth stating: the detection logic lives in one place per
/// platform, in Swift and in Kotlin, and improving it improves Flutter, React
/// Native and native apps at the same time rather than three times over.
///
/// ```dart
/// import 'package:fingerly_flutter/fingerly.dart';
///
/// final fingerly = await Fingerly.load(apiKey: 'pk_live_…');
/// final result = await fingerly.identify(tag: 'checkout');
///
/// if (result.verdicts.jailbreak.value &&
///     result.verdicts.jailbreak.confidence == Confidence.high) {
///   // step up to a challenge
/// }
/// ```
library fingerly;

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

import 'src/types.dart';

export 'src/types.dart';

/// The channel name. Matches `FingerlyPlugin.swift` and the Kotlin equivalent;
/// a mismatch is a call that never arrives rather than a compile error, which
/// is why it is a constant in one place rather than a literal in three.
const _channelName = 'io.fingerly.sdk/flutter';

const _channel = MethodChannel(_channelName);

/// Which platform this SDK reports as.
///
/// The host is named as well as the toolkit — `flutter-ios`, not `flutter` —
/// because the server maps an SDK platform onto one of three scoring profiles
/// by looking for `ios` or `android` in the string. A Flutter app that does not
/// say which one it is running on is scored against browser weights, where
/// `jailbreak` is not a signal at all and everything the native SDK went to the
/// trouble of collecting is worth nothing.
///
/// See `models.RiskPlatformFor` on the server.
/// `defaultTargetPlatform` rather than `dart:io`'s `Platform`, because importing
/// `dart:io` makes this library fail to compile for web — and a package that
/// cannot be *imported* on a platform it does not support is worse than one
/// that simply does nothing there.
String _platformName() => defaultTargetPlatform == TargetPlatform.android
    ? 'flutter-android'
    : 'flutter-ios';

/// The message shown when the plugin is not registered.
///
/// Worth being specific about, because this is the failure every Flutter
/// integration hits first and `MissingPluginException` tells nobody what to do
/// about it.
const _missingPlugin =
    'The fingerly plugin is not registered on this platform. Run `flutter clean` '
    'and rebuild — this package cannot collect anything without the native SDK, '
    'and collecting a subset from Dart would report a compromised device as clean.';

/// A configured client.
class Fingerly {
  const Fingerly._();

  /// Configure the SDK and return a client.
  ///
  /// The key is a **publishable** SDK key from the dashboard, and it is safe in
  /// a shipped binary — it is scoped to the app identifiers you list. A secret
  /// key is refused when it arrives from a client, so pasting one in does not
  /// work by design.
  static Future<Fingerly> load({
    required String apiKey,
    String endpoint = '',
  }) async {
    await _invokeVoid('configure', {
      'apiKey': apiKey,
      // Empty means "use the native default". Not null: the native signature
      // takes a non-null string, and a null across the channel fails the
      // argument check rather than falling back.
      'endpoint': endpoint,
      'platform': _platformName(),
    });

    return const Fingerly._();
  }

  /// Collect, score on the device, and submit.
  ///
  /// Returns the server's verdict, not a receipt for one. There is no second
  /// call to make: the address lookup and the scoring happen on the request,
  /// so [IdentifyResult.suspectScore] and [IdentifyResult.visitorId] are
  /// populated by the time this resolves.
  ///
  /// Pass `submit: false` to collect and score without sending anything. The
  /// server's fields come back empty then, and [IdentifyResult.suspectScore]
  /// stays null rather than 0 — nobody scored it, which is not the same as
  /// scoring it and finding nothing.
  Future<IdentifyResult> identify({String? tag, bool submit = true}) async {
    final raw = await _invoke<String>('identify', {
      'tag': tag,
      'submit': submit,
    });

    return IdentifyResult.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  /// Run the sources and assemble the report, without submitting.
  ///
  /// Useful on its own: a debug screen, or seeing exactly what would be sent
  /// before agreeing to send it. Needs no key.
  Future<SignalReport> collect() async {
    final raw = await _invoke<String>('collect');

    return SignalReport.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  /// The native SDK's version, which is the one that did the collecting.
  static Future<String> nativeVersion() => _invoke<String>('sdkVersion');
}

/// Call the native side and insist on an answer.
///
/// Separate from [_invokeVoid] rather than one generic function with a null
/// check, because "returned null" is a failure for `identify` and the expected
/// outcome for `configure` — and `T == void` is not something Dart's type
/// system lets a single function ask about.
Future<T> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
  final result =
      await _guard(() => _channel.invokeMethod<T>(method, arguments));

  if (result == null) {
    throw const FingerlyException('The SDK produced no report');
  }
  return result;
}

/// Call the native side for its effect.
Future<void> _invokeVoid(String method, [Map<String, dynamic>? arguments]) =>
    _guard(() => _channel.invokeMethod<void>(method, arguments));

/// Turn the channel's failures into ones a caller can act on.
Future<R?> _guard<R>(Future<R?> Function() body) async {
  try {
    return await body();
  } on MissingPluginException {
    throw const FingerlyException(_missingPlugin);
  } on PlatformException catch (error) {
    // The native bridges set the error code to the HTTP status where there was
    // one, so a caller can tell a wrong key from an exhausted account without
    // parsing a message.
    throw FingerlyException(
      error.message ?? 'The submission could not be sent',
      status: int.tryParse(error.code),
    );
  }
}
