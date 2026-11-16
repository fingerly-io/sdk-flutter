#
# The CocoaPods spec Flutter's plugin tooling picks up.
#
# `mobile/ios` is the implementation and this package is a binding to it, so a
# fix to a jailbreak check reaches Flutter apps by bumping one version rather
# than by porting the fix a second time.
#
# The binary is fetched when the pod is installed instead of being a `Fingerly`
# pod dependency, because that would need the CocoaPods trunk, which takes no new
# podspecs after 2026-12-02. It is not in the pub.dev package either: it is a
# closed binary under its own licence, while this package is Apache-2.0.
#
Pod::Spec.new do |s|
  # Change these together with the `exact:` version in fingerly_flutter/Package.swift.
  # The checksum is the one in that release's Swift package manifest, and the
  # pin is what makes a changed file on the download host an install failure.
  # The team is the Apple team that must have signed the framework, a copy of
  # the pin in the iOS SDK's scripts/signing-team.sh.
  native_version = '0.3.0'
  native_sha256  = 'c1d582eae15243fb63e3e55e68909490060f2b8232624b1025bb931c3100b4cc'
  native_team_id = 'XGXX88HRR5'
  native_url     = "https://maven.fingerly.io/ios/Fingerly-#{native_version}.xcframework.zip"

  # This must differ from the native `Fingerly` pod by more than letter case.
  # CocoaPods target and framework names are case-insensitive on the default
  # macOS filesystem; naming this pod `fingerly` makes the native target depend on
  # itself and prevents every Flutter iOS application from compiling.
  s.name             = 'fingerly_flutter'
  s.version          = '0.3.0'
  s.summary          = 'Device intelligence and fraud signals for Flutter.'
  s.description      = <<~DESC
    The Flutter binding for the Fingerly fraud detection platform. Calls the
    native iOS SDK, which does the collecting.
  DESC

  # The package is Apache-2.0 licensed. Keep this as SPDX metadata rather than
  # pointing outside `ios/`: Flutter publishes the plugin pod from that
  # directory, where a repository-relative licence path is not guaranteed to
  # be part of CocoaPods' sandbox.
  s.license          = 'Apache-2.0'
  s.author           = { 'Fingerly' => 'support@fingerly.io' }
  s.homepage         = 'https://fingerly.io'
  s.source           = { :path => '.' }

  # CocoaPods and SwiftPM compile the same source tree. Two copies of this
  # bridge would inevitably drift and a channel mismatch fails only at runtime.
  s.source_files     = 'fingerly_flutter/Sources/fingerly_flutter/**/*'

  # 13.0 matches the native SDK's floor. Raising it here would exclude apps the
  # SDK itself supports; lowering it would promise a platform the code does not
  # build for.
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'

  s.dependency 'Flutter'

  # The SDK. Everything this plugin does is call into it. CocoaPods runs this
  # for a path pod as well, from the pod's own directory, before it looks for
  # the framework. A download is installed only when it matches the pinned
  # checksum and is signed by the pinned Apple team. An existing framework is
  # kept only when its stamp names the pinned checksum and its signature still
  # verifies; anything else, including a framework without a stamp, is
  # replaced by a verified download. A local build is installed through
  # FINGERLY_XCFRAMEWORK_PATH, which writes no stamp, so a later install without
  # the variable replaces it.
  s.vendored_frameworks = 'Frameworks/Fingerly.xcframework'
  s.prepare_command = <<~CMD
    set -eu
    if [ -n "${FINGERLY_XCFRAMEWORK_PATH:-}" ]; then
      rm -rf Frameworks
      mkdir Frameworks
      if [ -d "$FINGERLY_XCFRAMEWORK_PATH" ]; then
        cp -R "$FINGERLY_XCFRAMEWORK_PATH" Frameworks/Fingerly.xcframework
      elif [ -f "$FINGERLY_XCFRAMEWORK_PATH" ]; then
        work="$(mktemp -d)"
        trap 'rm -rf "$work"' EXIT
        unzip -q "$FINGERLY_XCFRAMEWORK_PATH" -d "$work/sdk"
        mv "$work/sdk/Fingerly.xcframework" Frameworks/
        if [ -f "$work/sdk/LICENSE" ]; then mv "$work/sdk/LICENSE" Frameworks/; fi
      else
        echo "fingerly_flutter: FINGERLY_XCFRAMEWORK_PATH does not exist: $FINGERLY_XCFRAMEWORK_PATH" >&2
        exit 1
      fi
      exit 0
    fi
    if ! printf '%s' '#{native_sha256}' | grep -qE '^[0-9a-f]{64}$'; then
      echo 'fingerly_flutter: no valid checksum is pinned for the native iOS SDK' >&2
      exit 1
    fi
    team='#{native_team_id}'
    if ! printf '%s' "$team" | grep -qE '^[A-Z0-9]{10}$'; then
      echo 'fingerly_flutter: no valid Apple team identifier is pinned for the native iOS SDK' >&2
      exit 1
    fi
    # A valid signature under an Apple-issued certificate whose leaf names the
    # team, on the XCFramework and every slice, recording the same team.
    verify_signature() {
      requirement="anchor apple generic and certificate leaf[subject.OU] = \\"$team\\""
      for code in "$1" "$1"/*/Fingerly.framework; do
        [ -e "$code" ] || continue
        if ! codesign --verify --strict --deep -R="$requirement" "$code" >&2; then
          echo "fingerly_flutter: $code is not signed by Apple team $team" >&2
          return 1
        fi
        signer="$(codesign -dv "$code" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
        if [ "$signer" != "$team" ]; then
          echo "fingerly_flutter: $code records team ${signer:-none}, expected $team" >&2
          return 1
        fi
      done
    }
    if [ -d Frameworks/Fingerly.xcframework ] && [ -f Frameworks/.sha256 ] \
       && [ "$(cat Frameworks/.sha256)" = '#{native_sha256} #{native_team_id}' ] \
       && verify_signature Frameworks/Fingerly.xcframework 2>/dev/null; then
      exit 0
    fi
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    curl --fail --silent --show-error --location --proto '=https' --retry 3 \
      --connect-timeout 20 --output "$work/sdk.zip" '#{native_url}'
    actual="$(shasum -a 256 "$work/sdk.zip" | cut -d ' ' -f 1)"
    if [ "$actual" != '#{native_sha256}' ]; then
      echo "fingerly_flutter: checksum mismatch for the native iOS SDK: $actual" >&2
      exit 1
    fi
    unzip -q "$work/sdk.zip" -d "$work/sdk"
    if [ ! -d "$work/sdk/Fingerly.xcframework" ]; then
      echo 'fingerly_flutter: the native iOS SDK archive holds no Fingerly.xcframework' >&2
      exit 1
    fi
    verify_signature "$work/sdk/Fingerly.xcframework"
    rm -rf Frameworks
    mkdir Frameworks
    mv "$work/sdk/Fingerly.xcframework" Frameworks/
    if [ -f "$work/sdk/LICENSE" ]; then mv "$work/sdk/LICENSE" Frameworks/; fi
    echo '#{native_sha256} #{native_team_id}' > Frameworks/.sha256
  CMD

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
