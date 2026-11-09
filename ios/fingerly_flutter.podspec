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
  native_version = '0.1.0'
  native_sha256  = ''
  native_url     = "https://maven.fingerly.io/ios/Fingerly-#{native_version}.xcframework.zip"

  # This must differ from the native `Fingerly` pod by more than letter case.
  # CocoaPods target and framework names are case-insensitive on the default
  # macOS filesystem; naming this pod `fingerly` makes the native target depend on
  # itself and prevents every Flutter iOS application from compiling.
  s.name             = 'fingerly_flutter'
  s.version          = '0.1.0'
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
  # the framework. A framework with no stamp beside it was unpacked by hand from
  # a local build and is left alone.
  s.vendored_frameworks = 'Frameworks/Fingerly.xcframework'
  s.prepare_command = <<~CMD
    set -eu
    if [ -d Frameworks/Fingerly.xcframework ]; then
      if [ ! -f Frameworks/.sha256 ] || [ "$(cat Frameworks/.sha256)" = '#{native_sha256}' ]; then
        exit 0
      fi
    fi
    if [ -z '#{native_sha256}' ]; then
      echo 'fingerly_flutter: no checksum is pinned for the native iOS SDK' >&2
      exit 1
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
    rm -rf Frameworks
    mkdir Frameworks
    mv "$work/sdk/Fingerly.xcframework" Frameworks/
    if [ -f "$work/sdk/LICENSE" ]; then mv "$work/sdk/LICENSE" Frameworks/; fi
    echo '#{native_sha256}' > Frameworks/.sha256
  CMD

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
