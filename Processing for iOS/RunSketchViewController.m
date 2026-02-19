//
//  RunSketchViewController.m
//  Processing for iOS
//
//  Created by Frederik Riedel on 27.06.15.
//  Copyright (c) 2015 Frederik Riedel. All rights reserved.
//

#import "RunSketchViewController.h"
#import "Processing_for_iOS-Swift.h"

@interface RunSketchViewController () <WKNavigationDelegate, UIGestureRecognizerDelegate>
@property(nonatomic,strong) NSURL *runtimeHTMLURL;
@property(nonatomic,assign) BOOL previousInteractivePopGestureEnabled;
@property(nonatomic,assign) BOOL previousInteractiveContentPopGestureEnabled;
@property(nonatomic,weak) id<UIGestureRecognizerDelegate> previousInteractivePopGestureDelegate;
@end

@implementation RunSketchViewController

-(id)initWithSimpleTextProject:(SimpleTextProject*)project {
    self = [super initWithNibName:nil bundle:nil];
    
    if(self) {
        
        self.project = project;
        self.title = self.project.name;
        
        WKWebViewConfiguration* configuration = [WKWebViewConfiguration new];
        WKUserContentController* contentController = [WKUserContentController new];
        configuration.userContentController = contentController;
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        configuration.allowsInlineMediaPlayback = YES;
        [configuration.userContentController addScriptMessageHandler:self name: @"iosbridge"];
        [configuration.userContentController addScriptMessageHandler:self name: @"error"];
        [[configuration preferences] setValue: [NSNumber numberWithBool:YES] forKey:@"allowFileAccessFromFileURLs"];
        
        self.sketchWebView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) configuration:configuration];
        self.sketchWebView.navigationDelegate = self;

        
        [self.view addSubview:self.sketchWebView];
        
        self.view.backgroundColor = [UIColor blackColor];
        
        self.sketchWebView.backgroundColor=[UIColor clearColor];
        self.sketchWebView.opaque=NO;
        
        self.sketchWebView.scrollView.scrollEnabled = NO;
        self.sketchWebView.scrollView.bounces = NO;
        
        
        NSString* content = [[self project] htmlPage];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *projectURL = self.project.folder;
        NSURL *dataURL = [projectURL URLByAppendingPathComponent:@"data"];
        if (![fileManager fileExistsAtPath:dataURL.path]) {
            [fileManager createDirectoryAtURL:dataURL withIntermediateDirectories:YES attributes:nil error:nil];
        }

        self.runtimeHTMLURL = [projectURL URLByAppendingPathComponent:@"__runtime_preview__.html"];
        NSError *writeError = nil;
        BOOL didWriteFile = [content writeToURL:self.runtimeHTMLURL atomically:YES encoding:NSUTF8StringEncoding error:&writeError];

        if (didWriteFile) {
            [self.sketchWebView loadFileURL:self.runtimeHTMLURL allowingReadAccessToURL:projectURL];
        } else {
            NSLog(@"Failed to write runtime HTML: %@", writeError.localizedDescription);
            [self.sketchWebView loadHTMLString:content baseURL:projectURL];
        }
        
        self.motionManager = [CMMotionManager new];

        if ([project.sourceCodeExtension isEqualToString:@"pde"]) {
            [self startAccelerometerListener];
            [self startGyroscopeListener];
        }
        
        
//        UIBarButtonItem* startARSession = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arkit"] style:UIBarButtonItemStylePlain target:self action:@selector(startARSession)];
        
        
        
        UIBarButtonItem *moreButton;
        if (@available(iOS 13.0, *)) {
            moreButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(showRunOptions:)];
        } else {
            moreButton = [[UIBarButtonItem alloc] initWithTitle:@"•••"
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(showRunOptions:)];
        }
        [[self navigationItem] setRightBarButtonItems:@[moreButton]];
    }

    return self;
}

-(void)startARSession {
    
}

-(void) addToHomeScreen {
    SelectAppIconViewController *addToHomeVC = [[SelectAppIconViewController alloc] init];
    addToHomeVC.project = self.project;
    UINavigationController * navC = [[UINavigationController alloc] initWithRootViewController:addToHomeVC];
    navC.modalPresentationStyle = UIModalPresentationFormSheet;
    [self.navigationController presentViewController:navC animated:YES completion:nil];
}

-(void)showRunOptions:(UIBarButtonItem *)sender {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *addToHome = [UIAlertAction actionWithTitle:NSLocalizedString(@"Add to Homescreen…", @"")
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(__unused UIAlertAction * _Nonnull action) {
        [self addToHomeScreen];
    }];

    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"")
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil];

    [menu addAction:addToHome];
    [menu addAction:cancel];

    UIPopoverPresentationController *popover = menu.popoverPresentationController;
    if (popover) {
        popover.barButtonItem = sender;
    }

    [self presentViewController:menu animated:YES completion:nil];
}
    
    
-(void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    
    if ([message.name isEqualToString:@"error"]) {
        NSString* errorMessage = message.body[@"message"];
        
        DetectedBug* bug = [CodeErrorDetectionEngine bugFromString:errorMessage];
        
        if (bug) {
            
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Faulty Code Detected" message:@"Cannot run your project because there‘s a problem with your code. Processing can help you to figure out which part of your code is faulty." preferredStyle: UIAlertControllerStyleAlert];
            
            UIAlertAction* cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                
            }];
            
            UIAlertAction* subscribe = [UIAlertAction actionWithTitle:@"Show Bug in Code" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self.delegate didDetectBug:bug];
                [[self navigationController] popViewControllerAnimated:true];
            }];
            
            [alert addAction:cancel];
            [alert addAction:subscribe];
            
            [[self navigationController] presentViewController:alert animated:YES completion:nil];
        } else {
            NSLog(@"unknown error: %@", message.body);
        }
    } else {
        NSLog(@"didReceiveScriptMessage: %@", message.body);
    }
}
    
    
-(void) startAccelerometerListener {
    if([self.motionManager isAccelerometerAvailable]) {
        [self.motionManager setAccelerometerUpdateInterval:0.02];
        
        [self.motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
                                                 withHandler:^(CMAccelerometerData * _Nullable accelerometerData, NSError * _Nullable error) {
                                                     
                                                     [self.sketchWebView evaluateJavaScript:[NSString stringWithFormat:@"var pjs = Processing.getInstanceById('Sketch');"
                                                                                             "pjs.accelerometerUpdated(%f,%f,%f);", accelerometerData.acceleration.x, accelerometerData.acceleration.y, accelerometerData.acceleration.z] completionHandler:^(id _Nullable result, NSError * _Nullable error) {

                                                         if ([error.description containsString:@"pjs.accelerometerUpdated"]) {
                                                             [self.motionManager stopAccelerometerUpdates];
                                                         }
                                                         
                                                         NSLog(@"%@, %@",result, error.description);


                                                     }];

                                                     
                                                 }];
    } else {
         NSLog(@"Accelerometer not Available!");
    }
}

-(void) startGyroscopeListener {
    //Gyroscope
    if([self.motionManager isGyroAvailable])
    {
        
            
            [self.motionManager setGyroUpdateInterval:0.02];
            
            /* Add on a handler block object */
            
            /* Receive the gyroscope data on this block */
            [self.motionManager startGyroUpdatesToQueue:[NSOperationQueue mainQueue]
                                            withHandler:^(CMGyroData *gyroData, NSError *error)
             {

                 [self.sketchWebView evaluateJavaScript:[NSString stringWithFormat:@"var pjs = Processing.getInstanceById('Sketch');"
                                                         "pjs.gyroscopeUpdated(%f,%f,%f);", gyroData.rotationRate.x, gyroData.rotationRate.y, gyroData.rotationRate.z] completionHandler:^(id _Nullable result, NSError * _Nullable error) {
                     
                     
                     if ([error.description containsString:@"pjs.gyroscopeUpdated"]) {
                         [self.motionManager stopGyroUpdates];
                     }
                     NSLog(@"%@, %@",result, error.description);
                     
                 }];
             }];
    }
    else
    {
        NSLog(@"Gyroscope not Available!");
    }
}



-(void)viewWillLayoutSubviews {
    self.sketchWebView.frame=CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
}

-(void)viewWillDisappear:(BOOL)animated {
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.delegate = self.previousInteractivePopGestureDelegate;
        self.navigationController.interactivePopGestureRecognizer.enabled = self.previousInteractivePopGestureEnabled;
    }
    if (@available(iOS 26.0, *)) {
        if (self.navigationController.interactiveContentPopGestureRecognizer) {
            self.navigationController.interactiveContentPopGestureRecognizer.enabled = self.previousInteractiveContentPopGestureEnabled;
        }
    }

    if (self.runtimeHTMLURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.runtimeHTMLURL error:nil];
        self.runtimeHTMLURL = nil;
    }
    self.sketchWebView = nil;
    [self.motionManager stopGyroUpdates];
    [self.motionManager stopAccelerometerUpdates];
    self.motionManager = nil;
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"WebView provisional navigation failed: %@", error.localizedDescription);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"WebView navigation failed: %@", error.localizedDescription);
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:YES animated:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.previousInteractivePopGestureDelegate = self.navigationController.interactivePopGestureRecognizer.delegate;
        self.previousInteractivePopGestureEnabled = self.navigationController.interactivePopGestureRecognizer.enabled;
        self.navigationController.interactivePopGestureRecognizer.delegate = self;
        self.navigationController.interactivePopGestureRecognizer.enabled = NO;
    }
    if (@available(iOS 26.0, *)) {
        if (self.navigationController.interactiveContentPopGestureRecognizer) {
            self.previousInteractiveContentPopGestureEnabled = self.navigationController.interactiveContentPopGestureRecognizer.enabled;
            self.navigationController.interactiveContentPopGestureRecognizer.enabled = NO;
        }
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        return NO;
    }
    return YES;
}

-(void) close {
    
    [self.navigationController popViewControllerAnimated:YES];
}

-(NSArray<UIKeyCommand *> *)keyCommands {
    
    UIKeyCommand* close = [UIKeyCommand keyCommandWithInput:@"w" modifierFlags:UIKeyModifierCommand action:@selector(close) discoverabilityTitle:@"Close Sketch"];
    UIKeyCommand *esc = [UIKeyCommand keyCommandWithInput: UIKeyInputEscape modifierFlags: 0 action: @selector(close) discoverabilityTitle:@"Close Sketch"];
    
    return @[close, esc];
}

-(BOOL)canBecomeFirstResponder {
    return YES;
}


@end
