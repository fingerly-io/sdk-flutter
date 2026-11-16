import 'dart:convert';
import 'dart:io';

import 'package:fingerly_flutter/fingerly_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('io.fingerly.sdk/flutter');

Map<String, Object?> _report() => {
      'schema': 2,
      'budget_ms': 1200,
      'elapsed_ms': 42,
      'sources': {
        'identity': {
          'status': 'ok',
          'ms': 1,
          'value': {'install_id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479'},
        },
        'hardware': {
          'status': 'ok',
          'ms': 2,
          'value': {'machine': 'iPhone16,1', 'gpu_family_max': 9},
        },
        'attest': {
          'status': 'unsupported',
          'ms': 1,
          'reason': 'simulator',
        },
      },
      'integrity': {
        'native_symbols': [
          {
            'symbol': 'lstat',
            'image': 'libsystem_kernel.dylib',
            'tree': 'dyld_shared_cache',
            'prologue': 'd503237f',
          },
        ],
        'objc_methods': [
          {
            'method': 'NSFileManager fileExistsAtPath:',
            'image': 'Foundation',
            'tree': 'dyld_shared_cache',
            'isa_swizzled': false,
            'msg_forward': false,
          },
        ],
        'got_slots': [
          {
            'symbol': 'lstat',
            'image': 'libsystem_kernel.dylib',
            'tree': 'dyld_shared_cache',
          },
        ],
      },
    };

Map<String, Object?> _identifyResult() => {
      'requestId': 'req_123',
      'visitorId': 'visitor_123',
      'visitorIsNew': true,
      'visitorConfidence': 92,
      'identifiable': true,
      'duplicate': false,
      'state': 'enriched',
      'reason': '',
      'suspectScore': 16,
      'suspectLevel': 'medium',
      'report': _report(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('configure & FingerlyConfig', () {
    test('load names the native platform and forwards configuration on iOS',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? received;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        received = call;
        return null;
      });

      await Fingerly.load(
        apiKey: 'fly_pk_development_mobile',
        endpoint: 'http://localhost:9000',
      );

      expect(received?.method, 'configure');
      expect(received?.arguments, {
        'apiKey': 'fly_pk_development_mobile',
        'endpoint': 'http://localhost:9000',
        'platform': 'flutter-ios',
        'consent': 'pending',
      });
    });

    test('configure(FingerlyConfig) forwards platform and consent on Android',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? received;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        received = call;
        return null;
      });

      final client = await Fingerly.configure(
        const FingerlyConfig(
          apiKey: 'fly_pk_development_mobile',
          endpoint: 'https://edge.example.com',
          consent: ConsentState.granted,
          playIntegrityCloudProjectNumber: 987654321098,
        ),
      );

      expect(client.consent, ConsentState.granted);
      expect(received?.method, 'configure');
      expect(received?.arguments, {
        'apiKey': 'fly_pk_development_mobile',
        'endpoint': 'https://edge.example.com',
        'platform': 'flutter-android',
        'consent': 'granted',
        'playIntegrityCloudProjectNumber': 987654321098,
      });
    });
  });

  group('Play Integrity', () {
    test('forwards playIntegrityCloudProjectNumber on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? received;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        received = call;
        return null;
      });

      await Fingerly.load(
        apiKey: 'fly_pk_development_mobile',
        playIntegrityCloudProjectNumber: 123456789012,
      );

      expect(received?.arguments, {
        'apiKey': 'fly_pk_development_mobile',
        'endpoint': '',
        'platform': 'flutter-android',
        'consent': 'pending',
        'playIntegrityCloudProjectNumber': 123456789012,
      });
    });

    test('omits playIntegrityCloudProjectNumber when null', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? received;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        received = call;
        return null;
      });

      await Fingerly.configure(
        const FingerlyConfig(apiKey: 'fly_pk_development_mobile'),
      );

      final args = received?.arguments as Map<Object?, Object?>;
      expect(args.containsKey('playIntegrityCloudProjectNumber'), isFalse);
    });

    test('allows passing playIntegrityCloudProjectNumber on iOS without error',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? received;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        received = call;
        return null;
      });

      await Fingerly.load(
        apiKey: 'fly_pk_development_mobile',
        playIntegrityCloudProjectNumber: 123456789012,
      );

      expect(received?.arguments, {
        'apiKey': 'fly_pk_development_mobile',
        'endpoint': '',
        'platform': 'flutter-ios',
        'consent': 'pending',
        'playIntegrityCloudProjectNumber': 123456789012,
      });
    });

    test('refuses non-positive project numbers before configuring', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return null;
      });

      for (final bad in [0, -1, -999]) {
        await expectLater(
          Fingerly.load(
            apiKey: 'fly_pk_development_mobile',
            playIntegrityCloudProjectNumber: bad,
          ),
          throwsArgumentError,
        );
        await expectLater(
          Fingerly.configure(
            FingerlyConfig(
              apiKey: 'fly_pk_development_mobile',
              playIntegrityCloudProjectNumber: bad,
            ),
          ),
          throwsArgumentError,
        );
      }
      expect(calls, isEmpty);
    });
  });

  group('consent', () {
    List<MethodCall> installGatedNative({bool withDetails = true}) {
      final calls = <MethodCall>[];
      var consent = 'pending';

      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        final arguments = (call.arguments as Map?)?.cast<String, Object?>();

        switch (call.method) {
          case 'configure':
            consent = arguments?['consent'] as String? ?? 'pending';
            return null;
          case 'setConsent':
            consent = arguments?['state'] as String? ?? 'pending';
            return null;
          case 'identify' || 'collect':
            if (consent != 'granted') {
              throw PlatformException(
                code: 'consent_required',
                message: 'Fingerly needs consent before it can identify this '
                    'visitor (consent is $consent)',
                details: withDetails ? {'state': consent} : null,
              );
            }
            return call.method == 'identify'
                ? jsonEncode(_identifyResult())
                : jsonEncode(_report());
          default:
            throw MissingPluginException();
        }
      });

      return calls;
    }

    test('defaults to pending, so nothing is identified until granted',
        () async {
      final calls = installGatedNative();

      final client = await Fingerly.load(apiKey: 'fly_pk_development_mobile');

      expect(calls.first.arguments['consent'], 'pending');
      expect(client.consent, ConsentState.pending);
      await expectLater(
        client.identify(),
        throwsA(isA<FingerlyConsentException>()
            .having((error) => error.code, 'code', 'consent_required')
            .having((error) => error.state, 'state', ConsentState.pending)),
      );
      await expectLater(
          client.collect(), throwsA(isA<FingerlyConsentException>()));
    });

    test('identifies when loaded with consent granted', () async {
      final calls = installGatedNative();

      final client = await Fingerly.load(
          apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);
      final result = await client.identify();

      expect(calls.first.arguments['consent'], 'granted');
      expect(client.consent, ConsentState.granted);
      expect(result.requestId, 'req_123');
    });

    for (final state in [ConsentState.pending, ConsentState.denied]) {
      test('passes ${state.name} through to configure and refuses with it',
          () async {
        final calls = installGatedNative();

        final client = await Fingerly.load(
            apiKey: 'fly_pk_development_mobile', consent: state);

        expect(calls.single.method, 'configure');
        expect(calls.single.arguments['consent'], state.name);
        expect(client.consent, state);

        final matcher = throwsA(
          isA<FingerlyConsentException>()
              .having((error) => error.state, 'state', state)
              .having((error) => error.code, 'code', 'consent_required')
              .having((error) => error.status, 'status', isNull)
              .having(
                (error) => error.message,
                'message',
                'Fingerly needs consent before it can identify this visitor '
                    '(consent is ${state.name})',
              ),
        );
        await expectLater(client.identify(), matcher);
        await expectLater(client.collect(), matcher);
      });
    }

    test('setConsent forwards to native and keeps the getter in step',
        () async {
      final calls = installGatedNative();
      final client = await Fingerly.load(
          apiKey: 'fly_pk_development_mobile', consent: ConsentState.pending);

      final pending = client.setConsent(ConsentState.denied);
      expect(client.consent, ConsentState.denied);
      await pending;

      await client.setConsent(ConsentState.granted);

      final forwarded = calls.where((call) => call.method == 'setConsent');
      expect(forwarded.map((call) => call.arguments), [
        {'state': 'denied'},
        {'state': 'granted'},
      ]);
      expect(client.consent, ConsentState.granted);
    });

    test('identifies once consent is granted', () async {
      installGatedNative();
      final client = await Fingerly.load(
          apiKey: 'fly_pk_development_mobile', consent: ConsentState.pending);

      await expectLater(
          client.identify(), throwsA(isA<FingerlyConsentException>()));

      // Not awaited: channel calls arrive in order, so identify sees it.
      client.setConsent(ConsentState.granted);
      final result = await client.identify();

      expect(result.requestId, 'req_123');
    });

    test('reads the state from the message when the plugin sends no details',
        () async {
      installGatedNative(withDetails: false);
      final client = await Fingerly.load(
          apiKey: 'fly_pk_development_mobile', consent: ConsentState.denied);

      await expectLater(
        client.collect(),
        throwsA(isA<FingerlyConsentException>()
            .having((error) => error.state, 'state', ConsentState.denied)),
      );
    });

    test('is still a FingerlyException for existing handlers', () async {
      messenger.setMockMethodCallHandler(
        _channel,
        (call) async => call.method == 'configure'
            ? null
            : throw PlatformException(code: 'consent_required'),
      );
      final client = await Fingerly.load(apiKey: 'fly_pk_development_mobile');

      await expectLater(
        client.identify(),
        throwsA(isA<FingerlyException>().having(
          (error) => (error as FingerlyConsentException).state,
          'state',
          ConsentState.pending,
        )),
      );
    });
  });

  group('v3 IdentifyResult & Option B contract', () {
    test('identify forwards options and decodes the complete native result',
        () async {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'configure') return null;
        expect(call.method, 'identify');
        expect(call.arguments, {
          'tag': 'checkout',
          'submit': true,
          'automatic': false,
        });
        return jsonEncode(_identifyResult());
      });

      final client = await Fingerly.load(
          apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);
      final result = await client.identify(tag: 'checkout');

      expect(result.requestId, 'req_123');
      expect(result.visitorId, 'visitor_123');
      expect(result.visitorIsNew, isTrue);
      expect(result.visitorConfidence, 92);
      expect(result.identifiable, isTrue);
      expect(result.duplicate, isFalse);
      expect(result.state, 'enriched');
      expect(result.suspectScore, 16);
      expect(result.suspectLevel, 'medium');
      expect(result.triggers, isNull);
      expect(result.report.schema, 2);
      expect(result.report.sources['hardware']?.status, SignalStatus.ok);
      expect(result.report.sources['attest']?.reason, 'simulator');
      expect(result.report.integrity.nativeSymbols.single.symbol, 'lstat');
      expect(
        result.report.integrity.objcMethods.single.method,
        'NSFileManager fileExistsAtPath:',
      );
      expect(result.report.integrity.gotSlots?.single.symbol, 'lstat');
    });

    test(
        'Option B: visitorId is empty and visitorIsNew is false when identifiable is false',
        () {
      final unidentifiable = IdentifyResult.fromJson({
        'requestId': 'req_unid_1',
        'identifiable': false,
        'visitorId': '',
        'visitorIsNew': false,
        'visitorConfidence': 0,
        'duplicate': false,
        'state': 'enriched',
        'suspectScore': 15,
        'suspectLevel': 'medium',
        'report': _report(),
      });

      expect(unidentifiable.identifiable, isFalse);
      expect(unidentifiable.visitorId, '');
      expect(unidentifiable.visitorIsNew, isFalse);
      expect(unidentifiable.visitorConfidence, 0);

      // Even if a stale or malformed payload supplied a non-empty visitorId or
      // visitorIsNew: true while identifiable == false, Option B enforces "".
      final enforced = IdentifyResult.fromJson({
        'request_id': 'req_unid_2',
        'identifiable': false,
        'visitor_id': 'stale_visitor',
        'visitor_is_new': true,
        'visitor_confidence': 0,
        'state': 'enriched',
      });

      expect(enforced.requestId, 'req_unid_2');
      expect(enforced.identifiable, isFalse);
      expect(enforced.visitorId, '');
      expect(enforced.visitorIsNew, isFalse);
      expect(enforced.visitorConfidence, 0);
    });

    test('visitorIsNew is always false whenever visitorId is empty', () {
      final withheld = IdentifyResult.fromJson({
        'requestId': 'req_webview',
        'identifiable': true,
        'visitorId': '',
        'visitorIsNew': true,
        'visitorConfidence': 0,
        'state': 'enriched',
      });

      expect(withheld.identifiable, isTrue);
      expect(withheld.visitorId, '');
      expect(withheld.visitorIsNew, isFalse);
    });

    test('duplicate is a non-nullable bool preserving replayed verdicts', () {
      final replayed = IdentifyResult.fromJson({
        'requestId': 'req_dup',
        'visitorId': '',
        'identifiable': false,
        'duplicate': true,
        'state': 'enriched',
      });
      final fresh = IdentifyResult.fromJson({'requestId': 'req_fresh'});

      expect(replayed.duplicate, isTrue);
      expect(replayed.visitorId, '');
      expect(replayed.visitorIsNew, isFalse);
      expect(fresh.duplicate, isFalse);
    });

    test('audience-gated suspectScore and suspectLevel stay null, never 0',
        () async {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'configure') return null;
        return jsonEncode(_identifyResult()
          ..['suspectScore'] = null
          ..['suspectLevel'] = null);
      });
      final client = await Fingerly.load(
          apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);

      final result = await client.identify();

      expect(result.suspectScore, isNull);
      expect(result.suspectLevel, isNull);

      final zeroScored = IdentifyResult.fromJson(_identifyResult()
        ..['suspectScore'] = 0
        ..['suspectLevel'] = 'low');
      expect(zeroScored.suspectScore, 0);
      expect(zeroScored.suspectLevel, 'low');

      // suspectLevel is always null whenever suspectScore is null.
      final mismatched = IdentifyResult.fromJson(_identifyResult()
        ..['suspectScore'] = null
        ..['suspectLevel'] = 'low');
      expect(mismatched.suspectScore, isNull);
      expect(mismatched.suspectLevel, isNull);
    });

    test('decodes v3 triggers and maps canonical RiskSignal values', () {
      final result = IdentifyResult.fromJson(_identifyResult()
        ..['triggers'] = [
          {
            'signal': 'attestation_failed',
            'group': 'attestation_failed',
            'weight': 30,
            'confidence': 'high',
          },
          {
            'signal': 'custom_root_ca',
            'group': 'custom_root_ca',
            'weight': 0,
            'confidence': 'medium',
          },
          {
            'signal': 'future_server_signal',
            'weight': 5,
          },
          'malformed-entry',
          {'weight': 10},
        ]);

      expect(result.triggers, hasLength(3));
      expect(result.triggers![0].signal, 'attestation_failed');
      expect(result.triggers![0].riskSignal, RiskSignal.attestationFailed);
      expect(result.triggers![0].weight, 30);
      expect(result.triggers![0].confidence, 'high');
      expect(result.triggers![1].riskSignal, RiskSignal.customRootCa);
      expect(result.triggers![1].weight, 0);
      expect(result.triggers![2].signal, 'future_server_signal');
      expect(result.triggers![2].riskSignal, isNull);
    });

    test('enumerates all orthogonal v3 risk signals', () {
      const expectedSignals = [
        'high_activity',
        'tampering',
        'device_farm',
        'developer_tools',
        'geo_mismatch',
        'device_inconsistent',
        'report_incomplete',
        'fingerprint_suppressed',
        'tor',
        'proxy',
        'residential_proxy',
        'residential_proxy_low_confidence',
        'residential_proxy_medium_confidence',
        'residential_proxy_high_confidence',
        'vpn_public',
        'vpn_timezone',
        'vpn_relay',
        'vpn_mobile',
        'vpn_os_mismatch',
        'vpn_low_confidence',
        'vpn_medium_confidence',
        'vpn_high_confidence',
        'ip_blocklist_email_spam',
        'ip_blocklist_attack_source',
        'ip_abuser',
        'datacenter_ip',
        'bogon_ip',
        'anycast_ip',
        'incognito',
        'bad_bot',
        'automation',
        'fetch_metadata_missing',
        'antidetect_browser',
        'virtual_machine',
        'privacy_settings',
        'embedded_web_view',
        'remote_control',
        'emulator',
        'root_apps',
        'app_cloner',
        'jailbreak',
        'simulator',
        'frida',
        'mitm_attack',
        'active_call',
        'attestation_missing',
        'attestation_downgrade',
        'app_attest_key_churn',
        'play_device_integrity_failed',
        'play_app_unrecognized',
        'attestation_failed',
        'probe_errors',
        'custom_root_ca',
        'secondary_user_profile',
      ];

      expect(
        RiskSignal.values.map((signal) => signal.wire).toList(),
        expectedSignals,
      );
      for (final wire in expectedSignals) {
        expect(RiskSignal.tryParse(wire)?.wire, wire);
      }
      expect(RiskSignal.tryParse('unknown_signal'), isNull);
      expect(RiskSignal.tryParse(42), isNull);
    });

    test('identify forwards automatic and removes retired submit/tiers options',
        () async {
      Object? arguments;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'configure') return null;
        arguments = call.arguments;
        return jsonEncode(_identifyResult());
      });

      final client = await Fingerly.load(
          apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);
      await client.identify(automatic: true);

      expect(arguments, {'tag': null, 'submit': true, 'automatic': true});
    });

    test('decodes Android schema 2 native_methods integrity observations', () {
      final report = SignalReport.fromJson({
        'schema': 2,
        'budget_ms': 1200,
        'elapsed_ms': 38,
        'sources': const <String, Object?>{},
        'integrity': {
          'native_methods': [
            {
              'method': 'java.io.File!exists',
              'declared': 1,
              'native': 1,
            },
          ],
        },
      });

      expect(report.schema, 2);
      expect(
          report.integrity.nativeMethods.single.method, 'java.io.File!exists');
      expect(report.integrity.nativeMethods.single.declared, 1);
      expect(report.integrity.nativeMethods.single.native, 1);
      expect(report.integrity.gotSlots, isNull);
    });
  });

  test('collect and nativeVersion use their dedicated bridge methods',
      () async {
    messenger.setMockMethodCallHandler(
        _channel,
        (call) async => switch (call.method) {
              'configure' => null,
              'collect' => jsonEncode(_report()),
              'sdkVersion' => '0.3.0',
              _ => throw MissingPluginException(),
            });

    final client = await Fingerly.load(
        apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);
    final report = await client.collect();

    expect(report.schema, 2);
    expect(report.elapsedMs, 42);
    expect(await Fingerly.nativeVersion(), '0.3.0');
  });

  group('deleteStoredIdentity (GDPR erasure)', () {
    test('asks the native SDK without load or consent', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        return null;
      });

      await Fingerly.deleteStoredIdentity();
      expect(calls, ['deleteStoredIdentity']);
    });

    test('says so when the native SDK predates it', () async {
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw MissingPluginException(),
      );

      await expectLater(
        Fingerly.deleteStoredIdentity(),
        throwsA(
          isA<FingerlyException>().having(
            (error) => error.message,
            'message',
            contains('deleteStoredIdentity is not available'),
          ),
        ),
      );
    });

    test('surfaces a failed delete as a FingerlyException with null status',
        () async {
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(
          code: 'delete_failed',
          message: 'Fingerly could not delete its stored install record',
        ),
      );

      await expectLater(
        Fingerly.deleteStoredIdentity(),
        throwsA(
          isA<FingerlyException>()
              .having((error) => error.message, 'message',
                  'Fingerly could not delete its stored install record')
              .having((error) => error.status, 'status', isNull),
        ),
      );
    });

    test('dartdoc states GDPR/privacy-only erasure of install_id and key state',
        () {
      final source = File('lib/fingerly_flutter.dart').readAsStringSync();
      expect(source, contains('GDPR'));
      expect(source, contains('install_id'));
      expect(source, contains('attestation key state'));
    });
  });

  group('error mapping & defensive decoding', () {
    test('platform failures preserve HTTP status and ignore negative sentinels',
        () async {
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(code: '402', message: 'disabled'),
      );

      await expectLater(
        Fingerly.load(apiKey: 'fly_pk_development_mobile'),
        throwsA(
          isA<FingerlyException>()
              .having((error) => error.status, 'status', 402)
              .having((error) => error.message, 'message', 'disabled'),
        ),
      );

      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(code: '-1', message: 'no report'),
      );

      await expectLater(
        Fingerly.nativeVersion(),
        throwsA(
          isA<FingerlyException>()
              .having((error) => error.status, 'status', isNull)
              .having((error) => error.message, 'message', 'no report'),
        ),
      );
    });

    test('a native Retry-After reaches FingerlyException.retryAfter', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method != 'identify') return null;
        throw PlatformException(
          code: '429',
          message: 'Too many requests',
          details: {'retryAfterMs': 3000},
        );
      });
      final fingerly = await Fingerly.load(apiKey: 'fly_pk_development_mobile');

      await expectLater(
        fingerly.identify(),
        throwsA(
          isA<FingerlyException>()
              .having((error) => error.status, 'status', 429)
              .having((error) => error.retryAfter, 'retryAfter',
                  const Duration(seconds: 3)),
        ),
      );
    });

    test('retryAfter is null when the failure named no wait', () async {
      for (final details in <Object?>[
        null,
        {'retryAfterMs': 'soon'},
        {'retryAfterMs': -1},
        {'state': 'pending-not-a-consent-code'},
      ]) {
        messenger.setMockMethodCallHandler(
          _channel,
          (_) async => throw PlatformException(
            code: '503',
            message: 'unavailable',
            details: details,
          ),
        );

        await expectLater(
          Fingerly.nativeVersion(),
          throwsA(isA<FingerlyException>()
              .having((error) => error.retryAfter, 'retryAfter', isNull)),
          reason: '$details',
        );
      }
    });

    test('a missing native plugin becomes an actionable FingerlyException',
        () async {
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw MissingPluginException(),
      );

      await expectLater(
        Fingerly.nativeVersion(),
        throwsA(
          isA<FingerlyException>().having(
            (error) => error.message,
            'message',
            contains('flutter clean'),
          ),
        ),
      );
    });

    test('unknown native enum values degrade safely', () {
      final outcome = SignalOutcome.fromJson({
        'status': 'new-native-status',
        'ms': 3,
      });

      expect(outcome.status, SignalStatus.error);
    });

    test('a result without reason and with unknown members still decodes', () {
      final json = _identifyResult()
        ..remove('reason')
        ..['next_attestation'] = {'challenge': 'chk_1'}
        ..['somethingNew'] = {'nested': true};

      final result = IdentifyResult.fromJson(json);

      expect(result.requestId, 'req_123');
      expect(result.reason, '');
      expect(result.suspectScore, 16);
    });

    test('members of the wrong type read as missing instead of throwing', () {
      final result = IdentifyResult.fromJson({
        'requestId': 42,
        'visitorIsNew': 'yes',
        'visitorConfidence': '92',
        'identifiable': 'true',
        'duplicate': 'no',
        'suspectScore': 'high',
        'triggers': 'not-a-list',
        'report': {
          'schema': '2',
          'sources': {
            'device': {
              'status': 'ok',
              'ms': 2,
              'value': ['not', 'a', 'map'],
            },
            'broken': 'not-an-outcome',
          },
          'integrity': {
            'patched_natives': 'dlsym',
            'lies': [
              {'id': 'x', 'kind': 'swizzled'},
              5,
            ],
          },
        },
      });

      expect(result.requestId, '');
      expect(result.visitorId, '');
      expect(result.visitorIsNew, isFalse);
      expect(result.identifiable, isFalse);
      expect(result.duplicate, isFalse);
      expect(result.visitorConfidence, isNull);
      expect(result.suspectScore, isNull);
      expect(result.triggers, isNull);
      expect(result.report.schema, 0);
      expect(result.report.sources.keys, ['device']);
      expect(result.report.sources['device']!.value, isNull);
      expect(result.report.integrity.patchedNatives, isEmpty);
      expect(result.report.integrity.lies.single.kind, 'swizzled');
    });

    test('an unreadable or null native answer is a FingerlyException',
        () async {
      for (final raw in <String?>[null, 'not json', '[1, 2]', '"text"']) {
        messenger.setMockMethodCallHandler(
          _channel,
          (call) async => call.method == 'configure' ? null : raw,
        );
        final fingerly =
            await Fingerly.load(apiKey: 'fly_pk_development_mobile');

        await expectLater(
          fingerly.identify(),
          throwsA(isA<FingerlyException>()),
          reason: '$raw',
        );
        await expectLater(
          fingerly.collect(),
          throwsA(isA<FingerlyException>()),
          reason: '$raw',
        );
      }
    });
  });

  group('0.3.0 version parity', () {
    test(
        'plugin, podspec, Package.swift, build.gradle, and docs agree on 0.3.0',
        () {
      expect(Fingerly.pluginVersion, '0.3.0');

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: 0.3.0'));

      final podspec = File('ios/fingerly_flutter.podspec').readAsStringSync();
      expect(podspec, contains("native_version = '0.3.0'"));
      expect(podspec, contains("s.version          = '0.3.0'"));
      expect(
        podspec,
        contains(
          "native_sha256  = 'c1d582eae15243fb63e3e55e68909490060f2b8232624b1025bb931c3100b4cc'",
        ),
      );
      expect(podspec, contains("native_team_id = 'XGXX88HRR5'"));
      expect(podspec, contains('FINGERLY_XCFRAMEWORK_PATH'));

      final spm = File('ios/fingerly_flutter/Package.swift').readAsStringSync();
      expect(
        spm,
        contains(
          '.package(url: "https://github.com/fingerly-io/sdk-ios", exact: "0.3.0")',
        ),
      );
      expect(spm, contains('FINGERLY_XCFRAMEWORK_PATH'));

      final gradle = File('android/build.gradle').readAsStringSync();
      expect(gradle, contains("version '0.3.0'"));
      expect(gradle, contains('mavenLocal()'));
      expect(gradle, contains("implementation 'io.fingerly:fingerly:0.3.0'"));

      final changelog = File('CHANGELOG.md').readAsStringSync();
      expect(changelog, contains('## 0.3.0'));

      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('fingerly_flutter: ^0.3.0'));
      expect(readme, contains('io.fingerly:fingerly:0.3.0'));
    });
  });
}
