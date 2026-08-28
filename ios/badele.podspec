#
# The CocoaPods spec Flutter's plugin tooling picks up.
#
# It depends on the native SDK rather than vendoring a copy of it. That is the
# whole architecture in one line: `mobile/ios` is the implementation, and this
# package is a binding to it, so a fix to a jailbreak check reaches Flutter apps
# by bumping one dependency rather than by porting the fix a second time.
#
Pod::Spec.new do |s|
  s.name             = 'badele'
  s.version          = '0.1.0'
  s.summary          = 'Device intelligence and fraud signals for Flutter.'
  s.description      = <<~DESC
    The Flutter binding for the Badele fraud detection platform. Calls the
    native iOS SDK, which does the collecting.
  DESC

  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Badele' => 'support@badele.io' }
  s.homepage         = 'https://badele.io'
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*'

  # 13.0 matches the native SDK's floor. Raising it here would exclude apps the
  # SDK itself supports; lowering it would promise a platform the code does not
  # build for.
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'

  s.dependency 'Flutter'
  # The SDK. Everything this plugin does is call into it.
  s.dependency 'Badele'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
