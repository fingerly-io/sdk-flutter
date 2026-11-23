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

    test('decodes v3 triggers and compares them with the Signal constants', () {
      final result = IdentifyResult.fromJson(_identifyResult()
        ..['triggers'] = [
          {
            'signal': 'attestation_failed',
            'group': 'attestation_failed',
            'weight': 30,
            'confidence': 'high',
          },
          {
            'signal': 'vpn_public',
            'group': 'vpn',
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
      expect(result.triggers![0].signal, Signal.attestationFailed);
      expect(result.triggers![0].weight, 30);
      expect(result.triggers![0].confidence, Confidence.high);
      expect(result.triggers![1].signal, Signal.vpnPublic);
      expect(result.triggers![1].group, Signal.vpn);
      expect(result.triggers![1].weight, 0);
      expect(result.triggers![1].confidence, Confidence.medium);
      // A signal a newer server adds arrives unchanged.
      expect(result.triggers![2].signal, 'future_server_signal');
      expect(Signal.values, isNot(contains('future_server_signal')));
    });

    test('Signal names every server signal group and detector', () {
      // The server's list (server/domain/risk), member by member.
      const serverSignals = <String, String>{
        Signal.activeCall: 'active_call',
        Signal.aiSpoofed: 'ai_spoofed',
        Signal.androidEmulator: 'android_emulator',
        Signal.antidetectBrowser: 'antidetect_browser',
        Signal.anycastIp: 'anycast_ip',
        Signal.appCloner: 'app_cloner',
        Signal.attestationDowngrade: 'attestation_downgrade',
        Signal.attestationFailed: 'attestation_failed',
        Signal.attestationMissing: 'attestation_missing',
        Signal.automation: 'automation',
        Signal.badBot: 'bad_bot',
        Signal.bogonIp: 'bogon_ip',
        Signal.bootloaderUnlocked: 'bootloader_unlocked',
        Signal.bot: 'bot',
        Signal.browserTampering: 'browser_tampering',
        Signal.clonedApp: 'cloned_app',
        Signal.customRootCa: 'custom_root_ca',
        Signal.datacenterIp: 'datacenter_ip',
        Signal.datacenterProxy: 'datacenter_proxy',
        Signal.developerTools: 'developer_tools',
        Signal.deviceActivityHigh: 'device_activity_high',
        Signal.deviceActivityVeryHigh: 'device_activity_very_high',
        Signal.deviceFarm: 'device_farm',
        Signal.deviceInconsistent: 'device_inconsistent',
        Signal.embeddedWebView: 'embedded_web_view',
        Signal.emulator: 'emulator',
        Signal.fetchMetadataMissing: 'fetch_metadata_missing',
        Signal.fingerprintSuppressed: 'fingerprint_suppressed',
        Signal.frida: 'frida',
        Signal.fridaDetected: 'frida_detected',
        Signal.geoMismatch: 'geo_mismatch',
        Signal.highActivity: 'high_activity',
        Signal.identityObfuscated: 'identity_obfuscated',
        Signal.incognito: 'incognito',
        Signal.incognitoMode: 'incognito_mode',
        Signal.iosSimulator: 'ios_simulator',
        Signal.ipAbuser: 'ip_abuser',
        Signal.ipBlocklist: 'ip_blocklist',
        Signal.ipBlocklistAttackSource: 'ip_blocklist_attack_source',
        Signal.ipBlocklistEmailSpam: 'ip_blocklist_email_spam',
        Signal.ipReputation: 'ip_reputation',
        Signal.jailbreak: 'jailbreak',
        Signal.jailbrokenDevice: 'jailbroken_device',
        Signal.locationSpoofing: 'location_spoofing',
        Signal.mitmAttack: 'mitm_attack',
        Signal.networkAnomaly: 'network_anomaly',
        Signal.playAppUnrecognized: 'play_app_unrecognized',
        Signal.playDeviceIntegrityFailed: 'play_device_integrity_failed',
        Signal.privacySettings: 'privacy_settings',
        Signal.probeErrors: 'probe_errors',
        Signal.proxy: 'proxy',
        Signal.remoteControl: 'remote_control',
        Signal.repeatedReinstall: 'repeated_reinstall',
        Signal.reportIncomplete: 'report_incomplete',
        Signal.residentialProxy: 'residential_proxy',
        Signal.residentialProxyHighConfidence:
            'residential_proxy_high_confidence',
        Signal.residentialProxyLowConfidence:
            'residential_proxy_low_confidence',
        Signal.residentialProxyMediumConfidence:
            'residential_proxy_medium_confidence',
        Signal.rootApps: 'root_apps',
        Signal.rootedDevice: 'rooted_device',
        Signal.secondaryUserProfile: 'secondary_user_profile',
        Signal.simulator: 'simulator',
        Signal.tampering: 'tampering',
        Signal.tor: 'tor',
        Signal.virtualMachine: 'virtual_machine',
        Signal.vpn: 'vpn',
        Signal.vpnHighConfidence: 'vpn_high_confidence',
        Signal.vpnLowConfidence: 'vpn_low_confidence',
        Signal.vpnMediumConfidence: 'vpn_medium_confidence',
        Signal.vpnMobile: 'vpn_mobile',
        Signal.vpnOsMismatch: 'vpn_os_mismatch',
        Signal.vpnPublic: 'vpn_public',
        Signal.vpnRelay: 'vpn_relay',
        Signal.webTicketInvalid: 'web_ticket_invalid',
        Signal.webTicketMissing: 'web_ticket_missing',
      };

      expect(serverSignals, hasLength(75));
      for (final entry in serverSignals.entries) {
        expect(entry.key, entry.value);
      }
      expect(Signal.values.toSet(), serverSignals.values.toSet());
      expect(Signal.values, hasLength(75), reason: 'no duplicates');
      expect(Signal.values, isNot(contains('app_attest_key_churn')));
    });

    test('the level, confidence, state and consent constants match the server',
        () {
      expect(SuspectLevel.values, ['low', 'medium', 'high']);
      expect(SuspectLevel.low, 'low');
      expect(SuspectLevel.medium, 'medium');
      expect(SuspectLevel.high, 'high');

      expect(Confidence.values, ['low', 'medium', 'high']);
      expect(Confidence.low, 'low');
      expect(Confidence.medium, 'medium');
      expect(Confidence.high, 'high');

      expect(EventState.values, ['pending', 'enriched', 'unavailable']);
      expect(EventState.pending, 'pending');
      expect(EventState.enriched, 'enriched');
      expect(EventState.unavailable, 'unavailable');

      expect(ConsentState.values.map((state) => state.name).toList(),
          ['granted', 'pending', 'denied']);
    });

    test('result fields compare and switch on the constants', () {
      final result = IdentifyResult.fromJson(_identifyResult()
        ..['state'] = 'enriched'
        ..['suspectScore'] = 80
        ..['suspectLevel'] = 'high');

      expect(result.state, EventState.enriched);
      expect(result.suspectLevel, SuspectLevel.high);
      final band = switch (result.suspectLevel) {
        SuspectLevel.high => 'review',
        SuspectLevel.medium || SuspectLevel.low => 'allow',
        _ => 'not scored',
      };
      expect(band, 'review');

      // Values a newer server adds reach the app unchanged.
      final newer = IdentifyResult.fromJson(_identifyResult()
        ..['state'] = 'state_from_a_newer_server'
        ..['suspectScore'] = 50
        ..['suspectLevel'] = 'level_from_a_newer_server');
      expect(newer.state, 'state_from_a_newer_server');
      expect(newer.suspectLevel, 'level_from_a_newer_server');
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
              'sdkVersion' => '0.4.0',
              _ => throw MissingPluginException(),
            });

    final client = await Fingerly.load(
        apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);
    final report = await client.collect();

    expect(report.schema, 2);
    expect(report.elapsedMs, 42);
    expect(await Fingerly.nativeVersion(), '0.4.0');
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

    test('an Android erasure also needs Erase a visitor (Android 0.5.0)', () {
      final source = File('lib/fingerly_flutter.dart').readAsStringSync();
      final readme = File('README.md').readAsStringSync();
      for (final text in [source, readme]) {
        expect(text, contains('Erase a'));
        expect(text, contains('ANDROID_ID'));
      }
      expect(
        readme,
        contains('a reinstall keeps its `visitorId` until a factory reset'),
      );
      expect(source, isNot(contains('so a future\n  /// re-consented')));
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

  group('0.5.0 version parity', () {
    test(
        'plugin, podspec, Package.swift, build.gradle, and docs agree on 0.5.0',
        () {
      expect(Fingerly.pluginVersion, '0.5.0');

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: 0.5.0'));

      final podspec = File('ios/fingerly_flutter.podspec').readAsStringSync();
      expect(podspec, contains("native_version = '0.4.1'"));
      expect(podspec, contains("s.version          = '0.5.0'"));
      expect(
        podspec,
        contains(
          "native_sha256  = '74bb15a4b72b55524f4d2cb8567037c7f76088747bb5c866dfee61eb5f7d056e'",
        ),
      );
      expect(podspec, contains("native_team_id = 'XGXX88HRR5'"));
      expect(podspec, contains('FINGERLY_XCFRAMEWORK_PATH'));

      final spm = File('ios/fingerly_flutter/Package.swift').readAsStringSync();
      expect(
        spm,
        contains(
          '.package(url: "https://github.com/fingerly-io/sdk-ios", exact: "0.4.1")',
        ),
      );
      expect(spm, contains('FINGERLY_XCFRAMEWORK_PATH'));

      final gradle = File('android/build.gradle').readAsStringSync();
      expect(gradle, contains("version '0.5.0'"));
      expect(gradle, contains('mavenLocal()'));
      // An app that leaves out the optional artifacts must still pass R8.
      expect(gradle, contains("consumerProguardFiles 'consumer-rules.pro'"));
      final rules = File('android/consumer-rules.pro').readAsStringSync();
      expect(rules, contains('-dontwarn io.fingerly.sdk.appchecks.**'));
      expect(rules, contains('-dontwarn io.fingerly.sdk.playintegrity.**'));
      expect(gradle, contains("implementation 'io.fingerly:fingerly:0.5.0'"));
      expect(gradle,
          contains("compileOnly 'io.fingerly:fingerly-app-checks:0.5.0'"));
      expect(gradle,
          contains("compileOnly 'io.fingerly:fingerly-play-integrity:0.5.0'"));

      final changelog = File('CHANGELOG.md').readAsStringSync();
      expect(changelog, contains('## 0.5.0'));

      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('fingerly_flutter: ^0.5.0'));
      expect(readme, contains('io.fingerly:fingerly:0.5.0'));
      expect(readme, isNot(contains('io.fingerly:fingerly:0.4.0')));
    });
  });
}
