import 'dart:convert';

import 'package:fingerly_flutter/fingerly_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('io.fingerly.sdk/flutter');

Map<String, Object?> _report() => {
      'schema': 1,
      'budget_ms': 1200,
      'elapsed_ms': 42,
      'sources': {
        'device': {
          'status': 'ok',
          'ms': 2,
          'value': {'platform': 'ios'},
        },
        'attest': {
          'status': 'unsupported',
          'ms': 1,
          'reason': 'simulator',
        },
      },
      'integrity': {
        'patched_natives': <String>[],
        'lies': <Object?>[],
      },
    };

Map<String, Object?> _identifyResult() => {
      'requestId': 'req_123',
      'visitorId': 'visitor_123',
      'visitorIsNew': true,
      'visitorConfidence': 92,
      'identifiable': true,
      'duplicate': false,
      'state': 'accepted',
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

  test('configure names the native platform and forwards configuration',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    MethodCall? received;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      received = call;
      return null;
    });

    await Fingerly.load(
        apiKey: 'fly_pk_development_mobile', endpoint: 'http://localhost:9000');

    expect(received?.method, 'configure');
    expect(received?.arguments, {
      'apiKey': 'fly_pk_development_mobile',
      'endpoint': 'http://localhost:9000',
      'platform': 'flutter-ios',
      'consent': 'pending',
    });
  });

  group('Play Integrity', () {
    test('forwards the project number to the native side', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? received;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        received = call;
        return null;
      });

      await Fingerly.load(
          apiKey: 'fly_pk_development_mobile',
          playIntegrityCloudProjectNumber: 123456789012);

      expect(received?.arguments, {
        'apiKey': 'fly_pk_development_mobile',
        'endpoint': '',
        'platform': 'flutter-android',
        'consent': 'pending',
        'playIntegrityCloudProjectNumber': 123456789012,
      });
    });

    test('refuses a number that is not a project before configuring',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return null;
      });

      for (final bad in [0, -1]) {
        await expectLater(
          Fingerly.load(
              apiKey: 'fly_pk_development_mobile',
              playIntegrityCloudProjectNumber: bad),
          throwsArgumentError,
        );
      }
      expect(calls, isEmpty);
    });
  });

  group('consent', () {
    /// A native side that keeps its own consent, as `FingerlyBridge` does, and
    /// refuses `identify` and `collect` with `consent_required` until it is
    /// granted. `withDetails` imitates the iOS plugin, which sends the state in
    /// `details`; the Android plugin sends a code and a message only.
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
      // Changed before the native side has answered.
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

  test('identify forwards options and decodes the complete native result',
      () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'configure') return null;
      expect(call.method, 'identify');
      expect(call.arguments,
          {'tag': 'checkout', 'submit': true, 'automatic': false});
      return jsonEncode(_identifyResult());
    });

    final client = await Fingerly.load(
        apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);
    final result = await client.identify(tag: 'checkout');

    expect(result.requestId, 'req_123');
    expect(result.visitorId, 'visitor_123');
    expect(result.suspectScore, 16);
    expect(result.suspectLevel, 'medium');
    expect(result.report.sources['device']?.status, SignalStatus.ok);
    expect(result.report.sources['attest']?.reason, 'simulator');
  });

  test('identify(submit: false) surfaces the raw report and nothing else',
      () async {
    // Forged: a native side that fills the server's fields anyway must not be
    // able to make an unsent check look answered.
    final forged = _identifyResult()..['verdicts'] = {'jailbreak': true};
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'configure') return null;
      expect(
          call.arguments, {'tag': null, 'submit': false, 'automatic': false});
      return jsonEncode(forged);
    });

    final client = await Fingerly.load(
        apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);
    final result = await client.identify(submit: false);

    expect(result.report.sources.keys, ['device', 'attest']);
    expect(result.requestId, '');
    expect(result.visitorId, '');
    expect(result.visitorConfidence, isNull);
    expect(result.visitorIsNew, isNull);
    expect(result.identifiable, isNull);
    expect(result.duplicate, isNull);
    expect(result.suspectScore, isNull);
    expect(result.suspectLevel, isNull);
    expect(result.state, '');
    expect(result.reason, '');
  });

  test('identify(submit: false) refuses an answer with no readable report',
      () async {
    for (final answer in <Object?>[
      <String, Object?>{},
      {'report': null},
      {'report': 'text'},
      {
        'report': [1]
      },
    ]) {
      messenger.setMockMethodCallHandler(
        _channel,
        (call) async => call.method == 'configure' ? null : jsonEncode(answer),
      );
      final client = await Fingerly.load(
          apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);

      await expectLater(
        client.identify(submit: false),
        throwsA(isA<FingerlyException>()),
        reason: '$answer',
      );
    }
  });

  test('a stale native signal list or verdict never reaches the Dart result',
      () {
    for (final stale in <Object?>[
      [
        {'signal': 'simulator', 'weight': 16, 'confidence': 'high'},
      ],
      'not-a-list',
      null,
      7,
    ]) {
      final result = IdentifyResult.fromJson(_identifyResult()
        ..['triggers'] = stale
        ..['futureMember'] = {'nested': true}
        ..['verdicts'] = {
          'jailbreak': {'value': true, 'confidence': 'high', 'reasons': []},
        });

      expect(result.suspectScore, 16, reason: '$stale');
      expect(() => (result as dynamic).triggers, throwsNoSuchMethodError);
      expect(() => (result as dynamic).verdicts, throwsNoSuchMethodError);
    }
  });

  test('a score reads from an answer that has no signals', () {
    final result = IdentifyResult.fromJson(_identifyResult());

    expect(result.suspectScore, 16);
    expect(result.suspectLevel, 'medium');
  });

  test('an answer with neither score nor signals reads as no answer', () {
    final result = IdentifyResult.fromJson(_identifyResult()
      ..remove('suspectScore')
      ..remove('suspectLevel'));

    expect(result.requestId, 'req_123');
    expect(result.visitorId, 'visitor_123');
    expect(result.suspectScore, isNull);
    expect(result.suspectLevel, isNull);
  });

  test('a null score crosses the channel as null, not 0 or an empty string',
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
  });

  test('a null score stays null when the server did not score', () {
    final result = IdentifyResult.fromJson(_identifyResult()
      ..['suspectScore'] = null
      ..['suspectLevel'] = null);

    expect(result.suspectScore, isNull);
    expect(result.suspectLevel, isNull);
  });

  test('identify forwards automatic', () async {
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

  test('collect and nativeVersion use their dedicated bridge methods',
      () async {
    messenger.setMockMethodCallHandler(
        _channel,
        (call) async => switch (call.method) {
              'configure' => null,
              'collect' => jsonEncode(_report()),
              'sdkVersion' => '0.1.0',
              _ => throw MissingPluginException(),
            });

    final client = await Fingerly.load(
        apiKey: 'fly_pk_development_mobile', consent: ConsentState.granted);
    final report = await client.collect();

    expect(report.schema, 1);
    expect(report.elapsedMs, 42);
    expect(await Fingerly.nativeVersion(), '0.1.0');
  });

  group('deleteStoredIdentity', () {
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

    test('surfaces a failed delete as a FingerlyException', () async {
      // Both plugins refuse with this code and message.
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
  });

  test('platform failures preserve the HTTP status', () async {
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
  });

  test('a native Retry-After reaches FingerlyException.retryAfter', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
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
    // Since server 00f1eb5 an app is no longer told why a submission went
    // unscored, and a newer native SDK may add members this binding has
    // never heard of.
    final json = _identifyResult()
      ..remove('reason')
      ..['deferredToken'] = 'tok_1'
      ..['somethingNew'] = {'nested': true};

    final result = IdentifyResult.fromJson(json);

    expect(result.requestId, 'req_123');
    expect(result.reason, '');
    expect(result.suspectScore, 16);
  });

  test('an answer the server did not give stays null on both native shapes',
      () {
    final android = IdentifyResult.fromJson({
      'requestId': 'req_dup',
      'visitorIsNew': null,
      'visitorConfidence': null,
      'identifiable': null,
      'duplicate': null,
    });
    final ios = IdentifyResult.fromJson({'requestId': 'req_dup'});

    for (final result in [android, ios]) {
      expect(result.visitorIsNew, isNull);
      expect(result.visitorConfidence, isNull);
      expect(result.identifiable, isNull);
      expect(result.duplicate, isNull);
    }
  });

  test('a duplicate answer keeps its flag with the visitor fields empty', () {
    final result = IdentifyResult.fromJson(
        {'requestId': 'req_dup', 'visitorId': '', 'duplicate': true});

    expect(result.duplicate, isTrue);
    expect(result.visitorId, '');
    expect(result.visitorConfidence, isNull);
  });

  test('members of the wrong type read as missing instead of throwing', () {
    final result = IdentifyResult.fromJson({
      'requestId': 42,
      'visitorIsNew': 'yes',
      'visitorConfidence': '92',
      'suspectScore': 'high',
      'triggers': [
        'not-a-trigger',
        {'signal': 'simulator', 'group': 7},
      ],
      'report': {
        'schema': '1',
        'sources': {
          'device': {
            'status': 'ok',
            'ms': 2,
            'value': ['not', 'a', 'map']
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
    expect(result.visitorIsNew, isNull);
    expect(result.visitorConfidence, isNull);
    expect(result.suspectScore, isNull);
    expect(result.report.schema, 0);
    expect(result.report.sources.keys, ['device']);
    expect(result.report.sources['device']!.value, isNull);
    expect(result.report.integrity.patchedNatives, isEmpty);
    expect(result.report.integrity.lies.single.kind, 'swizzled');
  });

  test('an unreadable native answer is a FingerlyException', () async {
    for (final raw in ['not json', '[1, 2]', '"text"']) {
      messenger.setMockMethodCallHandler(_channel, (_) async => raw);
      final fingerly = await Fingerly.load(apiKey: 'fly_pk_development_mobile');

      await expectLater(
        fingerly.identify(),
        throwsA(isA<FingerlyException>()),
        reason: raw,
      );
      await expectLater(
        fingerly.collect(),
        throwsA(isA<FingerlyException>()),
        reason: raw,
      );
    }
  });
}
