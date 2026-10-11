//
//  RunSketchViewController.m
//  Processing for iOS
//
//  Created by Frederik Riedel on 27.06.15.
//  Copyright (c) 2015 Frederik Riedel. All rights reserved.
//

#import "RunSketchViewController.h"
#import "Processing_for_iOS-Swift.h"
#import <AVFoundation/AVFoundation.h>

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

@interface RunSketchViewController () <WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate>
@property(nonatomic,strong) NSURL *runtimeHTMLURL;
@property(nonatomic,strong) SketchProgram *program;
@property(nonatomic,strong) DetectedBug *pendingBug;
@property(nonatomic,strong) NSTimer *watchdog;
@property(nonatomic,assign) NSTimeInterval lastRuntimeActivity;
@property(nonatomic,assign) BOOL started;
@property(nonatomic,assign) BOOL failed;
@property(nonatomic,assign) BOOL runtimeReady;
@property(nonatomic,readwrite) BOOL completedSuccessfully;
@property(nonatomic,copy) NSSet<NSString *> *requestedSensors;
@property(nonatomic,strong) CMAltimeter *altimeter;
@property(nonatomic,strong) NSTimer *sensorTimer;
@property(nonatomic,strong) NSMutableDictionary *sensorReadings;
@property(nonatomic,strong) NSMutableDictionary *sensorStatuses;
@property(nonatomic,strong) NSMutableDictionary *lastSensorStatuses;
@property(nonatomic,assign) NSUInteger sensorGeneration;
@property(nonatomic,assign) BOOL sensorDeliveryInFlight;
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
    self.sketchWebView.UIDelegate = self;
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resumeRuntime) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pauseSensors) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [self.sketchWebView loadFileURL:self.runtimeHTMLURL allowingReadAccessToURL:projectURL];
}

- (void)resetWatchdog {
    self.lastRuntimeActivity = NSProcessInfo.processInfo.systemUptime;
    if (self.runtimeReady && !self.failed && !self.sensorTimer &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive) [self startMotionListeners];
}

- (void)resumeRuntime {
    [self resetWatchdog];
    if (self.runtimeReady && !self.failed) [self.sketchWebView evaluateJavaScript:@"SketchRuntime.resumeCameras()" completionHandler:nil];
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (self.failed || !message.frameInfo.isMainFrame || ![message.frameInfo.request.URL isEqual:self.runtimeHTMLURL]) return;
    if ([message.name isEqualToString:@"error"]) {
        DetectedBug *bug = [self.program bugFromMessage:message.body];
        if (bug) [self reportBug:bug];
    } else if ([message.name isEqualToString:@"iosbridge"] && [message.body isKindOfClass:NSDictionary.class]) {
        id event = message.body[@"event"];
        if ([event isEqual:@"heartbeat"] || [event isEqual:@"ready"]) {
            [self resetWatchdog];
            if ([event isEqual:@"ready"] && !self.runtimeReady) {
                NSArray *allowed = @[@"accelerometerUpdated", @"gyroscopeUpdated", @"orientationUpdated", @"gravityUpdated",
                                     @"userAccelerationUpdated", @"rotationRateUpdated", @"magnetometerUpdated", @"altimeterUpdated"];
                NSMutableSet *requested = [NSMutableSet set];
                id sensors = message.body[@"sensors"];
                if ([sensors isKindOfClass:NSArray.class]) {
                    for (id sensor in sensors) if ([allowed containsObject:sensor]) [requested addObject:sensor];
                }
                self.requestedSensors = requested;
                self.runtimeReady = YES;
                self.completedSuccessfully = YES;
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
    self.completedSuccessfully = NO;
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
    if (!self.runtimeReady || self.failed || self.sensorTimer || !self.requestedSensors.count ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    self.motionManager = [CMMotionManager new];
    self.sensorReadings = [NSMutableDictionary dictionary];
    self.sensorStatuses = [NSMutableDictionary dictionary];
    self.lastSensorStatuses = [NSMutableDictionary dictionary];
    NSUInteger generation = ++self.sensorGeneration;
    NSTimeInterval interval = 1.0 / 30.0;
    __weak typeof(self) weakSelf = self;
    if ([self.requestedSensors containsObject:@"accelerometerUpdated"]) {
        [self setSensorStatus:@"accelerometerUpdated" status:self.motionManager.accelerometerAvailable ? @"waiting" : @"unavailable"];
        if (self.motionManager.accelerometerAvailable) {
            self.motionManager.accelerometerUpdateInterval = interval;
            [self.motionManager startAccelerometerUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMAccelerometerData *data, NSError *error) {
                if (weakSelf.sensorGeneration != generation) return;
                [weakSelf queueSensor:@"accelerometerUpdated" values:data ? @[@(data.acceleration.x), @(data.acceleration.y), @(data.acceleration.z)] : nil error:error];
            }];
        }
    }
    if ([self.requestedSensors containsObject:@"gyroscopeUpdated"]) {
        [self setSensorStatus:@"gyroscopeUpdated" status:self.motionManager.gyroAvailable ? @"waiting" : @"unavailable"];
        if (self.motionManager.gyroAvailable) {
            self.motionManager.gyroUpdateInterval = interval;
            [self.motionManager startGyroUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMGyroData *data, NSError *error) {
                if (weakSelf.sensorGeneration != generation) return;
                [weakSelf queueSensor:@"gyroscopeUpdated" values:data ? @[@(data.rotationRate.x), @(data.rotationRate.y), @(data.rotationRate.z)] : nil error:error];
            }];
        }
    }
    NSArray *fused = @[@"orientationUpdated", @"gravityUpdated", @"userAccelerationUpdated", @"rotationRateUpdated"];
    BOOL needsDeviceMotion = NO;
    for (NSString *callback in fused) if ([self.requestedSensors containsObject:callback]) {
        needsDeviceMotion = YES;
        [self setSensorStatus:callback status:self.motionManager.deviceMotionAvailable ? @"waiting" : @"unavailable"];
    }
    if (needsDeviceMotion && self.motionManager.deviceMotionAvailable) {
        self.motionManager.deviceMotionUpdateInterval = interval;
        [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
            toQueue:NSOperationQueue.mainQueue withHandler:^(CMDeviceMotion *data, NSError *error) {
            if (weakSelf.sensorGeneration != generation) return;
            [weakSelf queueSensor:@"orientationUpdated" values:data ? @[@(data.attitude.roll), @(data.attitude.pitch), @(data.attitude.yaw)] : nil error:error];
            [weakSelf queueSensor:@"gravityUpdated" values:data ? @[@(data.gravity.x), @(data.gravity.y), @(data.gravity.z)] : nil error:error];
            [weakSelf queueSensor:@"userAccelerationUpdated" values:data ? @[@(data.userAcceleration.x), @(data.userAcceleration.y), @(data.userAcceleration.z)] : nil error:error];
            [weakSelf queueSensor:@"rotationRateUpdated" values:data ? @[@(data.rotationRate.x), @(data.rotationRate.y), @(data.rotationRate.z)] : nil error:error];
        }];
    }
    if ([self.requestedSensors containsObject:@"magnetometerUpdated"]) {
        [self setSensorStatus:@"magnetometerUpdated" status:self.motionManager.magnetometerAvailable ? @"waiting" : @"unavailable"];
        if (self.motionManager.magnetometerAvailable) {
            self.motionManager.magnetometerUpdateInterval = interval;
            [self.motionManager startMagnetometerUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMMagnetometerData *data, NSError *error) {
                if (weakSelf.sensorGeneration != generation) return;
                [weakSelf queueSensor:@"magnetometerUpdated" values:data ? @[@(data.magneticField.x), @(data.magneticField.y), @(data.magneticField.z)] : nil error:error];
            }];
        }
    }
    if ([self.requestedSensors containsObject:@"altimeterUpdated"]) {
        BOOL available = CMAltimeter.isRelativeAltitudeAvailable;
        CMAuthorizationStatus authorization = CMAltimeter.authorizationStatus;
        BOOL denied = authorization == CMAuthorizationStatusDenied || authorization == CMAuthorizationStatusRestricted;
        [self setSensorStatus:@"altimeterUpdated" status:!available ? @"unavailable" : denied ? @"denied" : @"waiting"];
        if (available && !denied) {
            self.altimeter = [CMAltimeter new];
            [self.altimeter startRelativeAltitudeUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMAltitudeData *data, NSError *error) {
                if (weakSelf.sensorGeneration != generation) return;
                [weakSelf queueSensor:@"altimeterUpdated" values:data ? @[data.relativeAltitude, data.pressure] : nil error:error];
            }];
        }
    }
    // Batch the newest values and allow only one pending WebKit evaluation.
    self.sensorTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
        [weakSelf deliverSensors];
    }];
}

- (void)setSensorStatus:(NSString *)callback status:(NSString *)status {
    if (![self.lastSensorStatuses[callback] isEqual:status]) {
        self.lastSensorStatuses[callback] = status;
        self.sensorStatuses[callback] = status;
    }
}

- (void)queueSensor:(NSString *)callback values:(NSArray<NSNumber *> *)values error:(NSError *)error {
    if (![self.requestedSensors containsObject:callback]) return;
    if (error) {
        BOOL denied = [error.domain isEqual:CMErrorDomain] && (error.code == CMErrorNotAuthorized || error.code == CMErrorMotionActivityNotAuthorized);
        [self setSensorStatus:callback status:denied ? @"denied" : @"error"];
    } else if (values && [NSJSONSerialization isValidJSONObject:values]) {
        self.sensorReadings[callback] = values;
        [self setSensorStatus:callback status:@"active"];
    }
}

- (void)deliverSensors {
    if (self.failed || !self.runtimeReady || self.sensorDeliveryInFlight ||
        (!self.sensorReadings.count && !self.sensorStatuses.count)) return;
    NSDictionary *packet = @{@"readings": self.sensorReadings, @"statuses": self.sensorStatuses};
    NSData *json = [NSJSONSerialization dataWithJSONObject:packet options:0 error:nil];
    if (!json) return;
    NSString *script = [NSString stringWithFormat:@"SketchRuntime.updateSensors(%@)", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    [self.sensorReadings removeAllObjects];
    [self.sensorStatuses removeAllObjects];
    self.sensorDeliveryInFlight = YES;
    NSUInteger generation = self.sensorGeneration;
    __weak typeof(self) weakSelf = self;
    [self.sketchWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (weakSelf.sensorGeneration != generation) return;
        weakSelf.sensorDeliveryInFlight = NO;
        if (error.code == WKErrorJavaScriptExceptionOccurred) {
            [weakSelf reportError:error.userInfo[@"WKJavaScriptExceptionMessage"] ?: error.localizedDescription];
        }
    }];
}

- (void)pauseSensors {
    ++self.sensorGeneration;
    [self.sensorTimer invalidate];
    self.sensorTimer = nil;
    self.sensorDeliveryInFlight = NO;
    [self.motionManager stopGyroUpdates];
    [self.motionManager stopAccelerometerUpdates];
    [self.motionManager stopDeviceMotionUpdates];
    [self.motionManager stopMagnetometerUpdates];
    [self.altimeter stopRelativeAltitudeUpdates];
    self.altimeter = nil;
    self.motionManager = nil;
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
        [self.sketchWebView evaluateJavaScript:@"SketchRuntime.pauseCameras()" completionHandler:nil];
        [self stopMediaCapture];
    }
}

- (void)stopMediaCapture {
    [self.sketchWebView setCameraCaptureState:WKMediaCaptureStateNone completionHandler:nil];
    [self.sketchWebView setMicrophoneCaptureState:WKMediaCaptureStateNone completionHandler:nil];
}

- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
    initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type
    decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    // Use persistent iOS consent for this app's local sketch, avoiding another
    // WebKit prompt every time capture restarts. Other pages remain blocked.
    BOOL isSketch = !self.failed && webView == self.sketchWebView && frame.isMainFrame &&
        [frame.request.URL isEqual:self.runtimeHTMLURL];
    if (!isSketch) { decisionHandler(WKPermissionDecisionDeny); return; }
    NSArray<NSString *> *mediaTypes;
    switch (type) {
        case WKMediaCaptureTypeCamera: mediaTypes = @[AVMediaTypeVideo]; break;
        case WKMediaCaptureTypeMicrophone: mediaTypes = @[AVMediaTypeAudio]; break;
        case WKMediaCaptureTypeCameraAndMicrophone: mediaTypes = @[AVMediaTypeVideo, AVMediaTypeAudio]; break;
        default: decisionHandler(WKPermissionDecisionDeny); return;
    }
    [self requestCaptureAccess:mediaTypes index:0 webView:webView frameURL:frame.request.URL decisionHandler:decisionHandler];
}

- (void)requestCaptureAccess:(NSArray<NSString *> *)mediaTypes index:(NSUInteger)index webView:(WKWebView *)webView
    frameURL:(NSURL *)frameURL decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    // Consent may complete after Back, backgrounding, or navigation. Re-check
    // the actual runner before granting access or asking for the next device.
    if (self.failed || webView != self.sketchWebView || ![frameURL isEqual:self.runtimeHTMLURL] ||
        ![webView.URL isEqual:self.runtimeHTMLURL] || UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
        decisionHandler(WKPermissionDecisionDeny);
        return;
    }
    if (index == mediaTypes.count) { decisionHandler(WKPermissionDecisionGrant); return; }
    NSString *mediaType = mediaTypes[index];
    AVAuthorizationStatus authorization = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    if (authorization == AVAuthorizationStatusAuthorized) {
        [self requestCaptureAccess:mediaTypes index:index + 1 webView:webView frameURL:frameURL decisionHandler:decisionHandler];
    } else if (authorization == AVAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!granted || !strongSelf) { decisionHandler(WKPermissionDecisionDeny); return; }
                [strongSelf requestCaptureAccess:mediaTypes index:index + 1 webView:webView frameURL:frameURL decisionHandler:decisionHandler];
            });
        }];
    } else {
        decisionHandler(WKPermissionDecisionDeny);
    }
}

- (void)stopRuntime {
    self.runtimeReady = NO;
    [self.watchdog invalidate];
    self.watchdog = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self pauseSensors];
    [self.sketchWebView evaluateJavaScript:@"SketchRuntime.stop()" completionHandler:nil];
    [self stopMediaCapture];
    [self.sketchWebView.configuration.userContentController removeScriptMessageHandlerForName:@"error"];
    [self.sketchWebView.configuration.userContentController removeScriptMessageHandlerForName:@"iosbridge"];
    self.sketchWebView.navigationDelegate = nil;
    self.sketchWebView.UIDelegate = nil;
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
