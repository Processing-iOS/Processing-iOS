//
//  ProjectSelectionTableViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 5/15/18.
//  Copyright © 2018 Frederik Riedel. All rights reserved.
//

import UIKit
import CoreServices
import MobileCoreServices
import UniformTypeIdentifiers

class ProjectSelectionTableViewController: UITableViewController,
                                           UIViewControllerPreviewingDelegate,
                                           UIAlertViewDelegate {
    
    @IBOutlet weak var projectsCountLabel: UIBarButtonItem!
    private let projectCountView = UILabel()
    
    var projects: [SimpleTextProject]?
    var filteredProjects: [SimpleTextProject]?
    let searchController = UISearchController(searchResultsController: nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("My Projects", comment: "")
        
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Search Projects"
        if #available(iOS 9.1, *) {
            searchController.obscuresBackgroundDuringPresentation = false
        }
        searchController.searchBar.keyboardAppearance = .dark
        searchController.searchBar.tintColor = UIColor.white
        searchController.searchBar.barStyle = .black
        
        tableView.rowHeight = UITableView.automaticDimension
        
        if #available(iOS 13.0, *) {
            let navBarAppearance = UINavigationBarAppearance()
            navBarAppearance.configureWithOpaqueBackground()
            navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            navBarAppearance.backgroundColor = UIColor.processing()
            self.navigationItem.scrollEdgeAppearance = navBarAppearance
            self.navigationItem.standardAppearance = navBarAppearance
        }
        
        if #available(iOS 11.0, *) {
            navigationItem.searchController = searchController
        }
        definesPresentationContext = true
        
        SketchController.loadProjects { (projects) in
            self.projects = projects
            self.tableView.reloadData()
        }
        
        //        SketchController.loadSketches { (projects) in
        //            self.projects = projects
        //            self.tableView.reloadData()
        //        }
        
        projectCountView.font = .systemFont(ofSize: 13, weight: .semibold)
        projectCountView.textColor = .secondaryLabel
        projectsCountLabel.customView = projectCountView
        refreshProjectsCountLabel()
        registerForPreviewing(with: self, sourceView: tableView)
    }
    
    
    @IBAction func importProject(_ sender: UIBarButtonItem) {
        
        let actionSheet = UIAlertController(title: "Import…", message: "Import a file, a project folder, or the bundled sample projects. Existing projects will be kept.", preferredStyle: .actionSheet)
        
        actionSheet.popoverPresentationController?.barButtonItem = sender
        
        let singleFile = UIAlertAction(title: "Import individual file…", style: .default) { _ in
            let documentBrowser = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
            documentBrowser.delegate = self
            documentBrowser.allowsMultipleSelection = true
            self.present(documentBrowser, animated: true)
        }
        
        let projectFolder = UIAlertAction(title: "Import project folder…", style: .default) { _ in
            
            
            let documentBrowser = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            documentBrowser.navigationController?.navigationBar.tintColor = UIColor.processing()
            documentBrowser.delegate = self
            self.present(documentBrowser, animated: true)
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            
        }
        
        actionSheet.addAction(singleFile)
        actionSheet.addAction(projectFolder)
        actionSheet.addAction(UIAlertAction(title: "Import sample projects…", style: .default) { [weak self] _ in
            self?.showSampleProjectPicker()
        })
        actionSheet.addAction(cancel)
        
        self.present(actionSheet, animated: true)
        
    }

    private func showSampleProjectPicker() {
        let picker = SampleProjectPickerViewController { [weak self] fileNames in
            self?.importSampleProjects(fileNames)
        }
        let navigation = ProcessingNavigationViewController(rootViewController: picker)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func importSampleProjects(_ fileNames: [String]) {
        // Clear any search so restored projects are immediately visible.
        searchController.isActive = false
        searchController.searchBar.text = nil
        tableView.setEditing(false, animated: true)
        let editButton = toolbarItems?.first { $0.action == #selector(toggleEditMode(_:)) }
        editButton?.title = "Edit"
        editButton?.style = .plain

        let message: String
        let title: String
        do {
            let imported = try SketchController.importSampleProjects(fileNames)
            title = "Sample Projects"
            if imported.isEmpty {
                message = "The selected sample projects are already available."
            } else {
                let count = imported.count
                message = "Imported \(count) sample \(count == 1 ? "project" : "projects"). Existing projects were kept; fresh copies of edited samples have a numbered name."
            }
        } catch {
            title = "Import Error"
            message = "Some selected samples could not be imported. You can try again.\n\n\(error.localizedDescription)"
        }

        SketchController.loadProjects { projects in
            self.projects = projects
            self.filteredProjects = nil
            self.tableView.reloadData()
            self.refreshProjectsCountLabel()
        }
        let result = UIAlertController(title: title, message: message, preferredStyle: .alert)
        result.addAction(UIAlertAction(title: "OK", style: .default))
        present(result, animated: true)
    }
    
    func refreshProjectsCountLabel() {
        projectCountView.text = "\(projects?.count ?? 0) Projects"
        projectsCountLabel.accessibilityLabel = projectCountView.text
        projectCountView.sizeToFit()
    }
    
    @IBAction func startSearch(_ sender: Any) {
        searchController.searchBar.becomeFirstResponder()
    }

    @IBAction func toggleEditMode(_ sender: UIBarButtonItem) {
        if !tableView.isEditing {
            searchController.isActive = false
            searchController.searchBar.resignFirstResponder()
        }

        let shouldEdit = !tableView.isEditing
        tableView.setEditing(shouldEdit, animated: true)
        sender.title = shouldEdit ? "Done" : "Edit"
        sender.style = shouldEdit ? .done : .plain
    }
    
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isFiltering() {
            if let count = filteredProjects?.count {
                return count
            }
            return 0
        }
        
        if let count = projects?.count {
            return count
        }
        return 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "project-cell", for: indexPath)
                as? ProjectTableViewCell else {
                    fatalError("Misconfigured cell type!")
                }
        
        if isFiltering() {
            if let project = filteredProjects?[indexPath.row] {
                cell.projectNameLabel.text = project.name
            }
            return cell
        }
        
        if let project = projects?[indexPath.row] {
            cell.projectNameLabel.text = project.name
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            
            cell.creationDateLabel.text = "Created: \(dateFormatter.string(from: project.creationDate))"
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 66
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 20
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if isFiltering() {
            return false
        }
        return true
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            if let project = projects?[indexPath.row] {
                
                let alertController = UIAlertController(
                    title: "Delete Project",
                    message: "Are you sure that you want to delete the project \"\(project.name)\"? " +
                    "This cannot be undone.",
                    preferredStyle: .alert)
                
                let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { (_) in
                    SketchController.deleteSketch(withName: project.name)
                    
                    SketchController.loadProjects { (projects) in
                        self.projects = projects
                        self.tableView.deleteRows(at: [indexPath], with: .automatic)
                        self.refreshProjectsCountLabel()
                    }
                }
                alertController.addAction(deleteAction)
                
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
                    
                }
                alertController.addAction(cancelAction)
                
                present(alertController, animated: true)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            return
        }

        var currentProjects = projects
        if isFiltering() {
            currentProjects = filteredProjects
        }
        
        if let project = currentProjects?[indexPath.row] {
            let editor = EditorTabViewController(withProject: project)
            //            let editor = PDEEditorViewController(pdeSketch: project)!
            navigationController?.pushViewController(editor, animated: true)
        }
    }
    
    
    @IBAction func about(_ sender: Any) {
        let aboutVC = AboutViewController(nibName: "AboutViewController", bundle: .main)
        let navC = UINavigationController(rootViewController: aboutVC)
        navC.modalPresentationStyle = .formSheet
        self.navigationController?.present(navC, animated: true, completion: nil)
    }
    
    @IBAction func createNewProject(_ sender: UIBarButtonItem) {
        
        //        self.showCreateAlert(title: "New Processing Project", name: "")
        
        guard let button = sender.value(forKey: "view") as? UIView else {
            return
        }
        
        let actionSheet = UIAlertController(title: "Create a new Project", message: "This app supports working with Processing (.pde) and P5.js (.js) project files.", preferredStyle: .actionSheet)
        
        actionSheet.modalPresentationStyle = .popover
        
        
        let processing = UIAlertAction(title: "New Processing Project", style: .default) { (_) in
            self.showCreateAlert(title: "New Processing Project", name: "")
        }
        
        let p5js = UIAlertAction(title: "New P5.js Project", style: .default) { (_) in
            self.showCreateAlert(title: "New P5.js Project", name: "", type: "js")
        }
        
        let importButton = UIAlertAction(title: "Import Project…", style: .default) { (_) in
            self.importProject(sender)
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            
        }
        
        actionSheet.addAction(processing)
        actionSheet.addAction(p5js)
        actionSheet.addAction(importButton)
        actionSheet.addAction(cancel)
        
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = button
        }
        
        present(actionSheet, animated: true)
    }
    
    
    private func showImportError(error: String) {
        let alert = UIAlertController(title: "Import Error", message: error, preferredStyle: .alert)
        
        let ok = UIAlertAction(title: "Ok", style: .cancel) { (_) in
            
        }
        
        alert.addAction(ok)
        
        present(alert, animated: true)
    }
    
    
    func importSingleFile(file: URL) {
        let fileType = file.pathExtension
        let fileName = file.lastPathComponent.replacingOccurrences(of: ".\(fileType)", with: "")
        showCreateAlert(title: "Import Project", name: fileName, type: fileType, importingFiles: [file])
    }
    
    func importProjectFolder(folder: URL) {
        importSources([folder])
    }

    private func importSources(_ urls: [URL]) {
        guard let first = urls.first else { return }
        do {
            let language = try ProjectFiles.language(in: urls)
            let name = try ProjectFiles.read(first) { $0.isDirectory ? $0.lastPathComponent : $0.deletingPathExtension().lastPathComponent }
            showCreateAlert(title: "Import Project", name: name.replacingOccurrences(of: " ", with: "_"), type: language, importingFiles: urls)
        } catch { showImportError(error: error.localizedDescription) }
    }

    func showCreateAlert(title: String, name: String, type: String = "pde", importingFiles: [URL] = []) {
        
        let alertController = UIAlertController(title: title, message: "", preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
            alertController.dismiss(animated: true, completion: nil)
        }))
        
        alertController.addAction(createAlertAction(alertController: alertController, type: type, importingFiles: importingFiles))
        
        alertController.addTextField(configurationHandler: { (textField) -> Void in
            textField.textAlignment = .left
            textField.text = name
        })
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    func createAlertAction(alertController: UIAlertController, type: String, importingFiles: [URL]) -> UIAlertAction {
        return UIAlertAction(title: "Create", style: .default, handler: { (_) in
            if let fileName = alertController.textFields?[0].text {
                var letters = CharacterSet.letters
                letters.formUnion(CharacterSet(charactersIn: "-_1234567890"))
                
                var message = ""
                var suggestedName = fileName
                if fileName == "" {
                    message = "Name should be at least one character"
                } else if self.nameAlreadyExists(name: fileName) {
                    message = "File with name '\(fileName)' already exists. " +
                    "Please choose another name or delete the exiting one first."
                } else if fileName.contains(" ") {
                    message = "File name should not contain spaces."
                    suggestedName = fileName.replacingOccurrences(of: " ", with: "_")
                } else if !letters.isSuperset(of: CharacterSet(charactersIn: fileName)) {
                    message = "File name should contain no fancy symbols."
                } else {
                    
                    if type == "pde" {
                        self.createNewProcessingProject(name: fileName, importingFiles: importingFiles)
                    } else if type == "js" {
                        self.createNewP5JSProject(name: fileName, importingFiles: importingFiles)
                    }
                    
                    return
                }
                
                self.showCreateAlert(title: message, name: suggestedName, type: type, importingFiles: importingFiles)
            }
        })
    }
    
    private func createNewProcessingProject(name: String, importingFiles: [URL]) {
        createProject(name: name, language: "pde", importingFiles: importingFiles)
    }

    private func createNewP5JSProject(name: String, importingFiles: [URL]) {
        createProject(name: name, language: "js", importingFiles: importingFiles)
    }

    private func createProject(name: String, language: String, importingFiles: [URL]) {
        let progress = UIAlertController(title: importingFiles.isEmpty ? "Creating Project…" : "Importing Project…",
            message: "Preparing your files.", preferredStyle: .alert)
        present(progress, animated: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let project = language == "pde" ? PDEProject(withProjectName: name, importingFiles: importingFiles)
                : P5JSProject(withProjectName: name, importingFiles: importingFiles)
            DispatchQueue.main.async {
                progress.dismiss(animated: true) {
                    if let error = project.initializationError { self.showImportError(error: error.localizedDescription) }
                    else { self.selectNewSketch(withName: project.name) }
                }
            }
        }
    }

    private func selectNewSketch(withName name: String) {
        
        SketchController.loadProjects { (projects) in
            self.projects = projects
            self.tableView.reloadData()
            self.refreshProjectsCountLabel()
            
            let index = projects?.enumerated().reduce(nil, { (result, enumerator) -> Int? in
                if name == enumerator.element.name {
                    return enumerator.offset
                }
                
                return result
            })
            
            if let index = index {
                self.tableView.selectRow(
                    at: IndexPath(row: index, section: 0),
                    animated: true,
                    scrollPosition: .middle
                )
            }
            
        }
        
        
    }
    
    
    private func nameAlreadyExists(name: String) -> Bool {
        for project in projects ?? [] where project.name == name {
            return true
        }
        return false
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing,
                           viewControllerForLocation location: CGPoint) -> UIViewController? {
        
        
        if let indexPath = tableView.indexPathForRow(at: location) {
            let cell = tableView.cellForRow(at: indexPath)
            previewingContext.sourceRect = (cell?.frame)!
            
            let project: SimpleTextProject
            if isFiltering() {
                project = filteredProjects![indexPath.row]
            } else {
                project = projects![indexPath.row]
            }
            let editor = EditorTabViewController(withProject: project)
            return editor
        }
        
        return nil
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing,
                           commit viewControllerToCommit: UIViewController) {
        navigationController?.pushViewController(viewControllerToCommit, animated: false)
        
    }
    
    private func searchBarIsEmpty() -> Bool {
        // Returns true if the text is empty or nil
        return searchController.searchBar.text?.isEmpty ?? true
    }
    
    func filterContentForSearchText(_ searchText: String, scope: String = "All") {
        filteredProjects = projects?.filter({ (project) -> Bool in
            return project.name.lowercased().contains(searchText.lowercased())
        })
        
        tableView.reloadData()
    }
    
    private func isFiltering() -> Bool {
        return searchController.isActive && !searchBarIsEmpty()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

extension ProjectSelectionTableViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text!)
    }
}

extension ProjectSelectionTableViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importSources(urls)
    }
}
