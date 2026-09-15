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
        apiKey: 'pk_test_mobile', endpoint: 'http://localhost:9000');

    expect(received?.method, 'configure');
    expect(received?.arguments, {
      'apiKey': 'pk_test_mobile',
      'endpoint': 'http://localhost:9000',
      'platform': 'flutter-ios',
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

    final client = await Fingerly.load(apiKey: 'pk_test_mobile');
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

    final client = await Fingerly.load(apiKey: 'pk_test_mobile');
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
      Fingerly.load(apiKey: 'pk_test_mobile'),
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
