//
//  SketchController.h
//  Processing for iOS
//
//  Created by Frederik Riedel on 10/25/17.
//  Copyright © 2017 Frederik Riedel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PDESketch.h"

@class SimpleTextProject;

@interface SketchController : NSObject
+(void)loadSketches:(void (^ _Null_unspecified)(NSArray<PDESketch*>* _Null_unspecified sketches))callback;
+(void)loadProjects:(void (^ _Null_unspecified)(NSArray<SimpleTextProject*>* _Null_unspecified projects))callback;
+(NSArray<NSString*>* _Nonnull)bundledSampleFileNames;
+(nullable NSArray<NSString*>*)importSampleProjects:(NSArray<NSString*>* _Nonnull)fileNames error:(NSError* _Nullable * _Nullable)error NS_SWIFT_NAME(importSampleProjects(_:));
+(void)deleteSketchWithName:(NSString* _Null_unspecified)sketchName;
+(void)savePDESketch:(PDESketch* _Null_unspecified)sketch;
+(NSString* _Null_unspecified)documentsDirectory;
@end
