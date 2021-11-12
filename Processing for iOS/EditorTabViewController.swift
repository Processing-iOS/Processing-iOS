//
//  EditorTabViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 5/16/18.
//  Copyright © 2018 Frederik Riedel. All rights reserved.
//

import UIKit
import Tabman
import Pageboy
import SafariServices
import FredKitStore
import FredKitAnalytics

class EditorTabViewController: TabmanViewController, PageboyViewControllerDataSource {
    
    let project: SimpleTextProject!
    
    init(withProject project: SimpleTextProject) {
        self.project = project
        super.init(nibName: "EditorTabViewController", bundle: Bundle.main)
        self.automaticallyAdjustsChildScrollViewInsets = true
        self.dataSource = self
        
        
        
//        ExternalScreenController.showSketch(project: project)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.bar.style = .scrollingButtonBar
        
        self.title = self.project.name
        
        let runButton = UIBarButtonItem(
            barButtonSystemItem: .play,
            target: self,
            action: #selector(EditorTabViewController.runSketch)
        )
        let addNewPDEFile = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(EditorTabViewController.addNewPDEFile)
        )
        let shareButton = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(EditorTabViewController.share)
        )
        self.navigationItem.rightBarButtonItems = [runButton, addNewPDEFile, shareButton]
        
        let formatButton = UIBarButtonItem(
            title: NSLocalizedString("Format Code", comment: ""),
            style: .plain,
            target: self,
            action: #selector(EditorTabViewController.formatCode)
        )
        
        let codeReferenceButton = UIBarButtonItem(
            title: NSLocalizedString("Reference", comment: ""),
            style: .plain,
            target: self,
            action: #selector(EditorTabViewController.showCodeReference)
        )
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let organize = UIBarButtonItem(
            barButtonSystemItem: .organize,
            target: self,
            action: #selector(EditorTabViewController.showFolderContent)
        )
        
        self.toolbarItems = [formatButton, flexibleSpace, organize, flexibleSpace, codeReferenceButton]
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(EditorTabViewController.saveCode),
            name: NSNotification.Name(rawValue: "saveCode"),
            object: nil
        )
        
        self.bar.appearance = TabmanBar.Appearance({ (appearance) in
            
            // customize appearance here
            appearance.state.selectedColor = UIColor.white
            appearance.state.color = UIColor.white
            appearance.style.background = .solid(color: UIColor.processing())
            appearance.indicator.color = UIColor.white
            //appearance.state.color = UIColor.processing()
            appearance.indicator.isProgressive = false
        })
        
        reloadBarTitles()
    }
    
    func reloadBarTitles() {
        var titles = [Item]()
        for sourceCodeFile in project.sourceCodeFiles {
            titles.append(Item(title: "\(sourceCodeFile.fileName)"))
        }
        if titles.count > 0 {
            self.bar.items = titles
        }
    }
    
    func numberOfViewControllers(in pageboyViewController: PageboyViewController) -> Int {
        return project.sourceCodeFiles.count
    }
    
    func viewController(for pageboyViewController: PageboyViewController,
                        at index: PageboyViewController.PageIndex) -> UIViewController? {
        return PDEEditorViewController(sourceCodeFile: project.sourceCodeFiles[index])
    }
    
    func defaultPage(for pageboyViewController: PageboyViewController) -> PageboyViewController.Page? {
        return .first
    }
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(
                input: "t",
                modifierFlags: .command,
                action: #selector(EditorTabViewController.formatCode),
                discoverabilityTitle: "Format Code"
            ),
            UIKeyCommand(
                input: "s",
                modifierFlags: .command,
                action: #selector(EditorTabViewController.saveCode),
                discoverabilityTitle: "Save Code"
            ),
            UIKeyCommand(
                input: "r",
                modifierFlags: .command,
                action: #selector(EditorTabViewController.runSketch),
                discoverabilityTitle: "Run Code"
            ),
            UIKeyCommand(
                input: "w",
                modifierFlags: .command,
                action: #selector(EditorTabViewController.close),
                discoverabilityTitle: "Close Project"
            ),
            UIKeyCommand(
                input: UIKeyInputEscape,
                modifierFlags: UIKeyModifierFlags(rawValue: 0),
                action: #selector(EditorTabViewController.close),
                discoverabilityTitle: "Close Project"
            ),
            UIKeyCommand(
                input: "\t",
                modifierFlags: .control,
                action: #selector(EditorTabViewController.nextTab),
                discoverabilityTitle: "Next Tab"
            ),
            UIKeyCommand(
                input: "\t",
                modifierFlags: [.control, .shift],
                action: #selector(EditorTabViewController.previousTab),
                discoverabilityTitle: "Previous Tab"
            ),
            UIKeyCommand(
                input: "n",
                modifierFlags: .command,
                action: #selector(EditorTabViewController.addNewPDEFile),
                discoverabilityTitle: "Add new File"
            )
        ]
    }
    
    @objc func nextTab() {
        scrollToPage(.next, animated: true)
    }
    
    @objc func previousTab() {
        scrollToPage(.previous, animated: true)
    }
    
    @objc func close() {
        saveCode()
        self.navigationController?.popViewController(animated: true)
    }
    
    @objc func showCodeReference() {
        let safariVC = SFSafariViewController(url: URL(string: "https://processing.org/reference/")!)
        present(safariVC, animated: true, completion: nil)
    }
    
    @objc func share(sender: UIBarButtonItem) {
        
        saveCode()
        
        guard let view = sender.value(forKey: "view") as? UIView else {
            return
        }
        
        let actionSheet = UIAlertController(title: "Export", message: "Select how you‘d like to export your project.", preferredStyle: .actionSheet)
        actionSheet.modalPresentationStyle = .popover
        
        
        let homescreen = UIAlertAction(title: "Add App to Homescreen", style: .default) { (_) in
            
            
            
            if FredKitSubscriptionManager.shared.isCurrentlySubscribed {
                if #available(iOS 11.0, *) {
                    let homeScreenShareVC = SelectAppIconViewController()
                    homeScreenShareVC.project = self.project
                    let navC = UINavigationController(rootViewController: homeScreenShareVC)
                    navC.modalPresentationStyle = .formSheet
                    self.present(navC, animated: true)
                }
                
            } else {
                FredKitUpgradeDetailTableViewController.show()
            }
            
            
        }
        
        let exportFolder = UIAlertAction(title: "Export Project", style: .default) { (_) in
            let sourceCodeURLs = self.project.sourceCodeFiles.map { (sourceCodeFile) -> URL in
                return URL(fileURLWithPath: sourceCodeFile.filePath)
            }
            let activityViewController = UIActivityViewController(activityItems: sourceCodeURLs, applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = view
            self.present(activityViewController, animated: true)
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            
        }
        
        
        actionSheet.addAction(homescreen)
        actionSheet.addAction(exportFolder)
        actionSheet.addAction(cancel)
        
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = view.frame
        }
        
        present(actionSheet, animated: true)
        
    }
    
    @objc func runSketch() {
        saveCode()
        let runVC = RunSketchViewController(simpleTextProject: project)!
        runVC.delegate = self
        navigationController?.pushViewController(runVC, animated: true)
    }
    
    @objc func formatCode() {
        let pdeFileViewController = currentViewController as? PDEEditorViewController
        pdeFileViewController?.formatCode()
    }
    
    @objc func saveCode() {
        
        let pdeFileViewController = currentViewController as? PDEEditorViewController
        pdeFileViewController?.saveCode()
    }
    
    @objc func showFolderContent() {
        let folderContenVC = FolderContentBrowserTableViewController(
            withPath: self.project.folder.path,
            basePath: self.project.folder.path
        )
        let navC = ProcessingNavigationViewController(rootViewController: folderContenVC)
        navigationController?.present(navC, animated: true, completion: nil)
        
    }
    
    @objc func addNewPDEFile() {
        saveCode()
        addNewFileName(withErrorMessage: nil, predefinedFileName: nil)
    }
    
    func addNewFileName(withErrorMessage errorMessage: String?, predefinedFileName: String?) {
        var fileNameAlertController: UIAlertController
        if let errorMessage = errorMessage, let predefinedFileName = predefinedFileName {
            fileNameAlertController = UIAlertController(
                title: "Error Creating New \(project.sourceCodeExtension) File",
                message: errorMessage, preferredStyle: .alert
            )
            fileNameAlertController.addTextField { (textfield) in
                textfield.placeholder = "File Name"
                textfield.text = predefinedFileName
            }
        } else {
            fileNameAlertController = UIAlertController(
                title: "New \(project.sourceCodeExtension) File",
                message: "Creating a \(project.sourceCodeExtension) file in this project.",
                preferredStyle: .alert
            )
            fileNameAlertController.addTextField { (textfield) in
                textfield.placeholder = "File Name"
            }
        }
        
        fileNameAlertController.addAction(createAction(fileNameAlertController: fileNameAlertController))
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        fileNameAlertController.addAction(cancelAction)
        
        self.present(fileNameAlertController, animated: true, completion: nil)
    }
    
    func createAction(fileNameAlertController: UIAlertController) -> UIAlertAction {
        return UIAlertAction(title: "Create", style: .default) { (_) in
            if let newFileNameTextField = fileNameAlertController.textFields?.first {
                if let newFileName = newFileNameTextField.text {
                    
                    let letters = NSMutableCharacterSet.letters as? NSMutableCharacterSet
                    letters?.addCharacters(in: "-_1234567890")
                    
                    if newFileName.contains(" ") {
                        self.addNewFileName(
                            withErrorMessage: "The name should not contain any spaces.",
                            predefinedFileName: newFileName.replacingOccurrences(of: " ", with: "_")
                        )
                    } else if newFileName == "" {
                        self.addNewFileName(
                            withErrorMessage: "Name should be at least one character.",
                            predefinedFileName: newFileName
                        )
                    } else if self.nameAlreadyExists(name: newFileName) {
                        self.addNewFileName(
                            withErrorMessage: "A file with the same name already exists. Please chose another name.",
                            predefinedFileName: newFileName
                        )
                    } else if !(letters?.isSuperset(of: CharacterSet.init(charactersIn: newFileName)))! {
                        self.addNewFileName(
                            withErrorMessage: "Please don't use any fancy characters in the file name.",
                            predefinedFileName: newFileName
                        )
                    } else {
                        //everything is fine, create new file
                        
                        let className = newFileName.capitalized
                        let newClassCode = "class \(className) {\n   \n   \(className)() {\n      \n   }\n}"
                        self.project.createNewFile(withName: newFileName, content: newClassCode)
                        self.reloadPages()
                        self.reloadBarTitles()
                    }
                }
            }
        }
    }
    
    func nameAlreadyExists(name fileName: String) -> Bool {
        for file in project.sourceCodeFiles where file.fileName == "\(fileName).\(project.sourceCodeExtension)" {
            return true
        }
        return false
    }
}

extension EditorTabViewController: RunSketchViewControllerDelegate {
    
    func didDetect(_ bug: DetectedBug!) {
        var fileIndex: Int?
        project.sourceCodeFiles.enumerated().forEach { (iterator) in
            
            let index = iterator.offset
            let file = iterator.element
            
            let code = file.content!.lowercased()
            
            if code.contains(bug.wrongCode.lowercased()) {
                fileIndex = index
            }
        }
        
        if let fileIndex = fileIndex {
            let page = PageboyViewController.Page.at(index: fileIndex)
            scrollToPage(page, animated: true) { (newViewController, animated, finished) in
                if let editor = self.currentViewController as? PDEEditorViewController {
                    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { (_) in
                        editor.highlightCompilerError(ofCode: bug)
                    }
                }
            }
        }
    }
}
