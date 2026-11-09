#!/usr/bin/env bash
#
# Fails when a copy of a version disagrees with its source. pubspec.yaml owns the
# package version. The native SDK versions are separate, because a binding can
# release without a native change; the iOS copies must still agree with each other.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0

fail() {
  echo "error: $*" >&2
  status=1
}

same() {
  [ "$2" = "$3" ] || fail "$1 is '$2', expected '$3'"
}

version="$(sed -n 's/^version: *//p' pubspec.yaml)"
[ -n "$version" ] || { echo "error: no version in pubspec.yaml" >&2; exit 1; }

podspec=ios/fingerly_flutter.podspec
same "$podspec s.version" "$(sed -n "s/.*s\.version *= *'\(.*\)'.*/\1/p" "$podspec")" "$version"
same "android/build.gradle version" "$(sed -n "s/^version '\(.*\)'.*/\1/p" android/build.gradle)" "$version"
grep -qF "fingerly_flutter: ^$version" README.md || fail "README.md does not install ^$version"
grep -qF "## $version" CHANGELOG.md || fail "CHANGELOG.md has no entry for $version"

native_ios="$(sed -n "s/.*native_version *= *'\(.*\)'.*/\1/p" "$podspec")"
spm_ios="$(sed -n 's/.*sdk-ios", exact: "\(.*\)").*/\1/p' ios/fingerly_flutter/Package.swift)"
same "Package.swift native iOS version" "$spm_ios" "$native_ios"

sha="$(sed -n "s/.*native_sha256 *= *'\(.*\)'.*/\1/p" "$podspec")"
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "$podspec native_sha256 is not a SHA-256: publish the iOS binary and pin it"

native_android="$(sed -n "s/.*'io\.fingerly:fingerly:\(.*\)'.*/\1/p" android/build.gradle)"
grep -qF "io.fingerly:fingerly:$native_android" README.md || fail "README.md does not name Android SDK $native_android"

[ "$status" -eq 0 ] && echo "version $version, native iOS $native_ios, native Android $native_android"
exit "$status"
