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
import StoreKit

class EditorTabViewController: TabmanViewController, PageboyViewControllerDataSource, TMBarDataSource {
    
    let project: SimpleTextProject!
    private var editorFiles: [SourceCodeFile]
    private var pendingBug: DetectedBug?
    private var runningSketch: RunSketchViewController?
    private var lastConsole = SketchConsole()
    private var projectSharing: ProjectSharing?
    private var pendingReviewAfterSuccessfulRun = false
    private static let firstSuccessfulRunReviewKey = "requestedReviewAfterFirstSuccessfulRun"
    private let saveStatusLabel = UILabel()
    
    init(withProject project: SimpleTextProject) {
        self.project = project
        self.editorFiles = project.sourceCodeFiles
        super.init(nibName: "EditorTabViewController", bundle: Bundle.main)
        self.automaticallyAdjustsChildInsets = true
        self.dataSource = self
        
        
        
//        ExternalScreenController.showSketch(project: project)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self, selector: #selector(requestPendingReviewIfPossible),
            name: UIScene.didActivateNotification, object: nil
        )
        NotificationCenter.default.addObserver(self, selector: #selector(refreshProjectFromFiles), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        self.title = self.project.name
        let projectTitle = UILabel()
        projectTitle.text = project.name
        projectTitle.font = .preferredFont(forTextStyle: .headline)
        projectTitle.textColor = .white
        projectTitle.lineBreakMode = .byTruncatingMiddle
        saveStatusLabel.font = .preferredFont(forTextStyle: .caption2)
        saveStatusLabel.textColor = .white.withAlphaComponent(0.85)
        saveStatusLabel.text = "Saved"
        let titleStack = UIStackView(arrangedSubviews: [projectTitle, saveStatusLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .fill
        projectTitle.textAlignment = .center
        saveStatusLabel.textAlignment = .center
        let titleContainer = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 42))
        titleStack.frame = titleContainer.bounds
        titleStack.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        titleContainer.addSubview(titleStack)
        navigationItem.titleView = titleContainer
        
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
        
        let formatButton = UIBarButtonItem(title: "Tools", menu: UIMenu(children: [
            UIAction(title: "Format Code", image: UIImage(systemName: "text.alignleft")) { [weak self] _ in self?.formatCode() },
            UIAction(title: "Find and Replace", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in self?.findCode() },
            UIAction(title: "Undo", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in
                (self?.currentViewController as? PDEEditorViewController)?.undoCode()
            },
            UIAction(title: "Redo", image: UIImage(systemName: "arrow.uturn.forward")) { [weak self] _ in
                (self?.currentViewController as? PDEEditorViewController)?.redoCode()
            },
            UIMenu(title: "Text Size", image: UIImage(systemName: "textformat.size"), children: [
                UIAction(title: "Larger") { [weak self] _ in (self?.currentViewController as? PDEEditorViewController)?.changeFontSize(2) },
                UIAction(title: "Smaller") { [weak self] _ in (self?.currentViewController as? PDEEditorViewController)?.changeFontSize(-2) }
            ]),
            UIAction(title: "Console", image: UIImage(systemName: "terminal")) { [weak self] _ in
                guard let self else { return }
                self.view.endEditing(true)
                SketchConsoleViewController.presentConsole(self.lastConsole, from: self)
            }
        ]))
        
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
        
        let history = UIBarButtonItem(title: "History", style: .plain, target: self, action: #selector(showHistory))
        self.toolbarItems = [formatButton, flexibleSpace, organize, flexibleSpace, history, flexibleSpace, codeReferenceButton]
        NotificationCenter.default.addObserver(self, selector: #selector(updateSaveStatus), name: SourceCodeFile.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(projectFilesChanged(_:)), name: ProjectFiles.didChange, object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(EditorTabViewController.saveCode),
            name: NSNotification.Name(rawValue: "saveCode"),
            object: nil
        )
        
        let bar = TMBar.ButtonBar()
        bar.layout.transitionStyle = .snap
        bar.buttons.customize { button in
            button.tintColor = .white
            button.selectedTintColor = .white
        }
        bar.backgroundView.style = .flat(color: UIColor.processing())
        bar.indicator.tintColor = .white
        addBar(bar, dataSource: self, at: .top)
    }

    func barItem(for bar: TMBar, at index: Int) -> TMBarItemable {
        return TMBarItem(title: editorFiles[index].fileName)
    }

    func numberOfViewControllers(in pageboyViewController: PageboyViewController) -> Int {
        return editorFiles.count
    }
    
    func viewController(for pageboyViewController: PageboyViewController,
                        at index: PageboyViewController.PageIndex) -> UIViewController? {
        let editor = PDEEditorViewController(sourceCodeFile: editorFiles[index])
        editor?.completionFiles = editorFiles
        return editor
    }
    
    func defaultPage(for pageboyViewController: PageboyViewController) -> PageboyViewController.Page? {
        return .first
    }
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(findCode), discoverabilityTitle: "Find and Replace"),
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
                input: UIKeyCommand.inputEscape,
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
        guard saveCode() else { return }
        self.navigationController?.popViewController(animated: true)
    }

    @objc private func updateSaveStatus() {
        if editorFiles.contains(where: { $0.saveError != nil || $0.readError != nil }) {
            saveStatusLabel.text = "Not saved"
            saveStatusLabel.accessibilityHint = "Your edits are still open. Tap History to retry saving and see the error."
        } else {
            saveStatusLabel.text = editorFiles.contains(where: { $0.hasUnsavedChanges }) ? "Saving…" : "Saved"
            saveStatusLabel.accessibilityHint = nil
        }
    }

    @objc private func showHistory() {
        guard saveCode(), let editor = currentViewController as? PDEEditorViewController else { return }
        let history = SourceHistoryViewController(file: editor.sourceCodeFile) { [weak editor] in
            guard let editor else { return }
            editor.editor.text = editor.sourceCodeFile.content
            editor.textViewDidChange(editor.editor)
        }
        present(UINavigationController(rootViewController: history), animated: true)
    }
    
    @objc func showCodeReference() {
        let safariVC = SFSafariViewController(url: URL(string: "https://processing.org/reference/")!)
        present(safariVC, animated: true, completion: nil)
    }
    
    @objc func share(sender: UIBarButtonItem) {
        guard saveCode() else { return }
        projectSharing = ProjectSharing(folder: project.folder, name: project.name, presenter: self)
        projectSharing?.present(from: sender)
    }

    @objc func runSketch() {
        guard saveCode() else { return }
        let runVC = RunSketchViewController(simpleTextProject: project)!
        runVC.delegate = self
        runningSketch = runVC
        lastConsole = runVC.console
        pendingReviewAfterSuccessfulRun = false
        navigationController?.pushViewController(runVC, animated: true)
    }

    private func didReturnFromSketch() {
        guard let runner = runningSketch,
              navigationController?.topViewController === self,
              navigationController?.viewControllers.contains(where: { $0 === runner }) == false else { return }
        pendingReviewAfterSuccessfulRun = runner.completedSuccessfully
        runningSketch = nil
    }

    @objc private func requestPendingReviewIfPossible() {
        guard pendingReviewAfterSuccessfulRun else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.firstSuccessfulRunReviewKey) else {
            pendingReviewAfterSuccessfulRun = false
            return
        }
        guard pendingBug == nil, presentedViewController == nil,
              navigationController?.topViewController === self,
              let scene = viewIfLoaded?.window?.windowScene,
              scene.activationState == .foregroundActive else { return }

        pendingReviewAfterSuccessfulRun = false
        // StoreKit decides whether to show its dialog. Record the request, not a rating.
        defaults.set(true, forKey: Self.firstSuccessfulRunReviewKey)
        if #available(iOS 16.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
    
    @objc func formatCode() {
        let pdeFileViewController = currentViewController as? PDEEditorViewController
        pdeFileViewController?.formatCode()
    }

    @objc func findCode() {
        (currentViewController as? PDEEditorViewController)?.findCode()
    }
    
    @discardableResult
    @objc func saveCode() -> Bool {
        let editor = currentViewController as? PDEEditorViewController
        let currentSaved = editor?.saveCode() ?? true
        // A tab may have failed to save while switching away from it. Retry its retained buffer.
        for file in editorFiles where file.saveError != nil || file.hasUnsavedChanges {
            file.save()
        }
        refreshProjectFromFiles()
        if let file = editorFiles.first(where: { $0.saveError != nil || $0.readError != nil }) {
            if file.hasExternalConflict {
                presentConflict(for: file)
                return false
            }
            let error = file.saveError ?? file.readError
            if viewIfLoaded?.window != nil && presentedViewController == nil {
                let alert = UIAlertController(title: "Cannot Save Code",
                    message: "\(file.fileName): \(error?.localizedDescription ?? "The file could not be saved.")\n\nYour edits are still in the editor. The sketch has not been run.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
            return false
        }
        return currentSaved
    }

    @objc private func refreshProjectFromFiles() {
        guard navigationController?.topViewController === self else { return }
        for file in editorFiles { file.refreshFromDisk() }
        (currentViewController as? PDEEditorViewController)?.refreshExternalChanges()
        // Reflect files added or renamed through Files without replacing dirty buffers.
        projectFilesChanged(Notification(name: ProjectFiles.didChange, object: project.folder))
    }

    private func presentConflict(for file: SourceCodeFile) {
        guard presentedViewController == nil, viewIfLoaded?.window != nil else { return }
        let alert = UIAlertController(title: "File Changed Elsewhere", message: file.saveError?.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep My Changes", style: .default) { [weak self] _ in
            do {
                try file.keepMyChanges()
                (self?.currentViewController as? PDEEditorViewController)?.refreshExternalChanges()
            } catch { self?.showConflictError(error) }
        })
        alert.addAction(UIAlertAction(title: "Save My Copy and Load Files Version", style: .default) { [weak self] _ in
            do {
                let copy = try file.saveConflictCopyAndReload()
                (self?.currentViewController as? PDEEditorViewController)?.refreshExternalChanges()
                let saved = UIAlertController(title: "Both Versions Saved", message: "Your editor version is in Conflicts/\(copy.lastPathComponent). The editor now shows the version from Files.", preferredStyle: .alert)
                saved.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(saved, animated: true)
            } catch { self?.showConflictError(error) }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showConflictError(_ error: Error) {
        let alert = UIAlertController(title: "Cannot Resolve File", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func projectFilesChanged(_ notification: Notification) {
        guard let folder = notification.object as? URL, folder.standardizedFileURL.path == project.folder.standardizedFileURL.path,
              let urls = try? project.sourceFileURLs() else { return }
        var paths = urls.map(\.path)
        for file in editorFiles where (file.hasUnsavedChanges || file.saveError != nil) && !paths.contains(file.filePath) {
            paths.append(file.filePath)
        }
        guard paths != editorFiles.map(\.filePath) else { return }
        let previous = Dictionary(uniqueKeysWithValues: editorFiles.map { ($0.filePath, $0) })
        editorFiles = paths.map { previous[$0] ?? SourceCodeFile(filePath: $0) }
        reloadData()
    }

    @objc func showFolderContent() {
        guard saveCode() else { return }
        let folderContenVC = FolderContentBrowserTableViewController(
            withPath: self.project.folder.path,
            basePath: self.project.folder.path
        )
        let navC = ProcessingNavigationViewController(rootViewController: folderContenVC)
        navigationController?.present(navC, animated: true, completion: nil)
        
    }
    
    @objc func addNewPDEFile() {
        guard saveCode() else { return }
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
                    
                    var letters = CharacterSet.letters
                    letters.formUnion(CharacterSet(charactersIn: "-_1234567890"))
                    
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
                    } else if !letters.isSuperset(of: CharacterSet(charactersIn: newFileName)) {
                        self.addNewFileName(
                            withErrorMessage: "Please don't use any fancy characters in the file name.",
                            predefinedFileName: newFileName
                        )
                    } else {
                        //everything is fine, create new file
                        
                        let className = newFileName.prefix(1).uppercased() + newFileName.dropFirst()
                        let validClassName = className.range(of: #"^[A-Za-z_][A-Za-z_0-9]*$"#, options: .regularExpression) != nil
                        let newClassCode = validClassName
                            ? (self.project.sourceCodeExtension == "js"
                                ? "class \(className) {\n   constructor() {\n   }\n}\n"
                                : "class \(className) {\n   \(className)() {\n   }\n}\n")
                            : "// Additional project code\n"
                        do {
                            try self.project.createNewFile(withName: newFileName, content: newClassCode)
                            self.projectFilesChanged(Notification(name: ProjectFiles.didChange, object: self.project.folder))
                        } catch {
                            self.addNewFileName(withErrorMessage: error.localizedDescription, predefinedFileName: newFileName)
                        }
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
        pendingBug = bug
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didReturnFromSketch()
        requestPendingReviewIfPossible()
        guard let bug = pendingBug else { return }
        pendingBug = nil
        guard let fileIndex = editorFiles.firstIndex(where: { $0.fileName == bug.fileName }) else { return }
        let highlight: () -> Void = { [weak self] in
            guard let editor = self?.currentViewController as? PDEEditorViewController else { return }
            editor.highlightCompilerError(ofCode: bug)
        }
        if currentIndex == fileIndex {
            highlight()
        } else {
            scrollToPage(.at(index: fileIndex), animated: false) { _, _, finished in
                if finished { highlight() }
            }
        }
    }
}
