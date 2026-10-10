//
//  Project.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/15/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import Foundation

@objc class SimpleTextProject: NSObject {
    
    @objc var name: String
    @objc var sourceCodeExtension: String
    
    @objc init(with name: String, sourceCodeExtension: String, importingFiles: [URL] = []) {
        
        self.name = name
        self.sourceCodeExtension = sourceCodeExtension
        
        super.init()
        
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(atPath: folder.path, withIntermediateDirectories: true, attributes: nil)
            
            if importingFiles.isEmpty {
                let startFile = SourceCodeFile(filePath: folder.appendingPathComponent("\(name).\(sourceCodeExtension)").path)
                startFile.save(newContent: self.emptyFile)
            }
            
        } else {
            print("already exists: \(folder.lastPathComponent)")
        }
        
        
        importingFiles.forEach { (url) in
            url.startAccessingSecurityScopedResource()
            
            if url.isDirectory {
                try! FileManager.default.removeItem(at: folder)
                try! FileManager.default.copyItem(at: url, to: folder)
            } else {
                let content = try? String(contentsOf: url)
                let startFile = SourceCodeFile(filePath: folder.appendingPathComponent(url.lastPathComponent).path)
                startFile.save(newContent: content)
            }
            
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    @objc var folder: URL {
        let docDir = URL(fileURLWithPath: SketchController.documentsDirectory())
        let sketchPath = docDir.appendingPathComponent("sketches/\(self.name)")
        return sketchPath
    }
    
    func sourceFileURLs() throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { $0.pathExtension == sourceCodeExtension }
        let mainName = "\(name).\(sourceCodeExtension)"
        return files.sorted {
            if $0.lastPathComponent == mainName && $1.lastPathComponent != mainName { return true }
            if $1.lastPathComponent == mainName { return false }
            return $0.lastPathComponent < $1.lastPathComponent
        }
    }

    @objc var sourceCodeFiles: [SourceCodeFile] {
        (try? sourceFileURLs())?.map { SourceCodeFile(filePath: $0.path) } ?? []
    }

    @objc func prepareRuntime() throws -> SketchProgram {
        try SketchProgram(project: self)
    }

    var emptyFile: String {
        return ""
    }
    
    var creationDate: Date {
        if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: folder.path) {
            return fileAttrs[FileAttributeKey.creationDate] as! Date
        } else {
            return Date()
        }
    }
    
    func createNewFile(withName name: String, content: String? = nil) {
        let newFile = SourceCodeFile(filePath: folder.appendingPathComponent("\(name).\(sourceCodeExtension)").path)
        if let content = content {
            newFile.save(newContent: content)
        } else {
            newFile.save(newContent: emptyFile)
        }
        
    }
    
}

extension URL {
    var isDirectory: Bool {
       return (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
