#!/usr/bin/env bash
#
# Decides whether the version in pubspec.yaml still has to be released. Prints
# new=true or new=false, and appends the same plus version=X.Y.Z to
# $GITHUB_OUTPUT when run in a workflow. A lookup that cannot answer fails the
# script, because an outage must never read as "not published yet".
#
# Usage: release-check.sh [package version]
# The arguments exist so the logic can be tried on a package already on pub.dev;
# the workflow passes none.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

package="${1:-fingerly_flutter}"
version="${2:-$(sed -n 's/^version: *//p' pubspec.yaml)}"
pub="${PUB_HOSTED_URL:-https://pub.dev}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || {
  echo "error: '$version' is not a release version" >&2
  exit 1
}

finish() {
  echo "$2"
  echo "new=$1"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    { echo "new=$1"; echo "version=$version"; } >> "$GITHUB_OUTPUT"
  fi
  exit 0
}

# The tag comes first: this workflow creates it before publishing, so it also
# stops a re-run while publish.yml is still working.
rc=0
git ls-remote --exit-code --tags origin "refs/tags/v$version" > /dev/null || rc=$?
case "$rc" in
  0) finish false "tag v$version exists" ;;
  2) ;;
  *) echo "error: git ls-remote failed with status $rc" >&2; exit 1 ;;
esac

url="$pub/api/packages/$package/versions/$version"
status="$(curl --silent --show-error --location --max-time 30 --retry 3 --retry-all-errors \
  --output /dev/null --write-out '%{http_code}' "$url")"
case "$status" in
  200) finish false "$package $version is on pub.dev" ;;
  404) finish true "$package $version is not on pub.dev" ;;
  *) echo "error: $url answered HTTP $status" >&2; exit 1 ;;
esac
