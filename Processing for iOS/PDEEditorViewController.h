//
//  EditorViewController.h
//  Processing for iOS
//
//  Created by Frederik Riedel on 27.06.15.
//  Copyright (c) 2015 Frederik Riedel. All rights reserved.
//


#import <UIKit/UIKit.h>
#import "PDEFile.h"
#import "PDESketch.h"
#import "RunSketchViewController.h"

// fwd declared
@class SourceCodeFile;

// fwd declared
@protocol SelectableOptionsViewControllerDelegate <NSObject>
-(void)replaceCharactersInRange:(NSRange) range withString: (NSString*) string;
@end

@interface PDEEditorViewController : UIViewController<UITextViewDelegate, SelectableOptionsViewControllerDelegate>

-(instancetype)initWithSourceCodeFile:(SourceCodeFile*)sourceCodeFile;
-(void)saveCode;
-(void)formatCode;
- (void)highlightCompilerErrorOfCode: (DetectedBug*)detectedBug;

@property(nonatomic,strong) SourceCodeFile* sourceCodeFile;
@property (strong, nonatomic) IBOutlet UITextView *editor;
@property (strong, nonatomic) NSString* bugToHighlight;


@end
