//
//  RunSketchViewController.h
//  Processing for iOS
//
//  Created by Frederik Riedel on 27.06.15.
//  Copyright (c) 2015 Frederik Riedel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PDEFile.h"
#import "PDESketch.h"

@class DetectedBug;


@protocol RunSketchViewControllerDelegate <NSObject>

-(void)didDetectBug: (DetectedBug*)bug;

@end

@import CoreMotion;
@import WebKit;

@interface RunSketchViewController : UIViewController<UIWebViewDelegate, WKScriptMessageHandler>
    
    @property(nonatomic,strong) PDESketch *pdeSketch;
    @property(nonatomic,strong) WKWebView *sketchWebView;
    
    @property (nonatomic,strong) CMMotionManager* motionManager;

    @property (nonatomic, weak) id<RunSketchViewControllerDelegate> delegate;
    
    
-(id)initWithPDEFile:(PDESketch*)pdeSketch;

@end
