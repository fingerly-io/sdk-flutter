# Fingerly for Flutter

Flutter bindings for Fingerly (`0.3.0`, `v: 3`). A binding to the native iOS and
Android SDKs, which do the collecting.

```yaml
dependencies:
  fingerly_flutter: ^0.3.0
```

Requires Flutter **3.10** or newer, iOS **13** or newer, and Android **5.0 (API
21)** or newer.

## Identify

```dart
import 'package:fingerly_flutter/fingerly_flutter.dart';

final fingerly = await Fingerly.load(
  apiKey: 'fly_pk_production_…',
  consent: ConsentState.granted, // only once you have consent (or another lawful basis)
);
final result = await fingerly.identify(tag: 'checkout');

// Send result.requestId to your backend and make the decision there.
```

The key is a **publishable** SDK key from the dashboard, and it is safe in a
shipped binary — it is scoped to the app identifiers and (on production Android
keys) the signing certificate SHA-256 digests (`AllowedAndroidSigners`) you
list. A **secret** key is refused when it arrives from a client.

`identify()` collects and submits a single-pass `v: 3` identification (`1-RTT`
steady-state via cached `next_attestation` challenge offers). It resolves with
what the server said: `requestId`, `visitorId` and, by default, `suspectScore`
and `suspectLevel`, so there is no second call to make.

Under **Option B** (`v: 3`), when `identifiable` is `false`, `visitorId` is `""`
and `visitorIsNew` is `false` — the server never mints a synthetic visitor ID
when device signals are insufficient. `visitorConfidence` can be `null` when
omitted.

The score is a convenience for showing a result straight away. Each SDK key has
a setting that hides it from apps, and then both `suspectScore` and
`suspectLevel` are `null`, exactly as on a check nobody scored: an app cannot
tell which it was, so read `null` as "no answer here", never as clean. The
signals behind a score never reach the device; read them on your backend,
through the server-side event read by `requestId` or webhooks, or in the
dashboard. Send `requestId` and `visitorId` to your own backend with the request
they belong to, and let your backend decide: **the score in your hand came from
a device you do not control**, and an app that branches on it locally is an app
whose branch can be patched out.

Call `collect()` to inspect the raw client `SignalReport` locally without
sending anything to the server.

Pass `automatic: true` for a call your app makes on its own rather than in
answer to the user: on start, on a timer, on returning to the foreground. It
joins an identification already in flight instead of starting another, and
waits out a transient failure instead of repeating it at once.

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

While the state is anything but `granted`, the native SDK runs no source, reads
and writes no container file or attestation key state, and sends nothing.
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

Every submission the native SDK sends carries `"consent": "granted"`, and the
server refuses any other value with `422 consent_required`. The native SDK only
sends while consent is granted, so that refusal should never be seen.

## Erasure (GDPR / privacy right to erasure only)

```dart
await Fingerly.deleteStoredIdentity();
```

**Strictly for user-initiated GDPR / privacy erasure and account deletion.**
Atomically deletes both the local `install_id` record and local hardware
attestation key state (`Application Support/io.fingerly.sdk/` container storage
with `isExcludedFromBackup = true` and App Attest key state on iOS; the
`install_id` record and persistent `AndroidKeyStore` v3 EC P-256 signing key
`io.fingerly.sdk.attest.v3` on Android). Do **not** call it during routine
sign-out or session rotation, as unnecessary resets force hardware key
re-attestation and repeated `install_id` churn (`>= 3` distinct IDs on a
hardware key within 24 hours triggers `tampering` churn detection). It needs no
`load` and no consent, sends nothing over the network, and completes once no
local identity or key state remains, including when there was none. It throws a
`FingerlyException` when the delete fails. The next identification made with
consent starts an unlinked record; to stop identifying as well, set consent to
`ConsentState.denied` first.

## This package collects nothing

That is the design, not a limitation.

Every signal worth having on a phone is unreachable from Dart: `lstat` on
`/var/jb`, the dyld image list, the thread names Frida's runtime leaves behind,
the `P_TRACED` flag, Secure Enclave App Attest and TEE Keystore signing, the TLS
chain the app was actually served. A method channel can reach none of them.

So a plugin that collected what it *could* reach from Dart would report a
jailbroken, instrumented device as clean — which is worse than reporting
nothing, because a customer would believe it.

This package calls the native SDK and hands back what it produced. The collection
logic lives in one place per platform, in Swift and in Kotlin, and improving it
improves Flutter, React Native, Lynx and native apps at the same time rather
than four times over. What the signals mean is decided on the server.

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
again. It is null when the response named no wait.

A call refused for want of consent throws `FingerlyConsentException`, a
subclass of `FingerlyException` with `code` `consent_required`, a `state`, and
no `status`. Catch it before `FingerlyException`, and answer it with
`setConsent` rather than a retry. See [Consent](#consent).

Everything parses defensively: a missing field produces a missing value rather
than an exception. A fraud SDK that throws during a checkout has done more
damage than the fraud it was looking for.

## Native SDKs (`0.3.0`)

Both platforms are implemented and compiled. The **iOS** plugin calls
[`mobile/ios`](../ios) (`0.3.0`, 15 native sources + `FingerlyPtrAuth` + App
Attest) and the **Android** plugin calls [`mobile/android`](../android)
(`io.fingerly:fingerly:0.3.0`, 20 native sources + persistent 24h TEE Keystore
signing); each forwards to that SDK's `FingerlyBridge` and hops the result back
to the platform thread.

On iOS, the Flutter Swift package resolves `0.3.0` from
`https://github.com/fingerly-io/sdk-ios`. With CocoaPods, `pod install` downloads
the same `Fingerly.xcframework` (`0.3.0`) from `https://maven.fingerly.io/ios/`
and verifies its pinned SHA-256 checksum, so nothing depends on CocoaPods Trunk.

On Android, the plugin depends on `io.fingerly:fingerly:0.3.0` from
`https://maven.fingerly.io`, which it adds to the Gradle build itself.

**Installed-app checks are opt-in on Android (`io.fingerly:fingerly-app-checks:0.3.0`).**
Core `io.fingerly:fingerly:0.3.0` declares zero `<queries>` entries in its
manifest because Google Play treats installed-app visibility as personal and
sensitive data. If your app justifies package visibility for the 17 root
managers, hooking frameworks and dual-space cloners in Play review, add
`io.fingerly:fingerly-app-checks:0.3.0` to your Android app module and declare
"App activity: Installed apps" on the Data safety form. The plugin finds the
artifact and registers its provider on every `Fingerly.load`, so there is no
native code to write:

```groovy
// android/app/build.gradle
dependencies {
    implementation 'io.fingerly:fingerly-app-checks:0.3.0'
}
```

Without it, the report carries no installed-app fields and nothing about other
apps leaves the device; whether the app itself runs inside a cloner is still
reported.

**Play Integrity (Android, optional: `io.fingerly:fingerly-play-integrity:0.3.0`).**
To add Google Play Integrity Standard tokens bound to the `v: 3`
`statementDigest` (ADR 0026), add `io.fingerly:fingerly-play-integrity:0.3.0` to
your Android app module and pass your Google Cloud project number (the one
linked in Play Console) to `Fingerly.load`. The plugin finds the artifact and
registers its provider with that project number:

```groovy
// android/app/build.gradle
dependencies {
    implementation 'io.fingerly:fingerly-play-integrity:0.3.0'
}
```

```dart
final fingerly = await Fingerly.load(
  apiKey: 'fly_pk_production_…',
  consent: ConsentState.granted,
  playIntegrityCloudProjectNumber: 123456789012,
);
```

A provider of your own, registered from native code with
`FingerlyBridge.setPlayIntegrity(provider)` before `Fingerly.load`, is used in
place of the artifact's. On Android, a project number with neither is a
configuration error:
`Fingerly.load` throws a `FingerlyException` (platform code
`play_integrity_unavailable`, "playIntegrityCloudProjectNumber was set but the
io.fingerly:fingerly-play-integrity artifact is not on the classpath") and
leaves the previous configuration in place. Without a project number, Play
Integrity is off and nothing fails. On iOS the project number is ignored.

To work against a local native build instead: for iOS, run
`scripts/build-xcframework.sh` in the iOS checkout and set
`FINGERLY_XCFRAMEWORK_PATH` to `build/Fingerly.xcframework` (or
`build/Fingerly-0.3.0.xcframework.zip`), or unzip it into this package's
`ios/Frameworks` directory. For Android, publish the native artifacts to your
local Maven repository, which the plugin checks before Fingerly's repository:

```sh
cd ../android && ./gradlew publishToMavenLocal
```

This plugin is licensed under Apache-2.0. The native SDKs it depends on are
closed binaries under the Fingerly SDK License.
