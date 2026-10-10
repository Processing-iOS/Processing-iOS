//
//  PDESketch.h
//  Processing for iOS
//
//  Created by Frederik Riedel on 10/25/17.
//  Copyright © 2017 Frederik Riedel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PDEFile.h"

@import UIKit;

@interface PDESketch : NSObject

-(instancetype)initWithSketchName:(NSString*)sketchName;
-(NSString*)filePath;
-(NSString*)cummulatedSourceCode;
-(NSString*)htmlPage;

@property(nonatomic,strong) NSString* sketchName;
@property(nonatomic,strong) NSDate* creationDate;
@property(nonatomic,strong) NSArray<PDEFile*>* pdeFiles;


@end
