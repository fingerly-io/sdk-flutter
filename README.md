<p align="center">
  <a href="https://fingerly.io">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/fingerly-io/.github/main/assets/logo-dark.svg">
      <img src="https://raw.githubusercontent.com/fingerly-io/.github/main/assets/logo-light.svg" alt="Fingerly" height="44">
    </picture>
  </a>
</p>

<p align="center"><b>Fingerly for Flutter</b><br>Device intelligence and fraud signals in your Flutter app, through a typed Dart API over the native iOS and Android SDKs.</p>

<p align="center">
  <a href="https://pub.dev/packages/fingerly_flutter"><img src="https://img.shields.io/pub/v/fingerly_flutter?style=flat-square" alt="pub.dev version"></a>
  <a href="https://github.com/fingerly-io/sdk-flutter/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square" alt="Licence: Apache-2.0"></a>
  <img src="https://img.shields.io/badge/flutter-%E2%89%A53.10-blue?style=flat-square" alt="Flutter 3.10 or newer">
  <a href="https://docs.fingerly.io/docs/sdks/flutter"><img src="https://img.shields.io/badge/docs-docs.fingerly.io-informational?style=flat-square" alt="Documentation"></a>
</p>

<p align="center"><img src="https://raw.githubusercontent.com/fingerly-io/.github/main/assets/banner.webp" alt="Fingerly" width="100%"></p>

## What is this

`fingerly_flutter` is the Flutter binding to the Fingerly native iOS and Android SDKs, which do the collecting. You call `identify()` from Dart and get back a request ID and a visitor ID to send to your own backend, which decides what to do. [Fingerly](https://fingerly.io) is a device intelligence API that helps you protect signups, logins and payments from fraud and abuse.

## Getting started

1. **Get a key.** In the [Fingerly dashboard](https://dashboard.fingerly.io), open **Integration > SDK keys** and create a public key for your app. [How keys work](https://docs.fingerly.io/docs/api-keys).
2. **Install the package.**

   ```yaml
   dependencies:
     fingerly_flutter: ^0.2.0
   ```

3. **Identify.**

   ```dart
   import 'package:fingerly_flutter/fingerly_flutter.dart';

   final fingerly = await Fingerly.load(
     apiKey: 'fly_pk_production_…',
     consent: ConsentState.granted, // only once you have consent (or another lawful basis)
   );
   final result = await fingerly.identify(tag: 'checkout');

   // Send result.requestId to your backend and make the decision there.
   ```

Requires Flutter **3.10** or newer, iOS **13** or newer.

## Contents

- [Identify](#identify)
- [Consent](#consent)
- [Erasure](#erasure)
- [Errors](#errors)
- [Reading the report](#reading-the-report)
- [Native SDKs](#native-sdks)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Documentation](#documentation)
- [Help](#help)
- [Licence](#licence)

## Identify

The key is a **publishable** SDK key from the dashboard, and it is safe in a shipped binary: it is scoped to the app identifiers you list. A **secret** key is refused when it arrives from a client.

`identify()` collects and submits. It resolves with what the server said: `requestId`, `visitorId` and, by default, `suspectScore` and `suspectLevel`, so there is no second call to make.

- The score is a convenience for showing a result straight away. Each SDK key has a setting that hides it from apps, and then both fields are `null`, exactly as on a check nobody scored. An app cannot tell which it was, so read `null` as "no answer here", never as clean.
- The signals behind a score never reach the device. Read them on your backend, through the server-side event read by `requestId` or webhooks, or in the dashboard.
- `visitorConfidence`, `visitorIsNew`, `identifiable` and `duplicate` can be `null` when the server did not say, which is not the same as `0` or `false`.
- Send the `requestId` and `visitorId` to your own backend with the request they belong to, and let your backend decide: **the score in your hand came from a device you do not control**, and an app that branches on it locally is an app whose branch can be patched out.

| Option | What it does |
| --- | --- |
| `tag` | A string echoed back on the finished event, for your own correlation. |
| `submit: false` | Collect without sending anything. Only `report` is filled in then: the server's fields stay empty and `suspectScore` stays null. |
| `automatic: true` | For a call your app makes on its own rather than in answer to the user: on start, on a timer, on returning to the foreground. It joins an identification already in flight instead of starting another, and waits out a transient failure instead of repeating it at once. On Android the plugin accepts the option and ignores it. |

`Fingerly.nativeVersion()` returns the version of the native SDK that did the collecting.

## Consent

The SDK identifies nobody until it is told consent is `granted`. The usual pattern is to load it at launch with the default, `ConsentState.pending`, and pass on the answer from your consent tool when it arrives:

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

The default is `pending`, so an integration that never mentions consent identifies nobody. Pass `consent: ConsentState.granted` to `load` only when you already have consent, or another lawful basis.

`setConsent` changes `consent` straight away, and the native SDK receives changes in the order they were made, so an `identify()` started after it sees the new state even if the returned future was not awaited. Await it to hear about a failure.

While the state is anything but `granted`, the native SDK runs no source, reads and writes no keychain entry or preference for fingerprinting, and sends nothing. `identify()` and `collect()` throw `FingerlyConsentException`, whose `code` is `consent_required` and whose `state` says which state refused the call:

```dart
try {
  await fingerly.identify();
} on FingerlyConsentException catch (error) {
  // error.state is pending or denied; nothing was collected or sent
}
```

A change applies to calls already in flight as well as later ones. Consent withdrawn halfway through an `identify()` stops it before the next source starts and before anything is submitted, and that call throws `FingerlyConsentException`.

Loading collects and sends nothing, whatever the state, so calling `Fingerly.load` at launch before the user has been asked is safe. The native SDK holds one state for the whole app: each `load` sets it to the `consent` passed, or `pending` when there is none, so pass `consent` on every `load`.

Every submission the native SDK sends carries the state it was collected under, `"consent": "granted"`, and the server refuses any other value with `422 consent_required`. The native SDK only sends while consent is granted, so that refusal should never be seen.

## Erasure

```dart
await Fingerly.deleteStoredIdentity();
```

Deletes the install record the native SDK keeps on the device, including the install ID the server recognises it by. Call it when a user asks for their data to be erased or deletes their account. It needs no `load` and no consent, and sends nothing, and completes once no record remains, including when there was none. It throws a `FingerlyException` when the delete fails. The next identification made with consent starts a new record; to stop identifying as well, set consent to `ConsentState.denied` first.

## Errors

`identify()` throws `FingerlyException`, whose `status` is the HTTP status where there was one:

```dart
try {
  await fingerly.identify();
} on FingerlyException catch (error) {
  if (error.status == 401) { /* the key is wrong */ }
  if (error.status == 402) { /* the organisation is not accepting traffic */ }
}
```

Both are your configuration rather than the user's behaviour, and neither is worth retrying. The native SDK retries the ones that are (429 and 5xx) with full-jitter backoff before it ever throws.

When the server asked for a pause with `Retry-After`, the exception carries it as `retryAfter`, a `Duration`. Wait at least that long before identifying again. It is null when the response named no wait.

A call refused for want of consent throws `FingerlyConsentException`, a subclass of `FingerlyException` with `code` `consent_required`, a `state`, and no `status`. Catch it before `FingerlyException`, and answer it with `setConsent` rather than a retry. See [Consent](#consent).

Everything parses defensively: a missing field produces a missing value rather than an exception. A fraud SDK that throws during a checkout has done more damage than the fraud it was looking for.

## Reading the report

```dart
final report = await fingerly.collect();   // no submission

report.sources.forEach((id, outcome) {
  debugPrint('$id ${outcome.status.name} ${outcome.ms}ms ${outcome.reason ?? ''}');
});
```

Five statuses, never a hole: `ok`, `unsupported`, `blocked`, `timeout`, `error`. A `blocked` outcome is information in its own right, not a missing value.

## Native SDKs

The iOS plugin calls the [iOS SDK](https://github.com/fingerly-io/sdk-ios) and the Android plugin calls the Android SDK (`io.fingerly:fingerly`). Each is a method-channel handler that forwards to that SDK's `FingerlyBridge` and hops the result back to the platform thread.

<details>
<summary><b>iOS</b></summary>

The Flutter Swift package resolves the native SDK from `https://github.com/fingerly-io/sdk-ios`. With CocoaPods, `pod install` downloads the same framework from `https://maven.fingerly.io/ios/` and checks it against a pinned SHA-256, so nothing depends on the CocoaPods trunk. Both need network access on the first build only.

The Play Integrity project number passed to `load` is ignored on iOS.

</details>

<details>
<summary><b>Android</b></summary>

The plugin depends on `io.fingerly:fingerly:0.2.0` from Fingerly's Maven repository, `https://maven.fingerly.io`, and adds that repository to the build itself, so no host-project repository override is required.

**Installed-app checks are opt-in.** The checks for root managers, hooking frameworks and app cloners by package name ship in a separate artifact, `io.fingerly:fingerly-app-checks`, because Google Play treats the list of installed apps as personal and sensitive data. This plugin depends on `io.fingerly:fingerly` only. If your app can justify the package visibility in its Play review and wants these checks, add the artifact to your app's Android module, at the same version as `io.fingerly:fingerly`, and declare "App activity: Installed apps" in the Data safety form:

```groovy
dependencies {
    implementation 'io.fingerly:fingerly-app-checks:<same version as io.fingerly:fingerly>'
}
```

Without it, the report carries no installed-app fields and nothing about other apps leaves the device; whether the app itself runs inside a cloner is still reported.

**Play Integrity (optional).** The Android SDK has an optional artifact, `io.fingerly:fingerly-play-integrity`, that adds Google Play Integrity verdicts to events. To use it, add the artifact to the app and pass your Google Cloud project number, the one linked to the app in Play Console, to `load`:

```groovy
// android/app/build.gradle
dependencies {
    implementation 'io.fingerly:fingerly-play-integrity:<same version as io.fingerly:fingerly>'
}
```

```dart
final fingerly = await Fingerly.load(
  apiKey: 'fly_pk_production_…',
  playIntegrityCloudProjectNumber: 123456789012,
);
```

The native SDK finds the artifact on its own; this plugin does not depend on it. Without the artifact the number is ignored and nothing fails. The rest of the setup, the service account uploaded to your Fingerly project and the daily budget, is covered by the Android SDK's [install notes](https://github.com/fingerly-io/sdk-android/blob/main/INSTALL.md#optional-play-integrity). Gradle refuses to pair the artifact with a core of another version.

</details>

<details>
<summary><b>Working against a local native build</b></summary>

For iOS, run `scripts/build-xcframework.sh` in the iOS checkout and unzip `build/Fingerly-0.2.0.xcframework.zip` into this package's `ios/Frameworks` directory. For Android, build the SDK's AAR into your local Maven repository, which the plugin checks before Fingerly's repository:

```sh
cd ../android && ./gradlew :fingerly:publishToMavenLocal
```

</details>

## How it works

This package collects nothing, by design. Almost everything worth collecting on a phone is out of reach of Dart, so a plugin that collected only what Dart can reach would report a compromised device as clean. That is worse than reporting nothing, because a customer would believe it.

The package calls the native SDK and hands back what it produced. The collection logic lives in one place per platform, in Swift and in Kotlin, so improving it improves Flutter, React Native and native apps at the same time rather than three times over. What the signals mean is decided on the server.

**The platform string.** This package reports `flutter-ios` or `flutter-android`, never the bare `flutter`. The server relies on the platform string to apply the mobile checks. Nothing fails when it is wrong: the submission succeeds, the event is stored and the report looks full, but the mobile checks do not apply.

<details>
<summary><b>Where it has run</b></summary>

Both platforms are implemented and compiled. The Dart contract has bridge, decoding and error-shape tests. The iOS bridge is verified through both CocoaPods and Swift Package Manager, and has run on an iPhone 16e simulator, collecting in 142ms. The Android bridge builds into a debug APK and has run on an API 36 Pixel 8 emulator, with a 1095ms cold collection and a 122ms warm collection.

</details>

## Requirements

| | Minimum |
| --- | --- |
| Flutter | 3.10 |
| Dart | 3.0 |
| iOS | 13 |
| Android | 5.0 (API 21) |

## Documentation

Guides and the API reference: <https://docs.fingerly.io/docs/sdks/flutter>.

## Help

Open an issue on this repository, or write to <support@fingerly.io>. Security issues: <security@fingerly.io>.

## Licence

This plugin is licensed under [Apache-2.0](https://github.com/fingerly-io/sdk-flutter/blob/main/LICENSE). The native SDK it depends on is a closed binary under the Fingerly SDK License.
