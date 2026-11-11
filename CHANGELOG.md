# Changelog

## Unreleased

- Android: `Fingerly.load(playIntegrityCloudProjectNumber: …)` enables Play
  Integrity when the app also adds the optional
  `io.fingerly:fingerly-play-integrity` artifact; without it the number is
  ignored. Needs the native Android SDK release after 0.1.0. See the README.

## 0.1.0

- First release: `Fingerly.load`, `identify`, consent, and the iOS and Android
  bindings to the native SDKs.
