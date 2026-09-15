#
# The CocoaPods spec Flutter's plugin tooling picks up.
#
# It depends on the native SDK rather than vendoring a copy of it. That is the
# whole architecture in one line: `mobile/ios` is the implementation, and this
# package is a binding to it, so a fix to a jailbreak check reaches Flutter apps
# by bumping one dependency rather than by porting the fix a second time.
#
Pod::Spec.new do |s|
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
  # The SDK. Everything this plugin does is call into it.
  s.dependency 'Fingerly'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
