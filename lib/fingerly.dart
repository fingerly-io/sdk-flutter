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
/// final fingerly = await Fingerly.load(apiKey: 'fly_pk_production_…');
/// // From the consent tool, once the user has agreed (or another lawful basis
/// // applies).
/// await fingerly.setConsent(ConsentState.granted);
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

/// The consent this package last handed to the native SDK.
///
/// Library state rather than a field, because the native bridge keeps one
/// client per process: every [Fingerly] talks to it, and a second
/// [Fingerly.load] changes the state for all of them.
ConsentState _consent = ConsentState.pending;

/// A configured client.
class Fingerly {
  const Fingerly._();

  /// Configure the SDK and return a client.
  ///
  /// The key is a **publishable** SDK key from the dashboard, and it is safe in
  /// a shipped binary — it is scoped to the app identifiers you list. A secret
  /// key is refused when it arrives from a client, so pasting one in does not
  /// work by design.
  ///
  /// [consent] is the state to start from, [ConsentState.pending] by default:
  /// call [setConsent] once the app's consent tool has an answer, and until
  /// it is [ConsentState.granted], [identify] and [collect] throw
  /// [FingerlyConsentException]. Pass [ConsentState.granted] here only once
  /// the user has agreed, or where another lawful basis applies. Loading
  /// collects and sends nothing, whatever the consent, and the state passed
  /// here replaces whatever the native SDK held before.
  static Future<Fingerly> load({
    required String apiKey,
    String endpoint = '',
    ConsentState consent = ConsentState.pending,
  }) async {
    await _invokeVoid('configure', {
      'apiKey': apiKey,
      // Empty means "use the native default". Not null: the native signature
      // takes a non-null string, and a null across the channel fails the
      // argument check rather than falling back.
      'endpoint': endpoint,
      'platform': _platformName(),
      'consent': consent.name,
    });

    _consent = consent;
    return const Fingerly._();
  }

  /// The consent last given to the native SDK, by [load] or [setConsent].
  ConsentState get consent => _consent;

  /// Record the user's answer, as the consent tool reports it.
  ///
  /// Safe to repeat. [consent] changes straight away and the native SDK is
  /// told in the order calls were made, so an [identify] started after this
  /// call sees the new state whether or not the returned future was awaited.
  /// It also applies to a call already in flight: withdrawing consent stops a
  /// running [identify] before it starts another source or submits, and that
  /// call throws [FingerlyConsentException].
  Future<void> setConsent(ConsentState state) {
    _consent = state;
    return _invokeVoid('setConsent', {'state': state.name});
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
  ///
  /// Throws [FingerlyConsentException] while consent is not granted.
  Future<IdentifyResult> identify({String? tag, bool submit = true}) async {
    final raw = await _invoke<String>('identify', {
      'tag': tag,
      'submit': submit,
    });

    return IdentifyResult.fromJson(_decode(raw));
  }

  /// Run the sources and assemble the report, without submitting.
  ///
  /// Useful on its own: a debug screen, or seeing exactly what would be sent
  /// before agreeing to send it. Needs no key, but does need consent: throws
  /// [FingerlyConsentException] without it.
  Future<SignalReport> collect() async {
    final raw = await _invoke<String>('collect');

    return SignalReport.fromJson(_decode(raw));
  }

  /// The native SDK's version, which is the one that did the collecting.
  static Future<String> nativeVersion() => _invoke<String>('sdkVersion');

  /// Delete the install record the native SDK keeps on the device.
  ///
  /// Call it when a user asks for their data to be erased or deletes their
  /// account, so the device stops presenting the install ID the server knows
  /// it by. Needs no [load] and no consent, and sends nothing. Completes once
  /// no record remains, including when there was none. The next
  /// identification made with consent starts a new record; to stop
  /// identifying as well, set consent to [ConsentState.denied] first, because
  /// a call already running may write a fresh record.
  ///
  /// Throws a [FingerlyException] when the delete fails, and when the native
  /// SDK in the app predates this call.
  static Future<void> deleteStoredIdentity() async {
    try {
      await _invokeVoid('deleteStoredIdentity');
    } on FingerlyException catch (error) {
      // The channel cannot tell a plugin that is not registered from one
      // whose native SDK predates this method, and the second is the likelier
      // cause here, so the message names both.
      if (error.message == _missingPlugin) {
        throw const FingerlyException(
          'deleteStoredIdentity is not available in the native Fingerly SDK '
          'on this platform, or the plugin is not registered',
        );
      }
      rethrow;
    }
  }
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

/// The native JSON as an object, or a [FingerlyException].
///
/// A `FormatException` or a `TypeError` out of `identify()` would escape an
/// `on FingerlyException` handler, which is the one every caller writes.
Map<String, dynamic> _decode(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const FingerlyException('The SDK produced an unreadable report');
  }
  if (decoded is Map<String, dynamic>) return decoded;
  throw const FingerlyException('The SDK produced an unreadable report');
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
    if (error.code == FingerlyConsentException.consentRequired) {
      throw FingerlyConsentException(_refusedConsent(error));
    }

    // The native bridges set the error code to the HTTP status where there was
    // one, so a caller can tell a wrong key from an exhausted account without
    // parsing a message.
    throw FingerlyException(
      error.message ?? 'The submission could not be sent',
      status: int.tryParse(error.code),
    );
  }
}

/// The state behind a native `consent_required` refusal.
///
/// The iOS plugin sends it in `details`. The Android plugin sends a code and a
/// message only, and the message ends with the state in a fixed form. Anything
/// unreadable is [ConsentState.pending], which is what the native SDKs read an
/// unknown state as.
ConsentState _refusedConsent(PlatformException error) {
  final details = error.details;
  final fromDetails =
      details is Map ? ConsentState.tryParse(details['state']) : null;
  if (fromDetails != null) return fromDetails;

  final match = RegExp(r'\(consent is (\w+)\)').firstMatch(error.message ?? '');
  return ConsentState.tryParse(match?.group(1)) ?? ConsentState.pending;
}
