platform :ios, '15.0'

target 'Processing for iOS' do
  use_frameworks!
  pod 'Tabman', '~> 3.2'
  pod "NSString+LevenshteinDistance"

  # Pods for Processing for iOS

  target 'Processing for iOSTests' do
    inherit! :search_paths
    # Pods for testing
  end
  
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
