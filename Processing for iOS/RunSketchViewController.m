//
//  RunSketchViewController.m
//  Processing for iOS
//
//  Created by Frederik Riedel on 27.06.15.
//  Copyright (c) 2015 Frederik Riedel. All rights reserved.
//

#import "RunSketchViewController.h"
#import "Processing_for_iOS-Swift.h"

// WKUserContentController retains its handlers; forwarding weakly avoids retaining
// the runner, WebKit process, and motion callbacks after leaving the sketch.
@interface SketchMessageHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic,weak) id<WKScriptMessageHandler> target;
@end
@implementation SketchMessageHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.target userContentController:controller didReceiveScriptMessage:message];
}
@end

@interface RunSketchViewController () <WKNavigationDelegate, UIGestureRecognizerDelegate>
@property(nonatomic,strong) NSURL *runtimeHTMLURL;
@property(nonatomic,strong) SketchProgram *program;
@property(nonatomic,strong) DetectedBug *pendingBug;
@property(nonatomic,strong) NSTimer *watchdog;
@property(nonatomic,assign) NSTimeInterval lastRuntimeActivity;
@property(nonatomic,assign) BOOL started;
@property(nonatomic,assign) BOOL failed;
@property(nonatomic,assign) BOOL previousInteractivePopGestureEnabled;
@property(nonatomic,assign) BOOL previousInteractiveContentPopGestureEnabled;
@property(nonatomic,weak) id<UIGestureRecognizerDelegate> previousInteractivePopGestureDelegate;
@end

@implementation RunSketchViewController

-(id)initWithSimpleTextProject:(SimpleTextProject*)project {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.project = project;
        self.title = project.name;
    }
    return self;
}

- (void)startSketch {
    self.started = YES;
    self.view.backgroundColor = UIColor.blackColor;
    NSError *error = nil;
    self.program = [self.project prepareRuntimeAndReturnError:&error];
    if (!self.program) {
        [self reportError:error.localizedDescription ?: @"Cannot read this project."];
        return;
    }
    if (self.program.preflightBug) {
        [self reportBug:self.program.preflightBug];
        return;
    }

    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    configuration.allowsInlineMediaPlayback = YES;
    // The bundled p5.sound runtime and local data loaders use file-origin requests.
    [configuration.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    SketchMessageHandler *handler = [SketchMessageHandler new];
    handler.target = self;
    [configuration.userContentController addScriptMessageHandler:handler name:@"iosbridge"];
    [configuration.userContentController addScriptMessageHandler:handler name:@"error"];
    self.sketchWebView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.sketchWebView.navigationDelegate = self;
    self.sketchWebView.backgroundColor = UIColor.clearColor;
    self.sketchWebView.opaque = NO;
    self.sketchWebView.scrollView.scrollEnabled = NO;
    self.sketchWebView.scrollView.bounces = NO;
    [self.view addSubview:self.sketchWebView];

    NSURL *projectURL = self.project.folder;
    NSURL *dataURL = [projectURL URLByAppendingPathComponent:@"data" isDirectory:YES];
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtURL:dataURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self reportError:[NSString stringWithFormat:@"Cannot prepare the sketch data folder. %@", error.localizedDescription]];
        return;
    }
    NSString *runtimeName = [NSString stringWithFormat:@"__runtime_%@.html", NSUUID.UUID.UUIDString];
    self.runtimeHTMLURL = [projectURL URLByAppendingPathComponent:runtimeName];
    if (![self.program.htmlPage writeToURL:self.runtimeHTMLURL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self reportError:[NSString stringWithFormat:@"Cannot prepare the sketch. %@", error.localizedDescription]];
        return;
    }
    self.lastRuntimeActivity = NSProcessInfo.processInfo.systemUptime;
    __weak typeof(self) weakSelf = self;
    self.watchdog = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { [timer invalidate]; return; }
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
            self.lastRuntimeActivity = now;
        } else if (now - self.lastRuntimeActivity > 10) {
            [self reportError:@"The sketch stopped responding for 10 seconds. Check for an infinite loop or a long-running operation, then run it again."];
        }
    }];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resetWatchdog) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self.sketchWebView loadFileURL:self.runtimeHTMLURL allowingReadAccessToURL:projectURL];
}

- (void)resetWatchdog {
    self.lastRuntimeActivity = NSProcessInfo.processInfo.systemUptime;
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (self.failed || !message.frameInfo.isMainFrame) return;
    if ([message.name isEqualToString:@"error"]) {
        DetectedBug *bug = [self.program bugFromMessage:message.body];
        if (bug) [self reportBug:bug];
    } else if ([message.name isEqualToString:@"iosbridge"] && [message.body isKindOfClass:NSDictionary.class]) {
        id event = message.body[@"event"];
        if ([event isEqual:@"heartbeat"] || [event isEqual:@"ready"]) {
            [self resetWatchdog];
            if ([event isEqual:@"ready"] && !self.motionManager && [self.project.sourceCodeExtension isEqualToString:@"pde"]) {
                [self startMotionListeners];
            }
        }
    }
}

- (void)reportError:(NSString *)message {
    [self reportBug:[CodeErrorDetectionEngine bugFromString:message]];
}

- (void)reportBug:(DetectedBug *)bug {
    if (self.failed || !bug) return;
    self.failed = YES;
    self.pendingBug = bug;
    [self stopRuntime];
    [self presentPendingBug];
}

- (void)presentPendingBug {
    if (!self.pendingBug || !self.view.window || self.presentedViewController) return;
    DetectedBug *bug = self.pendingBug;
    self.pendingBug = nil;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sketch Error" message:bug.displayMessage preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy Error" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = bug.displayMessage;
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];
    NSString *actionTitle = bug.hasSourceLocation ? @"Show in Code" : @"Back to Code";
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (bug.hasSourceLocation) [self.delegate didDetectBug:bug];
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startMotionListeners {
    self.motionManager = [CMMotionManager new];
    __weak typeof(self) weakSelf = self;
    if (self.motionManager.accelerometerAvailable) {
        self.motionManager.accelerometerUpdateInterval = 0.02;
        [self.motionManager startAccelerometerUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMAccelerometerData *data, NSError *error) {
            if (data && !error) [weakSelf sendMotion:@"accelerometerUpdated" x:data.acceleration.x y:data.acceleration.y z:data.acceleration.z];
        }];
    }
    if (self.motionManager.gyroAvailable) {
        self.motionManager.gyroUpdateInterval = 0.02;
        [self.motionManager startGyroUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMGyroData *data, NSError *error) {
            if (data && !error) [weakSelf sendMotion:@"gyroscopeUpdated" x:data.rotationRate.x y:data.rotationRate.y z:data.rotationRate.z];
        }];
    }
}

- (void)sendMotion:(NSString *)callback x:(double)x y:(double)y z:(double)z {
    if (self.failed) return;
    NSString *script = [NSString stringWithFormat:@"SketchRuntime.motion('%@', %f, %f, %f)", callback, x, y, z];
    __weak typeof(self) weakSelf = self;
    [self.sketchWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error.code == WKErrorJavaScriptExceptionOccurred) {
            [weakSelf reportError:error.userInfo[@"WKJavaScriptExceptionMessage"] ?: error.localizedDescription];
        }
    }];
}

- (void)stopRuntime {
    [self.watchdog invalidate];
    self.watchdog = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [self.motionManager stopGyroUpdates];
    [self.motionManager stopAccelerometerUpdates];
    self.motionManager = nil;
    [self.sketchWebView.configuration.userContentController removeScriptMessageHandlerForName:@"error"];
    [self.sketchWebView.configuration.userContentController removeScriptMessageHandlerForName:@"iosbridge"];
    self.sketchWebView.navigationDelegate = nil;
    [self.sketchWebView stopLoading];
    [self.sketchWebView removeFromSuperview];
    self.sketchWebView = nil;
    if (self.runtimeHTMLURL) {
        [NSFileManager.defaultManager removeItemAtURL:self.runtimeHTMLURL error:nil];
        self.runtimeHTMLURL = nil;
    }
}

- (void)dealloc {
    [self stopRuntime];
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

    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isMovingFromParentViewController || self.isBeingDismissed ||
        ![self.navigationController.viewControllers containsObject:self]) {
        [self stopRuntime];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) [self reportError:error.localizedDescription];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) [self reportError:error.localizedDescription];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self reportError:@"The sketch runtime stopped unexpectedly. The sketch may have used too much memory. Return to the code and try again."];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:YES animated:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.started) [self startSketch];
    [self presentPendingBug];
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
