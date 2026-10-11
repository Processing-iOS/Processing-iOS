import Foundation

/// Persist the permission-bearing bookmark, never just an external filesystem path.
@objc final class LinkedProjects: NSObject {
    private struct Link: Codable {
        let id: String
        let name: String
        let language: String
        let mainFile: String?
        var bookmark: Data
    }
    private static let key = "linkedProjectFolders"

    private static func saved() -> [Link] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Link].self, from: data)) ?? []
    }

    private static func store(_ links: [Link]) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(links), forKey: key)
    }

    static func open(_ folder: URL) throws -> SimpleTextProject {
        let language = try ProjectFiles.language(in: [folder])
        return try ProjectFiles.read(folder) { local in
            let bookmark = try local.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            var links = saved()
            var existingID: String?
            for link in links {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: link.bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale),
                   url.standardizedFileURL.path == local.standardizedFileURL.path { existingID = link.id }
            }
            let project = SimpleTextProject(folder: local, name: local.lastPathComponent, language: language,
                linkedIdentifier: existingID ?? UUID().uuidString)
            let main = try project.sourceFileURLs().first?.lastPathComponent
            let link = Link(id: project.linkedIdentifier!, name: project.name, language: language, mainFile: main, bookmark: bookmark)
            links.removeAll { $0.id == link.id }
            links.append(link)
            try store(links)
            project.preferredMainFileName = main
            return project
        }
    }

    @objc static func projects() -> [SimpleTextProject] {
        var links = saved()
        var refreshed = false
        let projects = links.indices.map { index -> SimpleTextProject in
            let link = links[index]
            do {
                var stale = false
                let folder = try URL(resolvingBookmarkData: link.bookmark, options: .withoutUI,
                    relativeTo: nil, bookmarkDataIsStale: &stale)
                let project = SimpleTextProject(folder: folder, name: folder.lastPathComponent,
                    language: link.language, linkedIdentifier: link.id)
                project.preferredMainFileName = link.mainFile
                if stale, let bookmark = try? folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    links[index].bookmark = bookmark
                    refreshed = true
                }
                return project
            } catch {
                // Keep inaccessible links visible so users can reconnect or remove
                // them; never mistake a local project with the same name for it.
                let unavailable = FileManager.default.temporaryDirectory.appendingPathComponent("UnavailableLink-\(link.id)")
                return SimpleTextProject(folder: unavailable, name: link.name, language: link.language,
                    linkedIdentifier: link.id, accessError: NSError(domain: "LinkedProject", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "This folder is unavailable. Reopen it using Import → Open Folder from Files, or remove this link."]))
            }
        }
        if refreshed { try? store(links) }
        return projects
    }

    static func remove(_ project: SimpleTextProject) throws {
        guard let id = project.linkedIdentifier else { return }
        try store(saved().filter { $0.id != id })
    }
}
