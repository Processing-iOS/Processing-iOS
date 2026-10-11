//
//  EditorViewController.m
//  Processing for iOS
//
//  Created by Frederik Riedel on 27.06.15.
//  Copyright (c) 2015 Frederik Riedel. All rights reserved.
//

#import "PDEEditorViewController.h"
#import "Processing_for_iOS-Swift.h"
#import "FRFileManager.h"
#import "NSString+LevenshteinDistance.h"
@import SafariServices;

@interface PDEEditorViewController ()
@property(nonatomic,copy) NSString *suggestionSource;
@property(nonatomic,assign) NSRange suggestionRange;
@property(nonatomic,strong) CodeCompletionController *completionController;
@property(nonatomic,copy) NSString *lastObservedText;
@property(nonatomic,strong) CodeHighlighter *highlighter;
@end

@implementation PDEEditorViewController

-(instancetype)initWithSourceCodeFile:(SourceCodeFile*)sourceCodeFile {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.sourceCodeFile = sourceCodeFile;
    return self;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    if (@available(iOS 11.0, *)) {
        self.navigationController.navigationBar.prefersLargeTitles = NO;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    
    
    self.editor.text = self.sourceCodeFile.content;
    self.lastObservedText = self.editor.text;
    self.editor.font = [UIFont fontWithName:@"SourceCodePro-Regular" size:18];
    self.highlighter = [[CodeHighlighter alloc] initWithTextView:self.editor language:self.sourceCodeFile.fileExtension];
    self.completionController = [[CodeCompletionController alloc] initWithTextView:self.editor file:self.sourceCodeFile projectFiles:self.completionFiles ?: @[]];
    __weak typeof(self) weakSelf = self;
    self.completionController.didComplete = ^{ [weakSelf textViewDidChange:weakSelf.editor]; };
    
    [self highlightCode];
    
    [self.editor setContentOffset: CGPointMake(0, 0) animated:NO];
}


-(NSArray<UIKeyCommand *> *)keyCommands {
    
    UIKeyCommand* format = [UIKeyCommand keyCommandWithInput:@"t" modifierFlags:UIKeyModifierCommand action:@selector(formatCode) discoverabilityTitle:@"Format Code"];
    UIKeyCommand* run = [UIKeyCommand keyCommandWithInput:@"r" modifierFlags:UIKeyModifierCommand action:@selector(runSketch) discoverabilityTitle:@"Run Code"];
    UIKeyCommand* close = [UIKeyCommand keyCommandWithInput:@"w" modifierFlags:UIKeyModifierCommand action:@selector(close) discoverabilityTitle:@"Close Project"];
    UIKeyCommand *esc = [UIKeyCommand keyCommandWithInput: UIKeyInputEscape modifierFlags: 0 action: @selector(close) discoverabilityTitle:@"Close Project"];
    
    UIKeyCommand *complete = [UIKeyCommand keyCommandWithInput:@" " modifierFlags:UIKeyModifierControl action:@selector(showCompletions)];
    complete.discoverabilityTitle = @"Complete Code";
    complete.wantsPriorityOverSystemBehavior = YES;
    if (self.completionController.hasSuggestions) {
        UIKeyCommand *accept = [UIKeyCommand keyCommandWithInput:@"\t" modifierFlags:0 action:@selector(acceptCompletion)];
        accept.wantsPriorityOverSystemBehavior = YES;
        UIKeyCommand *dismiss = [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(dismissCompletions)];
        dismiss.wantsPriorityOverSystemBehavior = YES;
        return @[format, run, close, complete, accept, dismiss];
    }
    return @[format, run, close, complete, esc];
}

- (void)showCompletions { [self.completionController show]; }
- (void)acceptCompletion { [self.completionController acceptFirst]; }
- (void)dismissCompletions { [self.completionController dismiss]; }


-(void)formatCode {
    [self.completionController dismiss];
    self.bugToHighlight = nil;
    self.suggestionSource = nil;
    
    NSArray *codeLines = [self.editor.text componentsSeparatedByString:@"\n"];
    
    NSInteger codeLevel[codeLines.count];
    
    int currentCodeLevel = 0;
    int currentLine = 0;
    
    for(NSString *lineOfCode in codeLines) {
        NSRange range = [lineOfCode rangeOfString:@"^\\s*" options:NSRegularExpressionSearch];
        NSString *result = [lineOfCode stringByReplacingCharactersInRange:range withString:@""];
        
        range = [result rangeOfString:@"\\s*$" options:NSRegularExpressionSearch];
        result = [result stringByReplacingCharactersInRange:range withString:@""];
        
        if(result.length>0) {
            NSString *firstChar = [result substringToIndex:1];
            NSString *lastChar = [result substringFromIndex:result.length-1];
            
            
            if([firstChar isEqualToString:@"}"] && [lastChar isEqualToString:@"{"]) {
                codeLevel[currentLine] = currentCodeLevel-1;
            } else if([firstChar isEqualToString:@"{"] || [lastChar isEqualToString:@"{"]) {
                codeLevel[currentLine] = currentCodeLevel;
                currentCodeLevel++;
            } else if([firstChar isEqualToString:@"}"]) {
                currentCodeLevel--;
                codeLevel[currentLine] = currentCodeLevel;
            } else {
                codeLevel[currentLine] = currentCodeLevel;
            }
        } else {
            codeLevel[currentLine] = currentCodeLevel;
        }
        
        currentLine++;
    }
    
    currentLine = 0;
    
    NSMutableArray *resultCodeLines = [[NSMutableArray alloc] init];
    
    for(NSString *lineOfCode in codeLines) {
        NSRange range = [lineOfCode rangeOfString:@"^\\s*" options:NSRegularExpressionSearch];
        NSString *result = [lineOfCode stringByReplacingCharactersInRange:range withString:@""];
        
        NSString *whitespaces = @"";
        
        for(int i=0; i < codeLevel[currentLine]; i++) {
            whitespaces = [NSString stringWithFormat:@"%@   ",whitespaces];
        }
        
        result = [NSString stringWithFormat:@"%@%@",whitespaces,result];
        [resultCodeLines addObject:result];
        
        currentLine++;
    }
    
    NSString *autoFormattedCode = [resultCodeLines componentsJoinedByString:@"\n"];
    
    CGPoint contentOffset = self.editor.contentOffset;
    self.editor.scrollEnabled=NO;
    NSRange currentCurserPosition = self.editor.selectedRange;
    
    self.editor.text=autoFormattedCode;
    
    self.editor.selectedRange = currentCurserPosition;
    self.editor.scrollEnabled=YES;
    [[NSOperationQueue mainQueue] addOperationWithBlock: ^{
        [self.editor setContentOffset: contentOffset animated:NO];
    }];
    
    [self highlightCode];
    [self saveCode];
}

-(void)highlightCode {
    [self.highlighter highlightNow];
    NSString *text = self.editor.text ?: @"";
    NSRange range = [self.bugToHighlight rangeInSource:text];
    if (self.bugToHighlight && range.location != NSNotFound && NSMaxRange(range) <= text.length) {
        [self.editor.textStorage addAttributes:@{NSUnderlineStyleAttributeName: @(NSUnderlineStyleThick),
            NSForegroundColorAttributeName: UIColor.systemRedColor} range:range];
    }
}

- (void)highlightCompilerErrorOfCode: (DetectedBug*)detectedBug {
    [self.completionController dismiss];

    if (![self.sourceCodeFile.fileName isEqualToString:detectedBug.fileName]) return;
    [self loadViewIfNeeded];
    NSString *text = self.editor.text ?: @"";
    NSRange range = [detectedBug rangeInSource:text];
    if (range.location == NSNotFound || range.location > text.length || range.length > text.length - range.location) return;
    self.bugToHighlight = detectedBug;
    [self highlightCode];
    self.editor.selectedRange = range;
    [self.editor scrollRangeToVisible:range];
    if (detectedBug.bugType != BugTypeReferenceError || detectedBug.wrongCode.length == 0 || range.length == 0) return;
    if (![[text substringWithRange:range] isEqualToString:detectedBug.wrongCode]) return;

    BOOL isProcessing = [self.sourceCodeFile.fileExtension isEqualToString:@"pde"];
    BOOL isClearCall = isProcessing && [detectedBug.wrongCode isEqualToString:@"clear"] &&
        text.length - range.location >= 8 && [[text substringWithRange:NSMakeRange(range.location, 8)] isEqualToString:@"clear();"];
    if (isClearCall) range.length = 8;
    self.suggestionSource = text;
    self.suggestionRange = range;

    UITextPosition *start = [self.editor positionFromPosition:self.editor.beginningOfDocument offset:range.location];
    UITextPosition *end = [self.editor positionFromPosition:start offset:range.length];
    if (!start || !end) return;
    UITextRange *textRange = [self.editor textRangeFromPosition:start toPosition:end];

    NSDictionary* fixSuggestions = @{
        @"clear": @[
                @{
                    @"suggestion": @"background(0);",
                    @"explanation_subtitle": @"“clear();” is not available on iOS. Use “background(0);“ instead for a black background.",
                    @"explanation": @"Replace with “background(0);”"
                },
                @{
                    @"suggestion": @"background(255);",
                    @"explanation_subtitle": @"“clear();” is not available on iOS. Use “background(255);“ instead for a white background.",
                    @"explanation": @"Replace with “background(255);”"
                }
        ],
        @"displaywidth": @[
                @{
                    @"suggestion": @"screenWidth",
                    @"explanation_subtitle": @"Use “screenWidth” for the sketch viewport width.",
                    @"explanation": @"Replace with “screenWidth”"
                }
        ],
        @"displayheight": @[
                @{
                    @"suggestion": @"screenHeight",
                    @"explanation_subtitle": @"Use “screenHeight” for the sketch viewport height.",
                    @"explanation": @"Replace with “screenHeight”"
                }
        ],
        @"pop": @[
                @{
                    @"suggestion": @"popMatrix",
                    @"explanation_subtitle": @"“pop” is not available on iOS. Use “popMatrix“ instead.",
                    @"explanation": @"Replace with “popMatrix”"
                },
                @{
                    @"suggestion": @"popStyle",
                    @"explanation_subtitle": @"“pop” is not available on iOS. Use “popStyle“ instead.",
                    @"explanation": @"Replace with “popStyle”"
                }
        ],
        @"push": @[
                @{
                    @"suggestion": @"pushMatrix",
                    @"explanation_subtitle": @"“push” is not available on iOS. Use “pushMatrix“ instead.",
                    @"explanation": @"Replace with “pushMatrix”"
                },
                @{
                    @"suggestion": @"pushStyle",
                    @"explanation_subtitle": @"“push” is not available on iOS. Use “pushStyle“ instead.",
                    @"explanation": @"Replace with “pushStyle”"
                }
        ]
    };
    
    NSArray *knownFixes = isProcessing ? fixSuggestions[detectedBug.wrongCode.lowercaseString] : nil;
    if ([detectedBug.wrongCode isEqualToString:@"clear"] && !isClearCall) knownFixes = nil;
    NSMutableArray<NSDictionary<NSString*, NSString*>*> *suggestionsForWrongCode = [NSMutableArray arrayWithArray:knownFixes ?: @[]];
    
    NSMutableArray<NSString*>* legitCommands = [NSMutableArray arrayWithArray:@[
        @"cos",
        @"sin",
        @"float",
        @"int",
        @"fill",
        @"stroke",
        @"noStroke",
        @"strokeWeight",
        @"rect",
        @"ellipse",
        @"map",
        @"norm",
        @"line",
        @"vertex",
        @"radians",
        @"endShape",
        @"beginShape",
        @"mousePressed",
        @"background",
        @"noLoop",
        @"random",
        @"translate",
        @"rotate",
        @"scale"
    ]];
    [legitCommands addObjectsFromArray:isProcessing ? @[@"double", @"screenWidth", @"screenHeight"] :
        @[@"windowWidth", @"windowHeight", @"createCanvas", @"push", @"pop", @"clear"]];
    
    
    for (NSString* suggestion in legitCommands) {
        
        NSUInteger distance = [suggestion levenshteinDistanceTo: detectedBug.wrongCode];
        if (!isClearCall && distance > 0 && distance < 3) {
            
            [suggestionsForWrongCode addObject:@{
                @"suggestion": suggestion,
                @"explanation_subtitle": [NSString stringWithFormat:@"Replace “%@” with “%@”?", detectedBug.wrongCode, suggestion],
                @"explanation": [NSString stringWithFormat:@"Replace with “%@”", suggestion]
            }];
            
        }
    }
    
    
    

    if (suggestionsForWrongCode.count == 0 || self.presentedViewController) return;

    SelectableOptionsViewController* selectOptionsVC = [[SelectableOptionsViewController alloc] initWithSelectableOptions:suggestionsForWrongCode forRange:range bug: detectedBug];
    
    CGRect rect = [self.editor firstRectForRange:textRange];
    
    CGFloat distanceUnderBottomScreenEdge = self.editor.frame.size.height - rect.origin.y;
    CGFloat newScrollPosition = self.editor.frame.size.height - distanceUnderBottomScreenEdge - (self.editor.frame.size.height / 2);
    
    if (distanceUnderBottomScreenEdge < 100) {
        [self.editor setContentOffset:CGPointMake(self.editor.contentOffset.x, newScrollPosition)];
        rect = [self.editor firstRectForRange:textRange];
    }
    
    selectOptionsVC.modalPresentationStyle = UIModalPresentationPopover;
    selectOptionsVC.popoverPresentationController.sourceView = self.editor;
    selectOptionsVC.popoverPresentationController.sourceRect = rect;
    selectOptionsVC.popoverPresentationController.backgroundColor = [UIColor clearColor];
    
    selectOptionsVC.delegate = self;
    
    [self presentViewController: selectOptionsVC animated: true completion: nil];
    
}

-(void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    NSString *currentText = self.editor.text ?: @"";
    if (![currentText isEqualToString:self.suggestionSource] || !NSEqualRanges(range, self.suggestionRange) ||
        range.location == NSNotFound || range.location > currentText.length || range.length > currentText.length - range.location) return;
    self.bugToHighlight = nil;
    self.suggestionSource = nil;
    self.editor.text = [currentText stringByReplacingCharactersInRange:range withString:string];
    [self highlightCode];
    [self saveCode];
}

- (void)keyboardWillChange:(NSNotification *)notification {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:[notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    [UIView setAnimationCurve:[notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue]];
    [UIView setAnimationBeginsFromCurrentState:YES];
    
    NSDictionary* info = [notification userInfo];
    CGRect keyboardRect = [self.editor convertRect:[[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGSize keyboardSize = keyboardRect.size;
    
    
    self.editor.contentInset = UIEdgeInsetsMake(0, 0, keyboardSize.height, 0);
    self.editor.scrollIndicatorInsets = self.editor.contentInset;
    
    [UIView commitAnimations];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:[notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    [UIView setAnimationCurve:[notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue]];
    [UIView setAnimationBeginsFromCurrentState:YES];
    self.editor.contentInset = UIEdgeInsetsZero;
    self.editor.scrollIndicatorInsets = UIEdgeInsetsZero;
    [UIView commitAnimations];
}

-(void)viewWillDisappear:(BOOL)animated {
    [self.editor resignFirstResponder];
    [self.completionController dismiss];
    //if ([self.navigationController.viewControllers indexOfObject:self]==NSNotFound) {
    [self saveCode];
    //}
    [super viewWillDisappear:animated];
}

-(BOOL)saveCode {
    // A failed read must not replace the original file with an empty editor buffer.
    if (!self.sourceCodeFile.content && self.sourceCodeFile.readError) return NO;
    if (![self.editor.text isEqualToString:self.lastObservedText]) {
        self.lastObservedText = self.editor.text;
        [self.sourceCodeFile updateContent:self.editor.text];
    }
    return [self.sourceCodeFile saveWithNewContent:nil];
}

-(void)textViewDidChange:(UITextView *) textView {
    self.lastObservedText = self.editor.text;
    [self.sourceCodeFile updateContent:self.editor.text];
    self.bugToHighlight = nil;
    self.suggestionSource = nil;
    [self.highlighter schedule];
    [self.completionController scheduleUpdate];
}

- (void)textViewDidChangeSelection:(UITextView *)textView {
    [self.completionController scheduleUpdate];
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    [self.navigationController setToolbarHidden:YES animated:YES];
    [self.completionController scheduleUpdate];
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    [self.completionController dismiss];
    if (self.view.window) [self.navigationController setToolbarHidden:NO animated:YES];
}

-(BOOL)canBecomeFirstResponder {
    return YES;
}

-(UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:self.editor.isFirstResponder animated:YES];
}

@end
