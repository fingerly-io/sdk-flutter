/// The shapes the native SDKs report in, as Dart.
///
/// Matches the unified `v: 3` wire contract (`sdks/contract/v3-envelope.md`) and
/// native `schema: 2` telemetry contract (`sdks/contract/native-report.md`).
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

List<IdentifyTrigger>? _triggers(Object? value) {
  if (value is! List) return null;
  final out = <IdentifyTrigger>[];
  for (final item in value) {
    final map = _map(item);
    if (map == null) continue;
    final parsed = IdentifyTrigger.tryFromJson(map);
    if (parsed != null) out.add(parsed);
  }
  return List<IdentifyTrigger>.unmodifiable(out);
}

/// Configuration passed to `Fingerly.configure` / `Fingerly.load`.
class FingerlyConfig {
  const FingerlyConfig({
    required this.apiKey,
    this.endpoint = '',
    this.consent = ConsentState.pending,
    this.playIntegrityCloudProjectNumber,
  });

  /// Publishable SDK key from the Fingerly dashboard (`fly_pk_...`).
  final String apiKey;

  /// Optional API origin override; empty uses `https://api.fingerly.io`.
  final String endpoint;

  /// Initial collection consent state. Defaults to [ConsentState.pending].
  final ConsentState consent;

  /// Android only: Google Cloud project number linked to the app in Play
  /// Console for Standard Play Integrity token requests (`> 0` when set).
  /// Safely ignored on iOS and when `io.fingerly:fingerly-play-integrity` is
  /// not linked into the Android app.
  final int? playIntegrityCloudProjectNumber;
}

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
/// told [granted]. [pending] and [denied] mean the same thing to the SDK (run
/// no source, send nothing, throw [FingerlyConsentException]) and are kept
/// apart because a consent tool reports them apart.
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

/// Canonical v3 risk signal catalogue (`sdks/contract/openapi.json` and
/// `sdks/contract/v3-manifest.json`).
enum RiskSignal {
  // Cross-platform signals
  highActivity('high_activity'),
  tampering('tampering'),
  deviceFarm('device_farm'),
  developerTools('developer_tools'),
  geoMismatch('geo_mismatch'),
  deviceInconsistent('device_inconsistent'),

  // Network & IP intelligence signals
  tor('tor'),
  proxy('proxy'),
  residentialProxy('residential_proxy'),
  residentialProxyLowConfidence('residential_proxy_low_confidence'),
  residentialProxyMediumConfidence('residential_proxy_medium_confidence'),
  residentialProxyHighConfidence('residential_proxy_high_confidence'),
  vpnPublic('vpn_public'),
  vpnTimezone('vpn_timezone'),
  vpnRelay('vpn_relay'),
  vpnMobile('vpn_mobile'),
  vpnOsMismatch('vpn_os_mismatch'),
  vpnLowConfidence('vpn_low_confidence'),
  vpnMediumConfidence('vpn_medium_confidence'),
  vpnHighConfidence('vpn_high_confidence'),
  ipBlocklistEmailSpam('ip_blocklist_email_spam'),
  ipBlocklistAttackSource('ip_blocklist_attack_source'),
  ipAbuser('ip_abuser'),
  datacenterIp('datacenter_ip'),
  bogonIp('bogon_ip'),
  anycastIp('anycast_ip'),

  // Browser-only signals
  incognito('incognito'),
  badBot('bad_bot'),
  automation('automation'),
  antidetectBrowser('antidetect_browser'),
  virtualMachine('virtual_machine'),
  fingerprintSuppressed('fingerprint_suppressed'),
  privacySettings('privacy_settings'),
  embeddedWebView('embedded_web_view'),
  remoteControl('remote_control'),

  // Native-only signals
  emulator('emulator'),
  rootApps('root_apps'),
  appCloner('app_cloner'),
  jailbreak('jailbreak'),
  simulator('simulator'),
  frida('frida'),
  mitmAttack('mitm_attack'),
  activeCall('active_call'),
  attestationMissing('attestation_missing'),
  appAttestKeyChurn('app_attest_key_churn'),
  playDeviceIntegrityFailed('play_device_integrity_failed'),
  playAppUnrecognized('play_app_unrecognized'),
  attestationFailed('attestation_failed'),
  reportIncomplete('report_incomplete'),
  customRootCa('custom_root_ca'),
  secondaryUserProfile('secondary_user_profile');

  const RiskSignal(this.wire);

  /// Exact wire token used by the server and OpenAPI schema.
  final String wire;

  static final Map<String, RiskSignal> _byWire = {
    for (final signal in RiskSignal.values) signal.wire: signal,
  };

  /// Looks up a known [RiskSignal] by its wire token, or returns null for an
  /// unrecognised token from a newer server.
  static RiskSignal? tryParse(Object? value) =>
      value is String ? _byWire[value] : null;
}

/// One active risk trigger (`IdentifyTriggerOut` in OpenAPI).
class IdentifyTrigger {
  const IdentifyTrigger({
    required this.signal,
    this.group,
    this.weight,
    this.confidence,
  });

  /// Canonical wire identifier, such as `attestation_failed` or `tampering`.
  final String signal;

  /// Typed [RiskSignal] when [signal] belongs to the known v3 catalogue, or
  /// null when emitted by a newer server.
  RiskSignal? get riskSignal => RiskSignal.tryParse(signal);

  final String? group;
  final int? weight;
  final String? confidence;

  static IdentifyTrigger? tryFromJson(Map<String, dynamic> json) {
    final signal = _string(json['signal']);
    if (signal == null || signal.isEmpty) return null;
    return IdentifyTrigger(
      signal: signal,
      group: _string(json['group']),
      weight: _int(json['weight']),
      confidence: _string(json['confidence']),
    );
  }
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

/// Where one watched iOS C function resolved, and the prologue/branch behind it.
class NativeSymbol {
  const NativeSymbol({
    required this.symbol,
    required this.image,
    required this.tree,
    this.prologue,
    this.branchImage,
    this.branchTree,
    this.branchResolved,
  });

  final String symbol;
  final String image;
  final String tree;
  final String? prologue;
  final String? branchImage;
  final String? branchTree;
  final bool? branchResolved;

  factory NativeSymbol.fromJson(Map<String, dynamic> json) => NativeSymbol(
        symbol: _string(json['symbol']) ?? '',
        image: _string(json['image']) ?? '',
        tree: _string(json['tree']) ?? '',
        prologue: _string(json['prologue']),
        branchImage: _string(json['branch_image']),
        branchTree: _string(json['branch_tree']),
        branchResolved: _bool(json['branch_resolved']),
      );
}

/// Where one watched iOS Objective-C method's implementation lives.
class ObjcMethod {
  const ObjcMethod({
    required this.method,
    this.image,
    required this.tree,
    this.isaSwizzled,
    this.msgForward,
  });

  final String method;
  final String? image;
  final String tree;
  final bool? isaSwizzled;
  final bool? msgForward;

  factory ObjcMethod.fromJson(Map<String, dynamic> json) => ObjcMethod(
        method: _string(json['method']) ?? '',
        image: _string(json['image']),
        tree: _string(json['tree']) ?? '',
        isaSwizzled: _bool(json['isa_swizzled']),
        msgForward: _bool(json['msg_forward']),
      );
}

/// Where one Mach-O GOT / lazy-symbol pointer slot in the iOS SDK image points.
class GotSlot {
  const GotSlot({
    required this.symbol,
    this.image,
    required this.tree,
  });

  final String symbol;
  final String? image;
  final String tree;

  factory GotSlot.fromJson(Map<String, dynamic> json) => GotSlot(
        symbol: _string(json['symbol']) ?? '',
        image: _string(json['image']),
        tree: _string(json['tree']) ?? '',
      );
}

/// Reflection counts on one watched Android framework method.
class NativeMethodCount {
  const NativeMethodCount({
    required this.method,
    required this.declared,
    required this.native,
  });

  final String method;
  final int declared;
  final int native;

  factory NativeMethodCount.fromJson(Map<String, dynamic> json) =>
      NativeMethodCount(
        method: _string(json['method']) ?? '',
        declared: _int(json['declared']) ?? 0,
        native: _int(json['native']) ?? 0,
      );
}

/// The runtime integrity layer's raw observations.
class IntegrityReport {
  const IntegrityReport({
    this.patchedNatives = const [],
    this.lies = const [],
    this.nativeSymbols = const [],
    this.objcMethods = const [],
    this.gotSlots,
    this.nativeMethods = const [],
  });

  final List<String> patchedNatives;
  final List<Lie> lies;
  final List<NativeSymbol> nativeSymbols;
  final List<ObjcMethod> objcMethods;
  final List<GotSlot>? gotSlots;
  final List<NativeMethodCount> nativeMethods;

  factory IntegrityReport.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const IntegrityReport();
    }

    final rawGotSlots = json['got_slots'];
    return IntegrityReport(
      patchedNatives: _strings(json['patched_natives']),
      lies: _maps(json['lies']).map(Lie.fromJson).toList(growable: false),
      nativeSymbols: _maps(json['native_symbols'])
          .map(NativeSymbol.fromJson)
          .toList(growable: false),
      objcMethods: _maps(json['objc_methods'])
          .map(ObjcMethod.fromJson)
          .toList(growable: false),
      gotSlots: rawGotSlots is List
          ? _maps(rawGotSlots).map(GotSlot.fromJson).toList(growable: false)
          : null,
      nativeMethods: _maps(json['native_methods'])
          .map(NativeMethodCount.fromJson)
          .toList(growable: false),
    );
  }
}

/// The whole client-side observation (`schema: 2` on native), as submitted.
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

/// What `identify()` resolves with (`schemas.IdentifyOut` in v3).
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
    this.triggers,
    required this.report,
  });

  /// Unique event identifier assigned by the server.
  final String requestId;

  /// Stable project-scoped visitor identifier, or `""` whenever
  /// [identifiable] is `false` (Option B), the report came from a genuine
  /// embedded WebView, or an unmatched report was withheld.
  final String visitorId;

  /// `true` only when a new visitor row was minted; always `false` when
  /// [visitorId] is empty.
  final bool visitorIsNew;

  /// How sure the server is of [visitorId], 0 to 100 (`0` when [visitorId] is
  /// `""`). Null when the native bridge omitted it.
  final int? visitorConfidence;

  /// `false` when the report carried too little independent signal to identify
  /// a device.
  final bool identifiable;

  /// `true` when this submission replayed a cached verdict under the same
  /// `Idempotency-Key`.
  final bool duplicate;

  /// The server's disposition of the check (`enriched` or `unavailable`).
  final String state;

  /// Why, when [state] needs explaining. Empty when omitted.
  final String reason;

  /// The server's score, or null when unscored or hidden by `hide_client_score`.
  ///
  /// Null and 0 are different answers: 0 is "scored, nothing fired". Do not
  /// collapse them with `?? 0` — that turns an unknown into a clean one.
  final int? suspectScore;

  /// The score as a band — `low`, `medium`, `high`. Null whenever
  /// [suspectScore] is null.
  final String? suspectLevel;

  /// Active risk signals and weights when returned by the caller's audience
  /// (omitted / null on public keys and standard native bridges).
  final List<IdentifyTrigger>? triggers;

  /// The raw client report that was collected and submitted.
  final SignalReport report;

  factory IdentifyResult.fromJson(Map<String, dynamic> json) {
    final rawIdentifiable = _bool(json['identifiable']);
    final rawVisitorId =
        _string(json['visitorId']) ?? _string(json['visitor_id']) ?? '';
    final identifiable = rawIdentifiable ?? rawVisitorId.isNotEmpty;
    // Option B: unidentifiable submissions never expose a visitorId.
    final visitorId = rawIdentifiable == false ? '' : rawVisitorId;
    final rawVisitorIsNew =
        _bool(json['visitorIsNew']) ?? _bool(json['visitor_is_new']) ?? false;
    final suspectScore =
        _int(json['suspectScore']) ?? _int(json['suspect_score']);
    final rawSuspectLevel =
        _string(json['suspectLevel']) ?? _string(json['suspect_level']);

    return IdentifyResult(
      requestId:
          _string(json['requestId']) ?? _string(json['request_id']) ?? '',
      visitorId: visitorId,
      visitorIsNew: visitorId.isEmpty ? false : rawVisitorIsNew,
      visitorConfidence:
          _int(json['visitorConfidence']) ?? _int(json['visitor_confidence']),
      identifiable: identifiable,
      duplicate: _bool(json['duplicate']) ?? false,
      state: _string(json['state']) ?? '',
      reason: _string(json['reason']) ?? '',
      suspectScore: suspectScore,
      suspectLevel: suspectScore == null ? null : rawSuspectLevel,
      triggers: _triggers(json['triggers']),
      report: SignalReport.fromJson(
        _map(json['report']) ?? const <String, dynamic>{},
      ),
    );
  }
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
  /// response named no wait. Wait at least this long before identifying again.
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
