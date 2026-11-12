# Changelog

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
