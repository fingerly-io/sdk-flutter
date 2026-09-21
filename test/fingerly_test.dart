import 'dart:convert';

import 'package:fingerly_flutter/fingerly.dart';
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
      'triggers': [
        {
          'signal': 'simulator',
          'group': 'environment',
          'weight': 16,
          'confidence': 'high',
          'reason': 'simulator-hardware',
        },
      ],
      'verdicts': {
        'simulator': {
          'value': true,
          'confidence': 'high',
          'reasons': ['simulator-hardware'],
        },
      },
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
      'consent': 'granted',
    });
  });

  group('consent', () {
    /// A native side that keeps its own consent, as `FingerlyBridge` does, and
    /// refuses `identify` and `collect` with `consent_required` until it is
    /// granted. `withDetails` imitates the iOS plugin, which sends the state in
    /// `details`; the Android plugin sends a code and a message only.
    List<MethodCall> installGatedNative({bool withDetails = true}) {
      final calls = <MethodCall>[];
      var consent = 'granted';

      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        final arguments = (call.arguments as Map?)?.cast<String, Object?>();

        switch (call.method) {
          case 'configure':
            consent = arguments?['consent'] as String? ?? 'granted';
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

    test('defaults to granted and identifies as before', () async {
      final calls = installGatedNative();

      final client = await Fingerly.load(apiKey: 'fly_pk_development_mobile');
      final result = await client.identify();

      expect(calls.first.arguments['consent'], 'granted');
      expect(client.consent, ConsentState.granted);
      expect(result.requestId, 'req_123');
    });

    for (final state in [ConsentState.pending, ConsentState.denied]) {
      test('passes ${state.name} through to configure and refuses with it',
          () async {
        final calls = installGatedNative();

        final client =
            await Fingerly.load(apiKey: 'fly_pk_development_mobile', consent: state);

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
      expect(call.arguments, {'tag': 'checkout', 'submit': true});
      return jsonEncode(_identifyResult());
    });

    final client = await Fingerly.load(apiKey: 'fly_pk_development_mobile');
    final result = await client.identify(tag: 'checkout');

    expect(result.requestId, 'req_123');
    expect(result.visitorId, 'visitor_123');
    expect(result.suspectScore, 16);
    expect(result.triggers.single.signal, 'simulator');
    expect(result.verdicts.simulator.value, isTrue);
    expect(result.verdicts.simulator.confidence, Confidence.high);
    expect(result.verdicts.jailbreak, same(Verdict.unknown));
    expect(result.report.sources['device']?.status, SignalStatus.ok);
    expect(result.report.sources['attest']?.reason, 'simulator');
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

    final client = await Fingerly.load(apiKey: 'fly_pk_development_mobile');
    final report = await client.collect();

    expect(report.schema, 1);
    expect(report.elapsedMs, 42);
    expect(await Fingerly.nativeVersion(), '0.1.0');
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
    final verdict = Verdict.fromJson({
      'value': true,
      'confidence': 'new-confidence',
      'reasons': <String>[],
    });

    expect(outcome.status, SignalStatus.error);
    expect(verdict.confidence, Confidence.low);
  });
}
