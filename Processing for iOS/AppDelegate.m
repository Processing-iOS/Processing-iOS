//
//  AppDelegate.m
//  Processing for iOS
//
//  Created by Frederik Riedel on 27.06.15.
//  Copyright (c) 2015 Frederik Riedel. All rights reserved.
//

#import "AppDelegate.h"
#import "UIColor+ProcessingColor.h"
#import "SketchController.h"
#import "Processing_for_iOS-Swift.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [[UINavigationBar appearanceWhenContainedInInstancesOfClasses: @[ProcessingNavigationViewController.class]] setTintColor: [UIColor whiteColor]];
    
    [[UISegmentedControl appearance] setTintColor: [UIColor whiteColor]];
    [[UINavigationBar appearance] setBarTintColor: [UIColor processingColor]];
    
    
    [[UISearchBar appearance] setBarTintColor: [UIColor processingColor]];
    
    [[UINavigationBar appearance] setTranslucent:NO];
    [[UINavigationBar appearance] setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
    if (@available(iOS 11.0, *)) {
        [[UINavigationBar appearance] setLargeTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
        
    }
    
    
    
//    [ExternalScreenController start];
    
    
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance* appearance = [[UINavigationBarAppearance alloc] init];
        
        [appearance configureWithOpaqueBackground];
        [appearance setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
        [appearance setLargeTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
        [appearance setBackgroundColor: [UIColor processingColor]];
        
        [[UINavigationBar appearanceWhenContainedInInstancesOfClasses: @[UINavigationController.class] ] setStandardAppearance:appearance];
        [[UINavigationBar appearanceWhenContainedInInstancesOfClasses: @[UINavigationController.class] ] setScrollEdgeAppearance:appearance];
    }
    
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc]
        initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
    configuration.delegateClass = [SceneDelegate class];
    configuration.storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    return configuration;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"saveCode" object:nil];
}

@end
