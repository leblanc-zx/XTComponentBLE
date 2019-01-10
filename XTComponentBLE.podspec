#
# Be sure to run `pod lib lint XTComponentBLE.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'XTComponentBLE'
  s.version          = '1.0.1'
  s.summary          = 'XTComponentBLE.描述'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!11

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/leblanc-zx/XTComponentBLE'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'leblanc-zx' => '351706354@qq.com' }
  s.source           = { :git => 'https://github.com/leblanc-zx/XTComponentBLE.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'

#s.source_files = 'XTComponentBLE/*.{h,m}'
  # 配置子目录
  s.subspec 'Models' do |models|
  models.source_files = 'XTComponentBLE/Models/*'
  end

  s.subspec 'BLE4' do |ble4|
  ble4.source_files = 'XTComponentBLE/BLE4.0/*'
  ble4.dependency 'XTComponentBLE/Models'
  end
  
  # s.resource_bundles = {
  #   'XTComponentBLE' => ['XTComponentBLE/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 3.0'
end
