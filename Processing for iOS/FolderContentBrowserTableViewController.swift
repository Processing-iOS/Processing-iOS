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
            action: #selector(FolderContentBrowserTableViewController.importFiles)
        )
        exportToolbarItem.isEnabled = false
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        self.toolbarItems = [importToolbarItem, flexibleSpace, exportToolbarItem, flexibleSpace, editToolbarItem]
    }

    @objc func done() {
        self.dismiss(animated: true, completion: nil)
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

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let path = "\(currentPath)/\(contents[indexPath.row])"
            do {
                try FileManager.default.removeItem(atPath: path)
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
