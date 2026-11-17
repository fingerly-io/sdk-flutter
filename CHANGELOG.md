# Changelog

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
