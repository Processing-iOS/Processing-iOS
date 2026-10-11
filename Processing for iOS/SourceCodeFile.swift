//
//  JSFile.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/11/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import Foundation

struct SourceRevision: Codable {
    let date: Date
    let content: String
}

@objc class SourceCodeFile: NSObject {
    
    @objc var filePath: String
    @objc var content: String?
    @objc private(set) var readError: NSError?
    @objc private(set) var saveError: NSError?
    @objc private(set) var hasUnsavedChanges = false
    private var pendingSave: DispatchWorkItem?
    private var lastSavedContent: String?
    private var lastSaveDate = Date()
    private var latestCheckpoint: SourceRevision?
    private var loadedCheckpoint = false
    static let didChange = Notification.Name("SourceCodeFileDidChange")
    
    init(filePath: String) {
        self.filePath = filePath
        do {
            self.content = try String(contentsOfFile: filePath, encoding: .utf8)
            self.lastSavedContent = self.content
        } catch {
            self.readError = error as NSError
        }
    }

    // Keep the shared file buffer current even when Pageboy discards an editor.
    @objc func updateContent(_ text: String) {
        guard content != text else { return }
        content = text
        hasUnsavedChanges = true
        pendingSave?.cancel()
        NotificationCenter.default.post(name: Self.didChange, object: self)
        if Date().timeIntervalSince(lastSaveDate) >= 2 {
            save()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.save() }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private var historyFolder: URL {
        URL(fileURLWithPath: filePath).deletingLastPathComponent()
            .appendingPathComponent(".processing-history", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: true)
    }

    func history() throws -> [SourceRevision] {
        guard FileManager.default.fileExists(atPath: historyFolder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: historyFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SourceRevision.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    private func checkpoint(_ text: String, force: Bool = false) throws {
        if !loadedCheckpoint {
            latestCheckpoint = try history().first
            loadedCheckpoint = true
        }
        let previous = latestCheckpoint
        guard previous?.content != text else { return }
        // Keep the beginning of each editing interval, rather than filling the
        // history with every keystroke. Explicit restores always preserve a copy.
        if !force, let previous, Date().timeIntervalSince(previous.date) < 30 { return }
        try FileManager.default.createDirectory(at: historyFolder, withIntermediateDirectories: true)
        let revision = SourceRevision(date: Date(), content: text)
        let url = historyFolder.appendingPathComponent("\(revision.date.timeIntervalSince1970)-\(UUID().uuidString).json")
        try JSONEncoder().encode(revision).write(to: url, options: .atomic)
        latestCheckpoint = revision
        let files = try FileManager.default.contentsOfDirectory(at: historyFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(100) { try? FileManager.default.removeItem(at: old) }
    }

    func restore(_ revision: SourceRevision) throws {
        guard save() else { throw saveError! }
        if let content { try checkpoint(content, force: true) }
        guard save(newContent: revision.content) else { throw saveError! }
    }
    
    @objc var fileName: String {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    @objc var fileExtension: String {
        return URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }
    
    @discardableResult
    @objc func save(newContent: String? = nil) -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        if let newContent = newContent {
            hasUnsavedChanges = hasUnsavedChanges || content != newContent
            self.content = newContent
        }
        defer { NotificationCenter.default.post(name: Self.didChange, object: self) }
        if !hasUnsavedChanges, saveError == nil, readError == nil, content == lastSavedContent { return true }
        do {
            guard let content = content else {
                throw readError ?? NSError(domain: "SketchSource", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot read \(fileName)."])
            }
            let exists = FileManager.default.fileExists(atPath: filePath)
            let stored = exists ? try String(contentsOfFile: filePath, encoding: .utf8) : nil
            if stored != content {
                if let stored { try checkpoint(stored) }
                try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            }
            lastSavedContent = content
            lastSaveDate = Date()
            hasUnsavedChanges = false
            saveError = nil
            readError = nil
            return true
        } catch {
            saveError = error as NSError
            hasUnsavedChanges = true
            return false
        }
    }
}
