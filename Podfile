# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'Processing for iOS' do
  use_frameworks!
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  # use_frameworks!
  pod 'Tabman', '~> 1.0'
  pod 'SwiftyStoreKit'
  pod 'Swifter', '~> 1.5.0'
  pod "NSString+LevenshteinDistance"

  # Pods for Processing for iOS

  target 'Processing for iOSTests' do
    inherit! :search_paths
    # Pods for testing
  end
  
end


#post_install do |installer|
#  installer.pods_project.targets.each do |target|
#    if target.name == "Pods-Processing for iOS"
#      puts "Updating #{target.name} to exclude Crashlytics/Fabric/Firebase"
#      target.build_configurations.each do |config|
#        xcconfig_path = config.base_configuration_reference.real_path
#        xcconfig = File.read(xcconfig_path)
#        xcconfig.sub!('-framework "FirebaseAnalytics"', '')
#        xcconfig.sub!('-framework "FIRAnalyticsConnector"', '')
#        xcconfig.sub!('-framework "GoogleMobileAds"', '')
#        xcconfig.sub!('-framework "Google-Mobile-Ads-SDK"', '')
#        xcconfig.sub!('-framework "GoogleAppMeasurement"', '')
#        xcconfig.sub!('-framework "Fabric"', '')
#        new_xcconfig = xcconfig + 'OTHER_LDFLAGS[sdk=iphone*] = -framework "Crashlytics" -framework "Fabric"'
#        File.open(xcconfig_path, "w") { |file| file << new_xcconfig }
#      end
#    end
#  end
#end
