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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveCode) name:@"saveCode" object:nil];
    
    
    self.editor.text = self.sourceCodeFile.content;
    
    [self highlightCode];
    [self codeLineIndent];
    
    [self.editor setContentOffset: CGPointMake(0, 0) animated:NO];
}


-(NSArray<UIKeyCommand *> *)keyCommands {
    
    UIKeyCommand* format = [UIKeyCommand keyCommandWithInput:@"t" modifierFlags:UIKeyModifierCommand action:@selector(formatCode) discoverabilityTitle:@"Format Code"];
    UIKeyCommand* run = [UIKeyCommand keyCommandWithInput:@"r" modifierFlags:UIKeyModifierCommand action:@selector(runSketch) discoverabilityTitle:@"Run Code"];
    UIKeyCommand* close = [UIKeyCommand keyCommandWithInput:@"w" modifierFlags:UIKeyModifierCommand action:@selector(close) discoverabilityTitle:@"Close Project"];
    UIKeyCommand *esc = [UIKeyCommand keyCommandWithInput: UIKeyInputEscape modifierFlags: 0 action: @selector(close) discoverabilityTitle:@"Close Project"];
    
    return @[format, run, close, esc];
}



-(void)formatCode {
    
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
    [self codeLineIndent];
}

-(void) codeLineIndent {
    NSMutableAttributedString * string = [[NSMutableAttributedString alloc] initWithAttributedString:self.editor.attributedText];
    [string addAttribute:NSFontAttributeName value:[UIFont fontWithName:@"SourceCodePro-Regular" size:18] range:NSMakeRange(0, string.length)];
    
    NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    style.headIndent = 32;
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: style
    };
    
    [string addAttributes:attributes range:NSMakeRange(0, string.length)];
    
    CGPoint contentOffset = self.editor.contentOffset;
    self.editor.scrollEnabled=NO;
    NSRange currentCurserPosition = self.editor.selectedRange;
    
    [self.editor setAttributedText:string];
    
    self.editor.selectedRange = currentCurserPosition;
    self.editor.scrollEnabled=YES;
    [[NSOperationQueue mainQueue] addOperationWithBlock: ^{
        [self.editor setContentOffset: contentOffset animated:NO];
    }];
}



-(void) highlightCode {
    
    NSString* text = self.editor.text;
    
    if (text == nil) {
        text = self.editor.attributedText.string;
    }
    
    
    if(text) {
        NSMutableAttributedString * string = [[NSMutableAttributedString alloc] initWithString: text];
        [string addAttribute:NSFontAttributeName value:[UIFont fontWithName:@"SourceCodePro-Regular" size:18] range:NSMakeRange(0, string.length)];
        
        if (@available(iOS 13.0, *)) {
            [string addAttribute: NSForegroundColorAttributeName value: UIColor.labelColor range: NSMakeRange(0, string.length)];
        }
        
        
        for(NSDictionary *syntaxPattern in [FRFileManager syntaxHighlighterDictionaryForSourceFileType:self.sourceCodeFile.fileExtension]) {
            NSString *patternString = syntaxPattern[@"regex"];
            
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:patternString options:NSRegularExpressionCaseInsensitive error:NULL];
            
            NSArray *matchResults = [regex matchesInString:self.editor.text options:0 range:NSMakeRange(0, self.editor.text.length)];
            
            //es kann bei richtigen matches nur ein match geben
            
            for(NSTextCheckingResult *match in matchResults) {
                NSRange matchRange = [match range];
                
                CGFloat red = [[syntaxPattern[@"color"] componentsSeparatedByString:@","][0] floatValue]/255;
                CGFloat green = [[syntaxPattern[@"color"] componentsSeparatedByString:@","][1] floatValue]/255;
                CGFloat blue = [[syntaxPattern[@"color"] componentsSeparatedByString:@","][2] floatValue]/255;
                
                
                [string addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:red green:green blue:blue alpha:1.f] range:matchRange];
                
                if(syntaxPattern[@"bold"]) {
                    [string addAttribute:NSFontAttributeName value:[UIFont fontWithName:@"SourceCodePro-Semibold" size:18] range:matchRange];
                } else {
                    [string addAttribute:NSFontAttributeName value:[UIFont fontWithName:@"SourceCodePro-Regular" size:18] range:matchRange];
                }
            }
        }
        
        if (self.bugToHighlight) {
            NSRange range = [text rangeOfString: self.bugToHighlight];
            
            NSRange fullRange = [text rangeOfString:[NSString stringWithFormat:@"%@();", self.bugToHighlight]];
            
            if (fullRange.location != NSNotFound) {
                range = fullRange;
            }
            
            [string addAttribute: NSUnderlineStyleAttributeName value: [NSNumber numberWithInt:NSUnderlineStyleThick|NSUnderlineStyleSingle] range: range];
            [string addAttribute: NSForegroundColorAttributeName value: [UIColor colorNamed:@"redAlertColor"] range: range];
//            [string addAttribute:NSFontAttributeName value:[UIFont fontWithName:@"SourceCodePro-Semibold" size:18] range:range];
//            [string addAttribute:NSBackgroundColorAttributeName value: [UIColor colorNamed:@"lightRedAlertColor"] range: range];
        }
        
        //Cursorposition speichern
        CGPoint contentOffset = self.editor.contentOffset;
        
        self.editor.scrollEnabled=NO;
        NSRange currentCurserPosition = self.editor.selectedRange;
        
        [self.editor setAttributedText:string];
        
        self.editor.selectedRange = currentCurserPosition;
        [self.editor setContentOffset: contentOffset animated:NO];
        self.editor.scrollEnabled=YES;
    }
}

- (void)highlightCompilerErrorOfCode: (DetectedBug*)detectedBug {
    
    self.bugToHighlight = detectedBug.wrongCode;
    [self highlightCode];
    
    NSString* text = [self.sourceCodeFile content];
    NSRange range = [text rangeOfString: self.bugToHighlight];
    
    NSRange fullRange = [text rangeOfString:[NSString stringWithFormat:@"%@();", self.bugToHighlight]];
    
    if (fullRange.location != NSNotFound) {
        range = fullRange;
    }
    [self.editor scrollRangeToVisible: range];
    
    
    UITextPosition *beginning = self.editor.beginningOfDocument;
    UITextPosition *start = [self.editor positionFromPosition:beginning offset:range.location];
    UITextPosition *end = [self.editor positionFromPosition:start offset:range.length];
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
        @"displayWidth": @[
                @{
                    @"suggestion": @"screenWidth",
                    @"explanation_subtitle": @"“displayWidth” is not available on iOS. Use “screenWidth“ instead.",
                    @"explanation": @"Replace with “screenWidth”"
                }
        ],
        @"displayHeight": @[
                @{
                    @"suggestion": @"screenHeight",
                    @"explanation_subtitle": @"“displayHeight” is not available on iOS. Use “screenHeight“ instead.",
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
    
    NSMutableArray<NSDictionary<NSString*, NSString*>*>* suggestionsForWrongCode = [NSMutableArray arrayWithArray:fixSuggestions[detectedBug.wrongCode.lowercaseString]];
    
    NSArray<NSString*>* legitCommands = @[
        @"cos",
        @"sin",
        @"float",
        @"double",
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
        @"screenWidth",
        @"screenHeight",
        @"background"
    ];
    
    
    for (NSString* suggestion in legitCommands) {
        
        NSUInteger distance = [suggestion levenshteinDistanceTo: detectedBug.wrongCode];
        if (distance < 3) {
            
            [suggestionsForWrongCode addObject:@{
                @"suggestion": suggestion,
                @"explanation_subtitle": [NSString stringWithFormat:@"Replace “%@” with “%@”?", detectedBug.wrongCode, suggestion],
                @"explanation": [NSString stringWithFormat:@"Replace with “%@”", suggestion]
            }];
            
        }
    }
    
    
    

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
    NSString* currentText = self.sourceCodeFile.content;
    NSString* newText = [currentText stringByReplacingCharactersInRange:range withString:string];
    self.editor.text = newText;
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
    //if ([self.navigationController.viewControllers indexOfObject:self]==NSNotFound) {
    [self saveCode];
    //}
    [super viewWillDisappear:animated];
}

-(void)saveCode {
    [self.sourceCodeFile saveWithNewContent: self.editor.text];
}

-(void)textViewDidChange:(UITextView *) textView {
    [self highlightCode];
    [self codeLineIndent];
}

-(BOOL)canBecomeFirstResponder {
    return YES;
}

-(UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:YES];
}

@end
