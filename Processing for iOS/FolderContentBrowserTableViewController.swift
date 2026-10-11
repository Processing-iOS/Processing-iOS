//
//  FolderContentBrowserTableViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 5/13/18.
//  Copyright © 2018 Frederik Riedel. All rights reserved.
//

import UIKit
import CoreServices
import UniformTypeIdentifiers

class FolderContentBrowserTableViewController: UITableViewController, UIDocumentPickerDelegate {

    var contents: [String]
    let basePath: String
    let currentPath: String
    private var projectSharing: ProjectSharing?

    init(withPath path: String, basePath: String) {
        self.basePath = basePath
        currentPath = path
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: path).filter { !$0.hasPrefix(".") && !$0.hasPrefix("__runtime_") }.sorted()
        } catch _ {
            contents = []
        }

        super.init(nibName: "FolderContentBrowserTableViewController", bundle: Bundle.main)
        title = "Folder Contents"
    }

    private func reload() {
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: currentPath).filter { !$0.hasPrefix(".") && !$0.hasPrefix("__runtime_") }.sorted()
        } catch _ {
            contents = []
        }

        tableView.reloadData()
    }

    required init(coder decoder: NSCoder) {
        contents = Array()
        basePath = ""
        currentPath = ""
        super.init(coder: decoder)!
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(
            UINib.init(nibName: "FileContentTableViewCell", bundle: Bundle.main),
            forCellReuseIdentifier: "file-cell")
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(FolderContentBrowserTableViewController.done)
            )
        ]

        self.navigationController?.setToolbarHidden(false, animated: false)
        let importToolbarItem = UIBarButtonItem(
            title: "Import…",
            style: .plain,
            target: self,
            action: #selector(FolderContentBrowserTableViewController.importFiles)
        )
        let editToolbarItem = UIBarButtonItem(
            barButtonSystemItem: .edit,
            target: self,
            action: #selector(FolderContentBrowserTableViewController.toggleEdit)
        )

        let exportToolbarItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareFolder(_:))
        )
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        self.toolbarItems = [importToolbarItem, flexibleSpace, exportToolbarItem, flexibleSpace, editToolbarItem]
    }

    @objc func done() {
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func shareFolder(_ sender: UIBarButtonItem) {
        let folder = URL(fileURLWithPath: currentPath)
        projectSharing = ProjectSharing(folder: folder, name: folder.lastPathComponent, presenter: self)
        projectSharing?.present(from: sender)
    }

    @objc func toggleEdit() {
        tableView.setEditing(!tableView.isEditing, animated: true)
    }

    @objc func importFiles() {
        if #available(iOS 11.0, *) {
            UINavigationBar.appearance(whenContainedInInstancesOf: [UIDocumentBrowserViewController.self])
                .tintColor = nil
        }
        let filePickerViewController = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        filePickerViewController.delegate = self
        filePickerViewController.allowsMultipleSelection = true
        filePickerViewController.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(filePickerViewController, animated: true, completion: nil)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contents.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "file-cell", for: indexPath)
            as? FileContentTableViewCell else {
                fatalError("Misconfigured cell type!")
        }

        let path = "\(currentPath)/\(contents[indexPath.row])"
        cell.fileTypeNameLabel.text = contents[indexPath.row]

        var directory: ObjCBool = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
        if exists && directory.boolValue {
            cell.fileTypeIcon.image = UIImage(named: "folder_icon")
        } else {
            cell.fileTypeIcon.image = UIImage(named: "pde-file-icon")
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let source = URL(fileURLWithPath: currentPath).appendingPathComponent(contents[indexPath.row])
        let rename = UIContextualAction(style: .normal, title: "Rename") { [weak self] _, _, done in
            self?.nameFile(source, duplicate: false); done(true)
        }
        let duplicate = UIContextualAction(style: .normal, title: "Duplicate") { [weak self] _, _, done in
            self?.nameFile(source, duplicate: true); done(true)
        }
        rename.backgroundColor = .systemBlue
        duplicate.backgroundColor = .systemIndigo
        let actions = UISwipeActionsConfiguration(actions: [rename, duplicate])
        actions.performsFirstActionWithFullSwipe = false
        return actions
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let source = URL(fileURLWithPath: currentPath).appendingPathComponent(contents[indexPath.row])
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in self?.nameFile(source, duplicate: false) },
                UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { _ in self?.nameFile(source, duplicate: true) }
            ])
        }
    }

    private func nameFile(_ source: URL, duplicate: Bool) {
        let title = duplicate ? "Duplicate File" : "Rename File"
        let alert = UIAlertController(title: title, message: duplicate && ["js", "pde"].contains(source.pathExtension.lowercased())
            ? "The copy contains the same code. Give any copied classes or functions unique names before running." : nil, preferredStyle: .alert)
        alert.addTextField {
            $0.text = duplicate ? source.deletingPathExtension().lastPathComponent + " Copy" + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension) : source.lastPathComponent
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: duplicate ? "Duplicate" : "Rename", style: .default) { [weak self] _ in
            guard let self, let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            let folder = URL(fileURLWithPath: self.basePath)
            FileOperationProgress.perform(title: duplicate ? "Duplicating File…" : "Renaming File…", from: self, work: {
                if duplicate { try ProjectFiles.duplicateFile(source, as: name, projectFolder: folder) }
                else { try ProjectFiles.renameFile(source, to: name, projectFolder: folder) }
            }) { error in
                if let error { self.showError(error) }
                else { self.reload() }
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let path = "\(currentPath)/\(contents[indexPath.row])"
            do {
                try ProjectFiles.write(URL(fileURLWithPath: basePath), options: []) { _ in
                    try FileManager.default.removeItem(atPath: path)
                }
                NotificationCenter.default.post(name: ProjectFiles.didChange, object: URL(fileURLWithPath: basePath))
                reload()
            } catch { showError(error) }
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let path = "\(currentPath)/\(contents[indexPath.row])"
        var directory: ObjCBool = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
        if exists && directory.boolValue {
            // open new folder content
            let dataFolderVC = FolderContentBrowserTableViewController(
                withPath: URL(fileURLWithPath: currentPath).appendingPathComponent(contents[indexPath.row]).path,
                basePath: basePath)
            navigationController?.pushViewController(dataFolderVC, animated: true)
        } else {
            // open file inspector
            let fileViewer = MultiFileViewController()
            fileViewer.fileURL = URL(fileURLWithPath: path)
            navigationController?.pushViewController(fileViewer, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        do {
            try ProjectFiles.importFiles(urls, into: URL(fileURLWithPath: basePath))
            reload()
            if urls.contains(where: { !["pde", "js"].contains($0.pathExtension.lowercased()) }),
               URL(fileURLWithPath: currentPath).lastPathComponent != "data" {
                let data = FolderContentBrowserTableViewController(
                    withPath: URL(fileURLWithPath: basePath).appendingPathComponent("data").path, basePath: basePath)
                navigationController?.pushViewController(data, animated: true)
            }
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "File Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}


extension FileManager {
    static func ensureFolderExists(folderPath: String) {
        if !FileManager.default.fileExists(atPath: folderPath) {
            try? FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
        }
    }
}
