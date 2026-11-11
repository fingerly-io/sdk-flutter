# Changelog

## Unreleased

- Android: the installed-app checks (root managers, hooking frameworks, app
  cloners) move to the opt-in `io.fingerly:fingerly-app-checks` artifact from
  the Android SDK release after 0.1.0; add it to your app's Android module at
  the same version as `io.fingerly:fingerly` if you want them. See the README.

## 0.1.0

- First release: `Fingerly.load`, `identify`, consent, and the iOS and Android
  bindings to the native SDKs.
