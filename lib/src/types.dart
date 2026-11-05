/// The shapes the native SDKs report in, as Dart.
///
/// A port of `@fingerly/core`'s `types.ts`, the same way `Types.swift` is. Where
/// the three differ, the JSON is the thing that has to match and the Dart
/// naming is allowed to be Dart.
///
/// Everything here is immutable and everything parses defensively. The JSON
/// arrives from a native SDK on a device the app does not control, and a
/// missing field must produce a missing value rather than an exception — a
/// fraud SDK that throws during a checkout has done more damage than the fraud
/// it was looking for.
library;

// Readers that check a member's type instead of casting it. `as String?` on a
// member that arrived as a number throws a `TypeError` out of `identify()`
// after the server has already answered, which is the exception the paragraph
// above promises not to raise. A member of the wrong type reads as missing.

Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic>
    ? value
    : value is Map
        ? value.map((key, item) => MapEntry('$key', item))
        : null;

String? _string(Object? value) => value is String ? value : null;

bool? _bool(Object? value) => value is bool ? value : null;

int? _int(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.map(_map).whereType<Map<String, dynamic>>().toList(growable: false)
    : const <Map<String, dynamic>>[];

/// How a source finished.
///
/// Five values, never a hole. A device that lacks an API, a jailbreak that
/// intercepted the call, and a source that ran out of budget are three
/// different facts, and the middle one is frequently more interesting than the
/// value would have been.
enum SignalStatus {
  ok,
  unsupported,
  blocked,
  timeout,
  error;

  static SignalStatus parse(Object? value) => switch (value) {
        'ok' => SignalStatus.ok,
        'unsupported' => SignalStatus.unsupported,
        'blocked' => SignalStatus.blocked,
        'timeout' => SignalStatus.timeout,
        // An unrecognised status is an SDK newer than this binding. Reported as
        // an error rather than thrown on: a Flutter app should not stop working
        // because the native SDK learned a new word.
        _ => SignalStatus.error,
      };
}

/// Whether the user has agreed to be identified.
///
/// Spelled as the other Fingerly SDKs spell it, and sent across the channel by
/// [name]. [pending] is the default: the SDK identifies nobody until it is
/// told [granted]. [pending] and [denied] mean the same thing
/// to the SDK (run no source, send nothing, throw
/// [FingerlyConsentException]) and are kept apart because a consent tool
/// reports them apart.
enum ConsentState {
  granted,
  pending,
  denied;

  /// The state a native bridge named, or null when it named none of the three.
  static ConsentState? tryParse(Object? value) => switch (value) {
        'granted' => ConsentState.granted,
        'pending' => ConsentState.pending,
        'denied' => ConsentState.denied,
        _ => null,
      };
}

/// How sure a verdict is.
enum Confidence {
  low,
  medium,
  high;

  static Confidence parse(Object? value) => switch (value) {
        'high' => Confidence.high,
        'medium' => Confidence.medium,
        _ => Confidence.low,
      };
}

/// What one source reported.
class SignalOutcome {
  const SignalOutcome({
    required this.status,
    required this.ms,
    this.value,
    this.reason,
  });

  final SignalStatus status;

  /// Wall-clock milliseconds, recorded for every status including the failures.
  /// A jailbreak check that took 2ms to find nothing and one that took 40ms are
  /// telling different stories.
  final int ms;

  /// Present when [status] is [SignalStatus.ok].
  final Map<String, dynamic>? value;

  /// A short stable token such as `sandbox-denied`, never a message.
  final String? reason;

  factory SignalOutcome.fromJson(Map<String, dynamic> json) => SignalOutcome(
        status: SignalStatus.parse(json['status']),
        ms: _int(json['ms']) ?? 0,
        value: _map(json['value']),
        reason: _string(json['reason']),
      );
}

/// One detector's answer.
///
/// [reasons] is the point of this type. A boolean that cannot say why it is
/// true is not reviewable, and every one of these will eventually be argued
/// with by a customer looking at a blocked user.
class Verdict {
  const Verdict({
    required this.value,
    required this.confidence,
    required this.reasons,
  });

  final bool value;
  final Confidence confidence;

  /// Strongest first, so truncating this list keeps the tell that drove it.
  final List<String> reasons;

  /// A verdict with nothing behind it — the native SDK did not report one.
  ///
  /// Not the same as a verdict of false, and a caller that treats it as one is
  /// a caller that reads "we could not look" as "nothing is wrong".
  static const unknown = Verdict(
    value: false,
    confidence: Confidence.low,
    reasons: <String>[],
  );

  factory Verdict.fromJson(Map<String, dynamic>? json) {
    if (json == null) return unknown;

    return Verdict(
      value: _bool(json['value']) ?? false,
      confidence: Confidence.parse(json['confidence']),
      reasons: _strings(json['reasons']),
    );
  }
}

/// The verdicts a native application can reach.
///
/// One class covering both platforms, with the platform-specific members
/// answering [Verdict.unknown] where they do not apply. Two classes and a union
/// would be more honest about the difference and would make every call site
/// branch on the platform to read a field — which is the wrong trade for a
/// cross-platform binding, where the whole point is writing the check once.
///
/// The distinction is not lost: `jailbreak` on Android and `root` on iOS both
/// come back with `value: false` *and* an empty `reasons` list, which is what
/// [Verdict.unknown] means.
class Verdicts {
  const Verdicts({
    required this.instrumentation,
    required this.mitm,
    required this.automation,
    required this.tampering,
    required this.farm,
    required this.jailbreak,
    required this.simulator,
    required this.root,
    required this.emulator,
    required this.appCloner,
  });

  /// Frida, Substrate, Substitute, ElleKit — anything rewriting the process.
  final Verdict instrumentation;

  /// Something intercepting the app's own TLS.
  final Verdict mitm;

  /// A debugger or a UI-test runner driving the process.
  final Verdict automation;

  /// Hooked functions, injected images, a signature that is not the app's.
  final Verdict tampering;

  /// A device that looks mass-provisioned or reset-fresh. The half one device
  /// can see about itself; the conclusive half is the server's.
  final Verdict farm;

  /// iOS. [Verdict.unknown] on Android.
  final Verdict jailbreak;

  /// iOS. [Verdict.unknown] on Android.
  final Verdict simulator;

  /// Android. [Verdict.unknown] on iOS.
  final Verdict root;

  /// Android. [Verdict.unknown] on iOS.
  final Verdict emulator;

  /// Android. [Verdict.unknown] on iOS.
  final Verdict appCloner;

  factory Verdicts.fromJson(Map<String, dynamic> json) {
    Verdict at(String key) => Verdict.fromJson(_map(json[key]));

    return Verdicts(
      instrumentation: at('instrumentation'),
      mitm: at('mitm'),
      automation: at('automation'),
      tampering: at('tampering'),
      farm: at('farm'),
      jailbreak: at('jailbreak'),
      simulator: at('simulator'),
      root: at('root'),
      emulator: at('emulator'),
      appCloner: at('appCloner'),
    );
  }
}

/// A hook, a substituted implementation or a claim that does not add up.
class Lie {
  const Lie({required this.id, required this.kind, this.detail});

  final String id;
  final String kind;
  final String? detail;

  factory Lie.fromJson(Map<String, dynamic> json) => Lie(
        id: _string(json['id']) ?? '',
        kind: _string(json['kind']) ?? 'contradiction',
        detail: _string(json['detail']),
      );
}

/// The tamper layer's findings. Raw; the server decides what they are worth.
class IntegrityReport {
  const IntegrityReport({
    required this.patchedNatives,
    required this.lies,
  });

  /// Functions that are no longer the ones the platform shipped.
  final List<String> patchedNatives;
  final List<Lie> lies;

  factory IntegrityReport.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const IntegrityReport(patchedNatives: [], lies: []);
    }

    return IntegrityReport(
      patchedNatives: _strings(json['patched_natives']),
      lies: _maps(json['lies']).map(Lie.fromJson).toList(growable: false),
    );
  }
}

/// The whole client-side observation, as submitted.
class SignalReport {
  const SignalReport({
    required this.schema,
    required this.budgetMs,
    required this.elapsedMs,
    required this.sources,
    required this.integrity,
  });

  final int schema;
  final int budgetMs;

  /// What collection actually cost.
  final int elapsedMs;
  final Map<String, SignalOutcome> sources;
  final IntegrityReport integrity;

  factory SignalReport.fromJson(Map<String, dynamic> json) => SignalReport(
        schema: _int(json['schema']) ?? 0,
        budgetMs: _int(json['budget_ms']) ?? 0,
        elapsedMs: _int(json['elapsed_ms']) ?? 0,
        sources: {
          for (final entry
              in (_map(json['sources']) ?? const <String, dynamic>{}).entries)
            if (_map(entry.value) case final outcome?)
              entry.key: SignalOutcome.fromJson(outcome),
        },
        integrity: IntegrityReport.fromJson(_map(json['integrity'])),
      );
}

/// One thing the server scored on.
class IdentifyTrigger {
  const IdentifyTrigger({
    required this.signal,
    required this.group,
    required this.weight,
    required this.confidence,
    required this.reason,
  });

  /// The signal that fired, such as `patched-natives`.
  final String signal;

  /// The family it belongs to. Empty when it belongs to none.
  final String group;

  /// What it was worth towards the score.
  final int weight;

  /// How sure the server is of this one signal.
  final String confidence;

  /// A short explanation, when there is one.
  final String reason;

  factory IdentifyTrigger.fromJson(Map<String, dynamic> json) =>
      IdentifyTrigger(
        signal: _string(json['signal']) ?? '',
        group: _string(json['group']) ?? '',
        weight: _int(json['weight']) ?? 0,
        confidence: _string(json['confidence']) ?? '',
        reason: _string(json['reason']) ?? '',
      );
}

/// What `identify()` resolves with.
class IdentifyResult {
  const IdentifyResult({
    required this.requestId,
    required this.visitorId,
    required this.visitorIsNew,
    required this.visitorConfidence,
    required this.identifiable,
    required this.duplicate,
    required this.state,
    required this.reason,
    required this.suspectScore,
    required this.suspectLevel,
    required this.triggers,
    required this.verdicts,
    required this.report,
  });

  /// Empty when `submit` was false: nothing was sent, so an invented
  /// identifier would be worse than an empty one.
  final String requestId;

  /// Who the server decided this is, stable across visits. Empty when nothing
  /// was submitted.
  final String visitorId;

  /// True when the server had never seen this visitor before.
  final bool visitorIsNew;

  /// How sure the server is of [visitorId], 0 to 100.
  final int visitorConfidence;

  /// False when the report carried too little to identify anyone.
  final bool identifiable;

  /// True when this submission was answered before, and this verdict belongs
  /// to the first one.
  final bool duplicate;

  /// The server's disposition of the check.
  final String state;

  /// Why, when [state] needs explaining. Empty when it does not.
  final String reason;

  /// The server's score, or null when it did not score.
  ///
  /// Null and 0 are different answers: 0 is "scored, nothing fired", null is
  /// "nobody scored it". Do not collapse them with `?? 0` — that turns an
  /// unscored check into a clean one.
  final int? suspectScore;

  /// The score as a band — `low`, `medium`, `high`. Null when unscored.
  final String? suspectLevel;

  /// What the server scored on. Empty when it found nothing.
  final List<IdentifyTrigger> triggers;

  /// The local verdicts, available immediately. Advisory — the server's are
  /// the answer.
  final Verdicts verdicts;

  /// The report that was sent, for debugging and for offline callers.
  final SignalReport report;

  factory IdentifyResult.fromJson(Map<String, dynamic> json) => IdentifyResult(
        requestId: _string(json['requestId']) ?? '',
        visitorId: _string(json['visitorId']) ?? '',
        visitorIsNew: _bool(json['visitorIsNew']) ?? false,
        visitorConfidence: _int(json['visitorConfidence']) ?? 0,
        identifiable: _bool(json['identifiable']) ?? false,
        duplicate: _bool(json['duplicate']) ?? false,
        state: _string(json['state']) ?? '',
        reason: _string(json['reason']) ?? '',
        // Read without a fallback, unlike everything above it. The native
        // bridges send an explicit null when nothing scored the submission,
        // and `?? 0` here would turn that into a clean verdict — which is the
        // one answer that lets somebody through.
        suspectScore: _int(json['suspectScore']),
        suspectLevel: _string(json['suspectLevel']),
        triggers: _maps(json['triggers'])
            .map(IdentifyTrigger.fromJson)
            .toList(growable: false),
        verdicts: Verdicts.fromJson(
          _map(json['verdicts']) ?? const <String, dynamic>{},
        ),
        report: SignalReport.fromJson(
          _map(json['report']) ?? const <String, dynamic>{},
        ),
      );
}

/// A failure the caller can act on.
class FingerlyException implements Exception {
  const FingerlyException(this.message, {this.status, this.retryAfter});

  final String message;

  /// The HTTP status where there was one. The two worth branching on are 401
  /// (the key is wrong) and 402 (the organisation is not accepting traffic) —
  /// both are the customer's configuration rather than the user's, and an app
  /// that retries either drains a battery over a typo.
  final int? status;

  /// How long the server asked the app to wait, from its `Retry-After`, when
  /// the native SDK gave up on a 429 or 503 that named one. Null when the
  /// response named no wait, and on platforms whose native bridge does not
  /// pass one on. Wait at least this long before identifying again.
  final Duration? retryAfter;

  @override
  String toString() => status == null
      ? 'FingerlyException: $message'
      : 'FingerlyException($status): $message';
}

/// A call refused because consent is not [ConsentState.granted].
///
/// Nothing was collected and nothing was sent: the native SDK refuses before
/// its first source runs, and a call already in flight when consent is
/// withdrawn refuses before it submits. The same call succeeds once the app
/// calls `setConsent(ConsentState.granted)`, so this is not one to retry.
///
/// A [FingerlyException] as well, so an existing `on FingerlyException`
/// handler keeps catching everything this package throws.
class FingerlyConsentException extends FingerlyException {
  FingerlyConsentException(this.state)
      : super(
          'Fingerly needs consent before it can identify this visitor '
          '(consent is ${state.name})',
        );

  /// The string every Fingerly SDK and bridge uses for this failure.
  static const String consentRequired = 'consent_required';

  /// The state that refused the call: [ConsentState.pending] or
  /// [ConsentState.denied].
  final ConsentState state;

  /// Always `consent_required`, matching the other SDKs.
  String get code => consentRequired;

  @override
  String toString() => 'FingerlyConsentException: $message';
}
