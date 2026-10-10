//
//  JSFile.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/11/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import Foundation

@objc class SourceCodeFile: NSObject {
    
    @objc var filePath: String
    @objc var content: String?
    @objc private(set) var readError: NSError?
    @objc private(set) var saveError: NSError?
    
    init(filePath: String) {
        self.filePath = filePath
        do {
            self.content = try String(contentsOfFile: filePath, encoding: .utf8)
        } catch {
            self.readError = error as NSError
        }
    }
    
    @objc var fileName: String {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    @objc var fileExtension: String {
        return URL(fileURLWithPath: filePath).pathExtension
    }
    
    @discardableResult
    @objc func save(newContent: String? = nil) -> Bool {
        if let newContent = newContent { self.content = newContent }
        do {
            guard let content = content else {
                throw readError ?? NSError(domain: "SketchSource", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot read \(fileName)."])
            }
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            saveError = nil
            readError = nil
            return true
        } catch {
            saveError = error as NSError
            return false
        }
    }
}
