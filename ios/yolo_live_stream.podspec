#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint yolo_live_stream.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'yolo_live_stream'
  s.version          = '0.0.1'
  s.summary          = 'WebRTC 영상 송수신 + YOLO 객체 탐지 Flutter 플러그인'
  s.description      = <<-DESC
같은 Wi-Fi의 두 기기를 WebRTC로 연결해 영상을 주고받고, 수신 영상에 YOLO 객체 탐지를 얹는다.
                       DESC
  s.homepage         = 'https://yourstar.space'
  s.license          = { :type => 'AGPL-3.0', :file => '../LICENSE' }
  s.author           = { 'yolo_live_stream' => 'yolo_live_stream' }
  s.source           = { :path => '.' }
  s.source_files = 'yolo_live_stream/Sources/yolo_live_stream/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'yolo_live_stream_privacy' => ['yolo_live_stream/Sources/yolo_live_stream/PrivacyInfo.xcprivacy']}
end
