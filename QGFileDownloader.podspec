#
# Be sure to run `pod lib lint QGFileDownloader.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'QGFileDownloader'
  s.version          = '0.1.2'
  s.summary          = 'A short description of QGFileDownloader.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/Quanhua-Guan/QGFileDownloader'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { '官泉华' => 'xinmuheart@163.com' }
  s.source           = { :git => 'https://github.com/Quanhua-Guan/QGFileDownloader.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'

  s.source_files = 'QGFileDownloader/Classes/**/*'
  
  # s.resource_bundles = {
  #   'QGFileDownloader' => ['QGFileDownloader/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  s.dependency 'AFNetworking', '~> 4.0'
end
