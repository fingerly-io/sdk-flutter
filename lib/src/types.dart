/// The shapes the native SDKs report in, as Dart.
///
/// A port of `@badele/core`'s `types.ts`, the same way `Types.swift` is. Where
/// the three differ, the JSON is the thing that has to match and the Dart
/// naming is allowed to be Dart.
///
/// Everything here is immutable and everything parses defensively. The JSON
/// arrives from a native SDK on a device the app does not control, and a
/// missing field must produce a missing value rather than an exception — a
/// fraud SDK that throws during a checkout has done more damage than the fraud
/// it was looking for.
library;

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
        ms: (json['ms'] as num?)?.toInt() ?? 0,
        value: json['value'] as Map<String, dynamic>?,
        reason: json['reason'] as String?,
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
      value: json['value'] as bool? ?? false,
      confidence: Confidence.parse(json['confidence']),
      reasons: (json['reasons'] as List?)?.cast<String>() ?? const <String>[],
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
    Verdict at(String key) =>
        Verdict.fromJson(json[key] as Map<String, dynamic>?);

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
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? 'contradiction',
        detail: json['detail'] as String?,
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
      patchedNatives:
          (json['patched_natives'] as List?)?.cast<String>() ?? const [],
      lies: (json['lies'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(Lie.fromJson)
              .toList() ??
          const [],
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
        schema: (json['schema'] as num?)?.toInt() ?? 0,
        budgetMs: (json['budget_ms'] as num?)?.toInt() ?? 0,
        elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
        sources: ((json['sources'] as Map?) ?? const {}).map(
          (key, value) => MapEntry(
            key as String,
            SignalOutcome.fromJson((value as Map).cast<String, dynamic>()),
          ),
        ),
        integrity: IntegrityReport.fromJson(
          (json['integrity'] as Map?)?.cast<String, dynamic>(),
        ),
      );
}

/// What `identify()` resolves with.
class IdentifyResult {
  const IdentifyResult({
    required this.requestId,
    required this.verdicts,
    required this.report,
  });

  /// Empty when `submit` was false: nothing was sent, so there is nothing to
  /// fetch later, and an invented identifier would be worse than an empty one.
  final String requestId;

  /// The local verdicts, available immediately. Advisory — the server's are
  /// the answer.
  final Verdicts verdicts;

  /// The report that was sent, for debugging and for offline callers.
  final SignalReport report;

  factory IdentifyResult.fromJson(Map<String, dynamic> json) => IdentifyResult(
        requestId: json['requestId'] as String? ?? '',
        verdicts: Verdicts.fromJson(
          (json['verdicts'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        report: SignalReport.fromJson(
          (json['report'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
}

/// A failure the caller can act on.
class BadeleException implements Exception {
  const BadeleException(this.message, {this.status});

  final String message;

  /// The HTTP status where there was one. The two worth branching on are 401
  /// (the key is wrong) and 402 (the organisation is not accepting traffic) —
  /// both are the customer's configuration rather than the user's, and an app
  /// that retries either drains a battery over a typo.
  final int? status;

  @override
  String toString() =>
      status == null ? 'BadeleException: $message' : 'BadeleException($status): $message';
}
