//
//  SketchController.m
//  Processing for iOS
//
//  Created by Frederik Riedel on 10/25/17.
//  Copyright © 2017 Frederik Riedel. All rights reserved.
//

#import "SketchController.h"
#import "FirstStart.h"
#import "Processing_for_iOS-Swift.h"
#import <CommonCrypto/CommonDigest.h>

@implementation SketchController

+(NSArray<NSString*>*)bundledSampleFileNames {
    return @[@"Example_3D.pde", @"Example_Draw.pde", @"Example_Clock.pde",
             @"Example_FollowMe.pde", @"Example_Multitouch.pde",
             @"Example_Gyroscope_Accelerometer.pde", @"Example_Sensors.pde",
             @"Example_Camera.js"];
}

+(NSArray<NSString*>*)importSampleProjects:(NSArray<NSString*>*)fileNames error:(NSError**)error {
    NSSet<NSString*> *selected = [NSSet setWithArray:fileNames];
    NSArray<NSString*> *available = [self bundledSampleFileNames];
    if (![selected isSubsetOfSet:[NSSet setWithArray:available]]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError
            userInfo:@{NSLocalizedDescriptionKey: @"One of the selected samples is not available."}];
        return nil;
    }
    if (selected.count == 0) return @[];

    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:[[self documentsDirectory] stringByAppendingPathComponent:@"sketches"] isDirectory:YES];
    if (![files createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSMutableArray<NSString*> *importedNames = [NSMutableArray array];

    for (NSString *fileName in available) {
        if (![selected containsObject:fileName]) continue;
        NSString *baseName = fileName.stringByDeletingPathExtension;
        NSString *extension = fileName.pathExtension;
        NSURL *source = [NSBundle.mainBundle URLForResource:baseName withExtension:extension];
        if (!source) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The bundled sample %@ is missing.", fileName]}];
            return nil;
        }
        NSData *bundledContents = [NSData dataWithContentsOfURL:source options:0 error:error];
        if (!bundledContents) return nil;

        // Repeated imports reuse an unchanged copy, including numbered copies.
        // Never replace a project: it may contain edits or additional files.
        NSArray<NSString*> *projectNames = [files contentsOfDirectoryAtPath:root.path error:error];
        if (!projectNames) return nil;
        NSPredicate *sampleNames = [NSPredicate predicateWithFormat:@"SELF MATCHES %@",
            [NSString stringWithFormat:@"%@(_[0-9]+)?", baseName]];
        BOOL alreadyAvailable = NO;
        for (NSString *name in [projectNames filteredArrayUsingPredicate:sampleNames]) {
            NSURL *project = [root URLByAppendingPathComponent:name isDirectory:YES];
            NSString *sourceName = [name stringByAppendingPathExtension:extension];
            NSMutableArray<NSString*> *contents = [[files contentsOfDirectoryAtPath:project.path error:nil] mutableCopy];
            [contents removeObject:@".DS_Store"];
            // An interrupted run can leave its generated HTML behind.
            for (NSString *entry in contents.copy) {
                if ([entry hasPrefix:@"__runtime_"] && [entry.pathExtension isEqualToString:@"html"] &&
                    [[NSUUID alloc] initWithUUIDString:[entry.stringByDeletingPathExtension substringFromIndex:@"__runtime_".length]]) {
                    [contents removeObject:entry];
                }
            }
            // Running a sketch creates an empty data folder; this isn't an edit.
            NSArray<NSString*> *dataContents = [files contentsOfDirectoryAtPath:[project URLByAppendingPathComponent:@"data"].path error:nil];
            if (dataContents && dataContents.count == 0) [contents removeObject:@"data"];
            if (contents.count == 1 && [contents.firstObject isEqualToString:sourceName] &&
                [bundledContents isEqualToData:[NSData dataWithContentsOfURL:[project URLByAppendingPathComponent:sourceName]]]) {
                alreadyAvailable = YES;
                break;
            }
        }
        if (alreadyAvailable) continue;

        NSString *name = baseName;
        NSUInteger suffix = 2;
        while ([files fileExistsAtPath:[root URLByAppendingPathComponent:name].path]) {
            name = [NSString stringWithFormat:@"%@_%lu", baseName, (unsigned long)suffix++];
        }
        NSURL *destination = [root URLByAppendingPathComponent:name isDirectory:YES];
        NSURL *staging = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        BOOL installed = [files createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:nil error:error] &&
            [files copyItemAtURL:source toURL:[staging URLByAppendingPathComponent:[name stringByAppendingPathExtension:extension]] error:error] &&
            [files moveItemAtURL:staging toURL:destination error:error];
        [files removeItemAtURL:staging error:nil];
        if (!installed) return nil;
        [importedNames addObject:name];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:[@"installedBundledSample." stringByAppendingString:fileName]];
    }
    return importedNames;
}

+(void)copySampleProjectsOnFirstStart {
    if ([FirstStart isFirstStart]) {
        NSArray<NSString*>* sampleProjects = @[@"Example_3D",@"Example_Draw",@"Example_Clock",@"Example_FollowMe",@"Example_Multitouch", @"Example_Gyroscope_Accelerometer"];
        
        for (NSString* fileName in sampleProjects) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[[[self documentsDirectory] stringByAppendingPathComponent:@"sketches"] stringByAppendingPathComponent:fileName] withIntermediateDirectories:YES attributes:nil error:nil];
            NSError* error;
            
            
            NSString* mainBundlePath = [[NSBundle mainBundle] pathForResource:fileName ofType:@"pde"];
            NSString* documentsDirectoryPath = [[[[[self documentsDirectory] stringByAppendingPathComponent:@"sketches"] stringByAppendingPathComponent:fileName] stringByAppendingPathComponent:fileName] stringByAppendingString:@".pde"];
            
            [[NSFileManager defaultManager] copyItemAtPath:mainBundlePath toPath:documentsDirectoryPath error:&error];
        }
        
    }
}

+(void)installAdditionalSamples {
    // Upgrade earlier camera examples only when they are byte-for-byte bundled
    // originals. A user's edits must always win.
    NSURL *cameraURL = [NSURL fileURLWithPath:[[self documentsDirectory] stringByAppendingPathComponent:@"sketches/Example_Camera/Example_Camera.js"]];
    NSData *existingCamera = [NSData dataWithContentsOfURL:cameraURL];
    if (existingCamera.length == 5685 || existingCamera.length == 339 || existingCamera.length == 337) {
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(existingCamera.bytes, (CC_LONG)existingCamera.length, digest);
        NSMutableString *hash = [NSMutableString string];
        for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hash appendFormat:@"%02x", digest[i]];
        if ([@[@"ccb109736ceb19444b5832112b7c8a29dffb4db1f99c65e16592d4ba01706fad",
               @"d1e0e2e64ef54e0223c4df3cfb6077ec907c6aafaae52c1c892006dd09013ab8",
               @"02757574b4745e3b624b5cc7fd37603bba71343508012994f238231401cf6fea"] containsObject:hash]) {
            NSURL *bundled = [NSBundle.mainBundle URLForResource:@"Example_Camera" withExtension:@"js"];
            NSData *replacement = bundled ? [NSData dataWithContentsOfURL:bundled] : nil;
            if (replacement) [replacement writeToURL:cameraURL options:NSDataWritingAtomic error:nil];
        }
    }
    // Offer new examples once on upgrades as well as fresh installs. Never
    // replace an existing project or resurrect a sample the user has deleted.
    for (NSString *fileName in @[@"Example_Sensors.pde", @"Example_Camera.js"]) {
        NSString *key = [@"installedBundledSample." stringByAppendingString:fileName];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if ([defaults boolForKey:key]) continue;
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *name = fileName.stringByDeletingPathExtension;
        NSURL *root = [NSURL fileURLWithPath:[[self documentsDirectory] stringByAppendingPathComponent:@"sketches"] isDirectory:YES];
        NSURL *destination = [root URLByAppendingPathComponent:name isDirectory:YES];
        if ([files fileExistsAtPath:destination.path]) {
            [defaults setBool:YES forKey:key];
            continue;
        }
        NSURL *source = [NSBundle.mainBundle URLForResource:name withExtension:fileName.pathExtension];
        if (!source) continue;
        NSURL *staging = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSError *error = nil;
        BOOL installed = [files createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error] &&
            [files createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:nil error:&error] &&
            [files copyItemAtURL:source toURL:[staging URLByAppendingPathComponent:fileName] error:&error] &&
            [files moveItemAtURL:staging toURL:destination error:&error];
        [files removeItemAtURL:staging error:nil];
        if (installed) [defaults setBool:YES forKey:key];
        else NSLog(@"Cannot install bundled sample %@: %@", fileName, error.localizedDescription);
    }
}

+(void)loadSketches:(void (^)(NSArray<PDESketch*>* sketches))callback {
    if (![self haveSketchesBeenUpdated]) {
        // start update routine
        [self updateFilesToNewFolderStructure];
        if (![self haveSketchesBeenUpdated]) {
            NSLog(@"Error occured while updating to new folder structure.");
        }
    }
    
    [self copySampleProjectsOnFirstStart];
    
    NSMutableArray<PDESketch*>* pdeSketches = [NSMutableArray array];
    NSArray *filePathsArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self documentsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"sketches"]]  error:nil];
    for (NSString* sketchFolder in filePathsArray) {
        NSString* sketchName = [sketchFolder lastPathComponent];
        if (![sketchName isEqualToString:@".DS_Store"]) {
            PDESketch* sketch = [[PDESketch alloc] initWithSketchName:sketchName];
            [pdeSketches addObject:sketch];
        }
    }
    
    NSArray* sortedArray = [pdeSketches sortedArrayUsingComparator:^NSComparisonResult(PDESketch* sketch1, PDESketch* sketch2) {
        return [sketch1.sketchName.lowercaseString compare:sketch2.sketchName.lowercaseString];
    }];
    
    callback(sortedArray);
}

+(void)loadProjects:(void (^)(NSArray<SimpleTextProject *> *))callback {
    
    [self copySampleProjectsOnFirstStart];
    [self installAdditionalSamples];
    
    NSMutableArray<SimpleTextProject*>* projects = [NSMutableArray array];
    
    NSArray *filePathsArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self documentsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"sketches"]]  error:nil];
    
    for (NSString* projectFolder in filePathsArray) {
        
        NSString* projectName = [projectFolder lastPathComponent];
        
        if (![projectName isEqualToString:@".DS_Store"]) {
            
            NSMutableArray* projectFiles = [NSMutableArray arrayWithArray: [[NSFileManager defaultManager] contentsOfDirectoryAtPath: [[SketchController documentsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"sketches/%@", projectFolder]]  error:nil]];
            
            NSString* fileFormat;
            
            for (NSString* projectFile in projectFiles) {
                
                NSString* extension = [projectFile pathExtension];
                
                if ([extension isEqualToString:@"pde"]) {
                    fileFormat = @"pde";
                }
                
                if ([extension isEqualToString:@"js"]) {
                    fileFormat = @"js";
                }
                
                if ([extension isEqualToString:@"txt"]) {
                    fileFormat = @"txt";
                }
            }
            
            if ([fileFormat isEqualToString:@"pde"]) {
                PDEProject* project = [[PDEProject alloc] initWithProjectName:projectFolder importingFiles:@[]];
                [projects addObject:project];
                
            } else if ([fileFormat isEqualToString:@"js"]) {
                
                P5JSProject* project = [[P5JSProject alloc] initWithProjectName:projectFolder importingFiles:@[]];
                [projects addObject:project];
                
            } else if ([fileFormat isEqualToString:@"txt"]) {
                SimpleTextProject* project = [[SimpleTextProject alloc] initWith:projectFolder sourceCodeExtension:@"txt" importingFiles:@[]];
                [projects addObject:project];
            }
        }
    }
    
    NSArray* sortedArray = [projects sortedArrayUsingComparator:^NSComparisonResult(SimpleTextProject* project1, SimpleTextProject* project2) {
        return [project1.name.lowercaseString compare: project2.name.lowercaseString];
    }];
    
    callback(sortedArray);
    
}

+(void)updateFilesToNewFolderStructure {
    NSArray<NSString*>* legacyFiles = [self legacyItemsFromMenuFile];
    for (NSString* legacyFileName in legacyFiles) {
        NSString* currentPath = [[self documentsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.pde", legacyFileName]];
        NSString* movePath =  [[self documentsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"sketches/%@/%@.pde", legacyFileName, legacyFileName]];
        NSString* moveFolder = [[self documentsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"sketches/%@/data", legacyFileName]];
        NSError* error;
        [[NSFileManager defaultManager] createDirectoryAtPath:moveFolder withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] moveItemAtPath:currentPath toPath:movePath error:&error];
        if (error) {
            NSLog(@"Error occured while copying the files: %@",error.description);
        }
    }
    
    NSArray *filePathsArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self documentsDirectory]  error:nil];
    for (NSString* file in filePathsArray) {
        if ([file.pathExtension isEqualToString:@"pde"]) {
            NSString* path = [[self documentsDirectory] stringByAppendingPathComponent:file];
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
    }
}

+(NSArray<NSString*>*)legacyItemsFromMenuFile {
    NSMutableArray* legacyFiles = [[NSMutableArray alloc] init];
    
    NSString *programmCodesPath = [[self documentsDirectory] stringByAppendingPathComponent:@"menu.txt"];
    NSString *programmCodesString = [NSString stringWithContentsOfFile:programmCodesPath encoding:NSUTF8StringEncoding error:NULL];
    
    for(NSString *fileName in [programmCodesString componentsSeparatedByString:@"\n"]) {
        if(![fileName isEqualToString:@""]) {
            [legacyFiles addObject:fileName];
        }
    }
    return legacyFiles.copy;
}

+(BOOL)haveSketchesBeenUpdated {
    NSArray *filePathsArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self documentsDirectory]  error:nil];
    for (NSString* file in filePathsArray) {
        if ([file.pathExtension isEqualToString:@"pde"]) {
            return NO;
        }
    }
    return YES;
}

+(void)deleteSketchWithName:(NSString*)sketchName {
    NSString* path = [[self documentsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"sketches/%@/",sketchName]];
    NSError *error;
    if ([[NSFileManager defaultManager] isDeletableFileAtPath:path]) {
        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
        if (!success) {
            NSLog(@"Error removing file at path: %@", error.localizedDescription);
        }
    }
}

+(void)savePDESketch:(PDESketch*)sketch {
    NSString* sketchPath = [[self documentsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"sketches/%@/data",sketch.sketchName]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:sketchPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:sketchPath withIntermediateDirectories:YES attributes:nil error:nil];
        NSLog(@"Created new folder for new sketch");
    }
}

+(NSString*)documentsDirectory {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsDirectory = [paths objectAtIndex:0];
    NSLog(@"%@",documentsDirectory);
    return documentsDirectory;
}

@end
