platform :ios, '12.0'

target 'Processing for iOS' do
  use_frameworks!
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  # use_frameworks!
  pod 'Tabman', '~> 1.0'
  pod 'Swifter', '~> 1.5.0'
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
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
    end
  end
end
