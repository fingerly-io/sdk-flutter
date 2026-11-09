# Fingerly for Flutter

Flutter bindings for Fingerly. A binding to the native iOS and Android SDKs, which
do the collecting.

```yaml
dependencies:
  fingerly_flutter: ^0.1.0
```

Requires Flutter **3.10** or newer, iOS **13** or newer.

## Identify

```dart
import 'package:fingerly_flutter/fingerly.dart';

final fingerly = await Fingerly.load(
  apiKey: 'fly_pk_production_…',
  consent: ConsentState.granted, // only once you have consent (or another lawful basis)
);
final result = await fingerly.identify(tag: 'checkout');

if (result.verdicts.jailbreak.value &&
    result.verdicts.jailbreak.confidence == Confidence.high) {
  // step up to a challenge, hold for review, add friction
}
```

The key is a **publishable** SDK key from the dashboard, and it is safe in a
shipped binary — it is scoped to the app identifiers you list. A **secret** key
is refused when it arrives from a client.

`identify()` collects, scores on the device, and submits. It resolves with the
server's verdict — `visitorId`, `suspectScore`, `suspectLevel` and the triggers
behind them — so there is no second call to make. Send the `requestId` and
`visitorId` to your own backend with the request they belong to, and let your
backend decide: **the score in your hand came from a device you do not
control**, and an app that branches on it locally is an app whose branch can be
patched out.

Pass `submit: false` to collect and score without sending anything.

Pass `automatic: true` for a call your app makes on its own rather than in
answer to the user: on start, on a timer, on returning to the foreground. It
joins an identification already in flight instead of starting another, and
waits out a transient failure instead of repeating it at once. On Android it
has no effect until the native Android SDK supports it.

## Consent

The SDK identifies nobody until it is told consent is `granted`. The usual
pattern is to load it at launch with the default, `ConsentState.pending`, and
pass on the answer from your consent tool when it arrives:

```dart
final fingerly = await Fingerly.load(apiKey: 'fly_pk_production_…'); // pending

// From your consent tool's callback:
await fingerly.setConsent(
  accepted ? ConsentState.granted : ConsentState.denied,
);

fingerly.consent; // granted, pending or denied
```

| Option / method | What it does |
| --- | --- |
| `consent:` on `Fingerly.load` | The starting state: `ConsentState.pending` (the default), `granted` or `denied`. |
| `setConsent(state)` | Records the decision. Safe to call repeatedly. |
| `consent` | The state last given to the native SDK, read-only. |

The default is `pending`, so an integration that never mentions consent
identifies nobody. Pass `consent: ConsentState.granted` to `load` only when you
already have consent, or another lawful basis.

`setConsent` changes `consent` straight away, and the native SDK receives
changes in the order they were made, so an `identify()` started after it sees
the new state even if the returned future was not awaited. Await it to hear
about a failure.

While the state is anything but `granted`, the native SDK runs no source, reads and
writes no keychain entry or preference for fingerprinting, and sends nothing.
`identify()` and `collect()` throw `FingerlyConsentException`, whose `code` is
`consent_required` and whose `state` says which state refused the call:

```dart
try {
  await fingerly.identify();
} on FingerlyConsentException catch (error) {
  // error.state is pending or denied; nothing was collected or sent
}
```

A change applies to calls already in flight as well as later ones. Consent
withdrawn halfway through an `identify()` stops it before the next source
starts and before anything is submitted, and that call throws
`FingerlyConsentException`.

Loading collects and sends nothing, whatever the state, so calling
`Fingerly.load` at launch before the user has been asked is safe. The native SDK
holds one state for the whole app: each `load` sets it to the `consent` passed,
or `pending` when there is none, so pass `consent` on every `load`.

Every submission the native SDK sends carries the state it was collected under,
`"consent": "granted"`, and the server refuses any other value with
`422 consent_required`. The native SDK only sends while consent is granted, so
that refusal should never be seen.

## Erasure

```dart
await Fingerly.deleteStoredIdentity();
```

Deletes the install record the native SDK keeps on the device, including the
install ID the server recognises it by. Call it when a user asks for their data
to be erased or deletes their account. It needs no `load` and no consent, and
sends nothing, and completes once no record remains, including when there was
none. It throws a `FingerlyException` when the delete fails. The next
identification made with consent starts a new record; to stop identifying as
well, set consent to `ConsentState.denied` first.

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
final report = await fingerly.collect();   // no submission

report.sources.forEach((id, outcome) {
  debugPrint('$id ${outcome.status.name} ${outcome.ms}ms ${outcome.reason ?? ''}');
});
```

Five statuses, never a hole: `ok`, `unsupported`, `blocked`, `timeout`, `error`.
A `blocked` jailbreak probe is stronger evidence than any value it could have
returned, because `lstat` on a path does not fail unless something made it.

## Errors

`identify()` throws `FingerlyException`, whose `status` is the HTTP status where
there was one:

```dart
try {
  await fingerly.identify();
} on FingerlyException catch (error) {
  if (error.status == 401) { /* the key is wrong */ }
  if (error.status == 402) { /* the organisation is not accepting traffic */ }
}
```

Both are your configuration rather than the user's behaviour, and neither is
worth retrying. The native SDK retries the ones that are (429 and 5xx) with
full-jitter backoff before it ever throws.

When the server asked for a pause with `Retry-After`, the exception carries it
as `retryAfter`, a `Duration`. Wait at least that long before identifying
again. It is null when the response named no wait, and on Android until the
native Android bridge passes the header on.

A call refused for want of consent throws `FingerlyConsentException`, a
subclass of `FingerlyException` with `code` `consent_required`, a `state`, and
no `status`. Catch it before `FingerlyException`, and answer it with
`setConsent` rather than a retry. See [Consent](#consent).

Everything parses defensively: a missing field produces a missing value rather
than an exception. A fraud SDK that throws during a checkout has done more
damage than the fraud it was looking for.

## Status

Both platforms are implemented and compiled. The **iOS** plugin calls
[`mobile/ios`](../ios) and the **Android** plugin calls
[`mobile/android`](../android); each is a method-channel handler that forwards
to that SDK's `FingerlyBridge` and hops the result back to the platform thread.

The Dart contract has bridge, decoding and error-shape tests. The iOS bridge is
verified through both CocoaPods and Swift Package Manager, and has run on an
iPhone 16e simulator: all 21 native sources collected in 142ms and
`simulator=true`. The Android bridge builds into a debug APK and has run on an
API 36 Pixel 8 emulator: all 22 native sources completed, `emulator=true`, with
a 1095ms cold collection and a 122ms warm collection.

The native SDKs are not published yet. For a CocoaPods development build, run
`scripts/build-xcframework.sh` in the iOS checkout, unzip
`build/Fingerly-0.1.0.xcframework.zip` beside `Fingerly.podspec`, and point the
host application's Podfile at that checkout:

```ruby
pod 'Fingerly', :path => '/path/to/sdks/mobile/ios'
```

The Flutter Swift package currently resolves the private iOS repository's
authenticated `main` branch. Before public release, publish the native SDK's
binary Swift package and point that dependency at it.

The Android plugin depends on `io.fingerly:fingerly:0.1.0` from Fingerly's Maven
repository, `https://maven.fingerly.io`, which the plugin adds to the build
itself, so no host-project repository override is required. That repository is
not live yet. Until it is, and for contributors at any time, build the SDK's AAR
into your local Maven repository:

```
cd ../android && ./gradlew :fingerly:publishToMavenLocal
```

The plugin checks Maven Local before Fingerly's repository.

This plugin is licensed under Apache-2.0. The native SDK it depends on is a
closed binary under the Fingerly SDK License.
