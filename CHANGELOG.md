# Changelog

## 0.4.3

- `Signal` names `aiSpoofed` (`ai_spoofed`, a client that names a known AI
  agent but fails its operator's check), `identityObfuscated`
  (`identity_obfuscated`, an opt-in strict identity-randomisation mode in a
  browser) and `bootloaderUnlocked` (`bootloader_unlocked`, an Android device
  whose bootloader is unlocked), and no longer has `vpnTimezone`, because the
  server no longer reports `vpn_timezone`. The native SDKs stay iOS `0.4.1`
  and Android `0.4.0`. Nothing collected or sent changes.

## 0.4.2

- Fixes minified Android release builds: R8 stopped with "Missing class
  io.fingerly.sdk.appchecks.FingerlyAppChecks" in any app that does not add
  the optional `io.fingerly:fingerly-app-checks` and
  `io.fingerly:fingerly-play-integrity` artifacts. The plugin now ships
  consumer ProGuard rules for them, as the React Native bridge does. Nothing
  collected or sent changes.

## 0.4.1

- Update the native iOS dependency (`sdk-ios` / `Fingerly.xcframework`) to
  `0.4.1`, which fixes a crash on every `identify()` in iOS apps built for
  release. The Android dependency stays `0.4.0`. Nothing collected or sent
  changes.
- The documentation of `ConsentState.granted` says when to set it: once
  collection is permitted for the user, because they consented or the law
  that applies does not require consent. A GDPR lawful basis alone is not
  enough. Behaviour is unchanged.

## 0.4.0

- Named constants for the fixed values the API returns, the same names the
  other Fingerly SDKs use: `SuspectLevel`, `Confidence`, `EventState` and
  `Signal`, each a class of `static const String` members in lowerCamelCase
  (`SuspectLevel.high`, `Signal.fingerprintSuppressed`) with a `values` list.
  `IdentifyResult.suspectLevel`, `IdentifyResult.state` and
  `IdentifyTrigger.signal`, `group` and `confidence` stay `String`, so a
  comparison with the plain string still works and a value a newer server adds
  arrives unchanged. `ConsentState` stays an enum.
- `Signal` lists all 73 signal groups and detectors the server reports,
  including `repeatedReinstall`, `deviceActivityHigh` and
  `deviceActivityVeryHigh`.
- **Breaking:** the `RiskSignal` enum and `IdentifyTrigger.riskSignal` are
  removed. Compare `IdentifyTrigger.signal` with a `Signal` member instead, for
  example `trigger.signal == Signal.attestationFailed`. The enum was behind the
  server and still named the retired `app_attest_key_churn`.
- Update native iOS (`sdk-ios` / `Fingerly.xcframework`) and Android
  (`io.fingerly:fingerly`) dependencies to `0.4.0`. Nothing collected or sent
  changes.

## 0.3.0

- Update native iOS (`sdk-ios` / `Fingerly.xcframework`) and Android
  (`io.fingerly:fingerly`) dependencies to `0.3.0` on the unified `v: 3` wire
  contract and `schema: 2` telemetry report, with local `mavenLocal()` and
  `FINGERLY_XCFRAMEWORK_PATH` artifact resolution support.
- Align `IdentifyResult` with `v: 3` Option B (`visitorId` is `""` when
  `identifiable == false`, `visitorIsNew` is `false` when `visitorId.isEmpty`,
  non-nullable `identifiable` and `duplicate` booleans, nullable `suspectScore` /
  `suspectLevel`, and optional `triggers`), add `FingerlyConfig` /
  `Fingerly.configure` and the `RiskSignal` / `IdentifyTrigger` types, and
  retire `identify(submit: false)` in favour of `collect()`.
- Forward `automatic` and `Retry-After` on Android as well as iOS, and clarify
  that `Fingerly.deleteStoredIdentity()` is strictly for user-initiated GDPR /
  privacy erasure (atomically wiping local `install_id` and hardware attestation
  key state).
- The podspec pins the Apple team next to the XCFramework checksum. The
  install keeps a download only when the XCFramework and every slice carry a
  valid signature under an Apple-issued certificate naming that team, and
  keeps an existing framework only when its stamp names the pinned checksum and
  team and its signature still verifies. An empty or malformed pin fails the
  install.
- Registers the app-checks and Play Integrity providers when their Android
  artifacts are linked, keeps one registered by hand, and fails `configure`
  when a Play Integrity project number has no provider.
- `RiskSignal` lists `attestation_downgrade`, `probe_errors` and
  `fetch_metadata_missing`, with `report_incomplete` and
  `fingerprint_suppressed` among the cross-platform signals.

## 0.2.0

- Android: the installed-app checks (root managers, hooking frameworks, app
  cloners) move to the opt-in `io.fingerly:fingerly-app-checks` artifact from
  the Android SDK release after 0.1.0; add it to your app's Android module at
  the same version as `io.fingerly:fingerly` if you want them. See the README.
- Android: `Fingerly.load(playIntegrityCloudProjectNumber: …)` enables Play
  Integrity when the app also adds the optional
  `io.fingerly:fingerly-play-integrity` artifact; without it the number is
  ignored. Needs the native Android SDK release after 0.1.0. See the README.

## 0.1.0

- First release: `Fingerly.load`, `identify`, consent, and the iOS and Android
  bindings to the native SDKs.
