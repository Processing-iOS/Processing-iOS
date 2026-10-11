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
    
    @objc private(set) var initializationError: NSError?
    private var folderOverride: URL?
    private var accessingFolder = false
    var linkedIdentifier: String?
    var preferredMainFileName: String?
    @objc var isLinked: Bool { linkedIdentifier != nil }

    init(folder: URL, name: String, language: String, linkedIdentifier: String? = nil, accessError: NSError? = nil) {
        self.name = name
        sourceCodeExtension = language
        folderOverride = folder
        self.linkedIdentifier = linkedIdentifier
        initializationError = accessError
        super.init()
        if linkedIdentifier != nil, accessError == nil { accessingFolder = folder.startAccessingSecurityScopedResource() }
    }

    deinit { if accessingFolder { folderOverride?.stopAccessingSecurityScopedResource() } }

    @objc init(with name: String, sourceCodeExtension: String, importingFiles: [URL] = []) {
        self.name = name
        self.sourceCodeExtension = sourceCodeExtension
        super.init()
        do {
            try ProjectFiles.validateName(name)
            if !importingFiles.isEmpty {
                try ProjectFiles.importProject(importingFiles, to: folder, language: sourceCodeExtension)
            } else if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try emptyFile.write(to: folder.appendingPathComponent("\(name).\(sourceCodeExtension)"), atomically: true, encoding: .utf8)
            }
        } catch {
            initializationError = error as NSError
        }
    }

    @objc var folder: URL {
        if let folderOverride { return folderOverride }
        let docDir = URL(fileURLWithPath: SketchController.documentsDirectory())
        let sketchPath = docDir.appendingPathComponent("sketches/\(self.name)")
        return sketchPath
    }
    
    func sourceFileURLs() throws -> [URL] {
        if let initializationError { throw initializationError }
        let files = try ProjectFiles.read(folder) { local in
            try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { try $0.pathExtension.lowercased() == sourceCodeExtension && $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
        }
        let mainName = preferredMainFileName ?? "\(name).\(sourceCodeExtension)"
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
            return fileAttrs[FileAttributeKey.creationDate] as? Date ?? Date()
        } else {
            return Date()
        }
    }
    
    func createNewFile(withName name: String, content: String? = nil) throws {
        try ProjectFiles.validateName(name)
        let url = folder.appendingPathComponent("\(name).\(sourceCodeExtension)")
        try ProjectFiles.write(folder, options: []) { _ in
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw ProjectFileError(message: "A file with this name already exists.")
            }
            try (content ?? emptyFile).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    
}

extension URL {
    var isDirectory: Bool {
       return (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
