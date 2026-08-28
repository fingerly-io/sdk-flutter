# badele

Flutter bindings for Badele. A binding to the native iOS and Android SDKs, which
do the collecting.

```yaml
dependencies:
  badele: ^0.1.0
```

Requires Flutter **3.10** or newer, iOS **13** or newer.

## Identify

```dart
import 'package:badele/badele.dart';

final badele = await Badele.load(apiKey: 'pk_live_…');
final result = await badele.identify(tag: 'checkout');

if (result.verdicts.jailbreak.value &&
    result.verdicts.jailbreak.confidence == Confidence.high) {
  // step up to a challenge, hold for review, add friction
}
```

The key is a **publishable** SDK key from the dashboard, and it is safe in a
shipped binary — it is scoped to the app identifiers you list. A **secret** key
is refused when it arrives from a client.

`identify()` collects, scores on the device, and submits. It returns as soon as
the server has a receipt — IP geolocation and the velocity windows are computed
after the response — so what comes back is a `requestId` rather than a finished
event. Send it to your own backend with the request it belongs to, and let your
backend fetch the finished event and decide.

Pass `submit: false` to collect and score without sending anything.

## This package collects nothing

That is the design, not a limitation.

Every signal worth having on a phone is unreachable from Dart: `lstat` on
`/var/jb`, the dyld image list, the thread names Frida's runtime leaves behind,
the `P_TRACED` flag, the DeviceCheck token Apple's Secure Enclave signs, the TLS
chain the app was actually served. A method channel can reach none of them.

So a plugin that collected what it *could* reach from Dart would report a
jailbroken, instrumented device as clean — which is worse than reporting
nothing, because a customer would believe it.

This package calls the native SDK and hands back what it produced. The detection
logic lives in one place per platform, in Swift and in Kotlin, and improving it
improves Flutter, React Native and native apps at the same time rather than
three times over.

## The verdicts

```dart
class Verdicts {
  final Verdict instrumentation;  // Frida, Substrate, Substitute, ElleKit
  final Verdict mitm;             // something intercepting the app's TLS
  final Verdict automation;       // a debugger or a UI-test runner
  final Verdict tampering;        // hooked functions, injected images
  final Verdict farm;             // mass-provisioned or reset-fresh

  final Verdict jailbreak;        // iOS
  final Verdict simulator;        // iOS
  final Verdict root;             // Android
  final Verdict emulator;         // Android
  final Verdict appCloner;        // Android
}
```

One class covering both platforms, with the platform-specific members answering
`Verdict.unknown` where they do not apply. Two classes and a union would be more
honest about the difference and would make every call site branch on the
platform to read a field — the wrong trade for a cross-platform binding, where
the point is writing the check once.

The distinction is not lost: `jailbreak` on Android comes back with
`value: false` **and** an empty `reasons` list, which is what `Verdict.unknown`
means. A caller that needs to tell "we looked and found nothing" from "this
platform cannot be asked" reads `reasons.isEmpty`.

Each verdict carries why, strongest first:

```dart
if (result.verdicts.instrumentation.value) {
  debugPrint(result.verdicts.instrumentation.reasons.join(', '));
  // → instrumentation-image-libhooker.dylib, instrumentation-thread-gum-js-loop
}
```

These are advice. The same rules run again on the server, over the stored
report, where they can improve without every customer shipping an app update.
**The decision belongs on your server.**

## The platform string

This package reports `flutter-ios` or `flutter-android`, never the bare
`flutter`. The server maps an SDK platform onto one of three scoring profiles by
looking for `ios` or `android` in the string, and a submission that names
neither falls through to the **browser** profile — where `jailbreak` and
`simulator` are not signals at all and everything the native SDK collected is
worth zero.

Nothing fails when that goes wrong: the submission succeeds, the event is
stored, the report looks full, and the signal never fires.

## Reading the report

```dart
final report = await badele.collect();   // no submission

report.sources.forEach((id, outcome) {
  debugPrint('$id ${outcome.status.name} ${outcome.ms}ms ${outcome.reason ?? ''}');
});
```

Five statuses, never a hole: `ok`, `unsupported`, `blocked`, `timeout`, `error`.
A `blocked` jailbreak probe is stronger evidence than any value it could have
returned, because `lstat` on a path does not fail unless something made it.

## Errors

`identify()` throws `BadeleException`, whose `status` is the HTTP status where
there was one:

```dart
try {
  await badele.identify();
} on BadeleException catch (error) {
  if (error.status == 401) { /* the key is wrong */ }
  if (error.status == 402) { /* the organisation is not accepting traffic */ }
}
```

Both are your configuration rather than the user's behaviour, and neither is
worth retrying. The native SDK retries the ones that are (429 and 5xx) with
full-jitter backoff before it ever throws.

Everything parses defensively: a missing field produces a missing value rather
than an exception. A fraud SDK that throws during a checkout has done more
damage than the fraud it was looking for.

## Status

Both platforms are implemented. The **iOS** plugin calls
[`mobile/ios`](../ios) and the **Android** plugin calls
[`mobile/android`](../android); each is a method-channel handler that forwards
to that SDK's `BadeleBridge` and hops the result back to the platform thread.

Neither has been compiled here — there is no Flutter toolchain on the machine
this was written on, and a plugin needs `Flutter.framework` and
`flutter_embedding` on the compile path. What they call is compiled and tested
by each native SDK's own suite.

The Android plugin depends on `io.badele:badele:0.1.0`, which is not published
yet. Until it is, build the SDK's AAR into your local Maven repository:

```
cd ../android && ./gradlew :badele:publishToMavenLocal
```

and add `mavenLocal()` to the host app's repositories.
