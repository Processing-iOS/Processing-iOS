//
//  ProjectSelectionTableViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 5/15/18.
//  Copyright © 2018 Frederik Riedel. All rights reserved.
//

import UIKit
import CoreServices
import FredKitStore
import SwiftyStoreKit
import FredKitAnalytics

class ProjectSelectionTableViewController: UITableViewController,
                                           UIViewControllerPreviewingDelegate,
                                           UIAlertViewDelegate {
    
    @IBOutlet weak var projectsCountLabel: UIBarButtonItem!
    
    var projects: [SimpleTextProject]?
    var filteredProjects: [SimpleTextProject]?
    let searchController = UISearchController(searchResultsController: nil)
    
    var adType: Benefit = .export
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        FredKitAnalytics.trackViewController(viewControllerIds: ["Overview"])
        
        self.title = NSLocalizedString("My Projects", comment: "")
        
        if Int.random(in: (0...1)) == 1 {
            adType = .codeFix
        }
        
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Search Projects"
        if #available(iOS 9.1, *) {
            searchController.obscuresBackgroundDuringPresentation = false
        }
        searchController.searchBar.keyboardAppearance = .dark
        searchController.searchBar.tintColor = UIColor.white
        searchController.searchBar.barStyle = .black
        
        tableView.rowHeight = UITableViewAutomaticDimension
        
        tableView.register(ProVersionTableViewCell.nib, forCellReuseIdentifier: "ProVersionTableViewCell")
        
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
        
        refreshProjectsCountLabel()
        projectsCountLabel.isEnabled = false
        projectsCountLabel.setTitleTextAttributes(
            [NSAttributedStringKey.font: UIFont.systemFont(ofSize: 13)],
            for: .disabled
        )
        registerForPreviewing(with: self, sourceView: tableView)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeSubscriptionStatus),
            name: NSNotification.Name(rawValue: "upgradedToPro"),
            object: nil
        )
    }
    
    
    @IBAction func importProject(_ sender: UIBarButtonItem) {
        
        let actionSheet = UIAlertController(title: "Import…", message: "Would you like to import a project folder or an individual file?", preferredStyle: .actionSheet)
        
        actionSheet.popoverPresentationController?.barButtonItem = sender
        
        let singleFile = UIAlertAction(title: "Import individual file…", style: .default) { _ in
            let documentBrowser = UIDocumentPickerViewController(documentTypes: ["public.txt", "public.js", "io.frogg.processing.pde", ], in: .open)
            documentBrowser.delegate = self
            self.present(documentBrowser, animated: true)
        }
        
        let projectFolder = UIAlertAction(title: "Import project folder…", style: .default) { _ in
            
            let documentBrowser = UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String], in: .open)
            documentBrowser.navigationController?.navigationBar.tintColor = .processing()
            documentBrowser.delegate = self
            self.present(documentBrowser, animated: true)
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            
        }
        
        actionSheet.addAction(singleFile)
        actionSheet.addAction(projectFolder)
        actionSheet.addAction(cancel)
        
        self.present(actionSheet, animated: true)
        
    }
    
    @objc func didChangeSubscriptionStatus() {
        tableView.reloadSections([0], with: .automatic)
    }
    
    func refreshProjectsCountLabel() {
        if let numberOfProjects = projects?.count {
            projectsCountLabel.title = "\(numberOfProjects) Projects"
        } else {
            projectsCountLabel.title = "0 Projects"
        }
    }
    
    @IBAction func startSearch(_ sender: Any) {
        searchController.searchBar.becomeFirstResponder()
    }
    
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if section == 0 {
            
            if FredKitSubscriptionManager.shared.shouldShowUpgradeAd {
                return 1
            }

            return 0
        }
        
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
        
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProVersionTableViewCell", for: indexPath)
            
            return cell
        }
        
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
        
        if indexPath.section == 0 {
            return UITableViewAutomaticDimension
        }
        
        return 66
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 20
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        
        if indexPath.section == 0 {
            return false
        }
        
        if isFiltering() {
            return false
        }
        return true
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle,
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
        
        if indexPath.section == 0 {
//            tableView.deselectRow(at: indexPath, animated: true)
//            
//            let proBenefistVC = ProBenefitsViewController()
//            proBenefistVC.shownBenefits = adType
//            let navC = UINavigationController(rootViewController: proBenefistVC)
//            navC.modalPresentationStyle = .formSheet
//            
//            self.present(navC, animated: true)
            
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
        let aboutVC = FredKitAboutViewController.defaultViewController
        
        
        aboutVC.inAppPurchaseCells = [
            InAppPurchaseCell(title: "Tip", subtitle: "Recommended for students and private use.", productID: "io.frogg.processing.tier1"),
            InAppPurchaseCell(title: "Tip", subtitle: "Recommended for professionals and organisations.", productID: "io.frogg.processing.tier2")
        ]
        
        if #available(iOS 13.0, *) {
            aboutVC.additionalAppLinks = [
                WebLinkCell(title: "Telegram Group", url: "https://t.me/processing_ios", icon: UIImage(systemName: "bubble.left.fill"))
            ]
        }
        
        aboutVC.modalTransitionStyle = .coverVertical
        aboutVC.modalPresentationStyle = .formSheet
        
        self.navigationController?.present(aboutVC.wrappedInNavigationController, animated: true, completion: nil)
    }
    
    func showTipSuccessfulAlert() {
        let alert = UIAlertController(title: "Thank you ❤️", message: "Thanks a lot for your support, this is very much appreciated. Enjoy the app!\n\n– Frederik", preferredStyle: .alert)
        let continueButton = UIAlertAction(title: "Continue", style: .default) { _ in
            
        }
        alert.addAction(continueButton)
        self.present(alert, animated: true)
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
        // todo import js as well
        let fileType = "pde"
        let fileName = folder.lastPathComponent
        showCreateAlert(title: "Import Project", name: fileName, type: fileType, importingFiles: [folder])
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
                let letters = NSMutableCharacterSet.letters as? NSMutableCharacterSet
                letters?.addCharacters(in: "-_1234567890")
                
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
                } else if !(letters?.isSuperset(of: CharacterSet.init(charactersIn: fileName)))! {
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
        // filename is correct
        let newProject = PDEProject(withProjectName: name, importingFiles: importingFiles)
        selectNewSketch(withName: newProject.name)
    }
    
    private func createNewP5JSProject(name: String, importingFiles: [URL]) {
        // filename is correct
        let newProject = P5JSProject(withProjectName: name, importingFiles: importingFiles)
        selectNewSketch(withName: newProject.name)
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
                    at: IndexPath(row: index, section: 1),
                    animated: true,
                    scrollPosition: .middle
                )
            }
            
        }
        
        
    }
    
    
    private func nameAlreadyExists(name: String) -> Bool {
        for project in projects! where project.name == name {
            return true
        }
        return false
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing,
                           viewControllerForLocation location: CGPoint) -> UIViewController? {
        
        
        if let indexPath = tableView.indexPathForRow(at: location) {
            
            if indexPath.section == 0 {
                return nil
            }
            
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
        
        
        if let selectedUrl = urls.first {
            selectedUrl.startAccessingSecurityScopedResource()
            if selectedUrl.isDirectory {
                self.importProjectFolder(folder: selectedUrl)
                selectedUrl.stopAccessingSecurityScopedResource()
                return
            } else {
                self.importSingleFile(file: selectedUrl)
                selectedUrl.stopAccessingSecurityScopedResource()
            }
            
        }
    }
}




