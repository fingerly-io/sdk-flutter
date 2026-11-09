#!/usr/bin/env bash
#
# Downloads the iOS framework the podspec points at and compares it with the
# pinned checksum. Without this, a wrong pin would only surface in a customer's
# `pod install`, after the version is on pub.dev for good.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

podspec=ios/fingerly_flutter.podspec
version="$(sed -n "s/.*native_version *= *'\(.*\)'.*/\1/p" "$podspec")"
wanted="$(sed -n "s/.*native_sha256 *= *'\(.*\)'.*/\1/p" "$podspec")"
base="${FINGERLY_IOS_BASE_URL:-https://maven.fingerly.io/ios}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl --fail --silent --show-error --location --max-time 300 --retry 3 \
  --output "$work/sdk.zip" "$base/Fingerly-$version.xcframework.zip"

actual="$( (sha256sum "$work/sdk.zip" 2> /dev/null || shasum -a 256 "$work/sdk.zip") | cut -d ' ' -f 1)"
if [ "$actual" != "$wanted" ]; then
  echo "error: Fingerly-$version.xcframework.zip is $actual, the podspec pins '$wanted'" >&2
  exit 1
fi

echo "iOS binary $version matches the pinned checksum"
