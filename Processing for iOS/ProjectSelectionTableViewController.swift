//
//  ProjectSelectionTableViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 5/15/18.
//  Copyright © 2018 Frederik Riedel. All rights reserved.
//

import UIKit

class ProjectSelectionTableViewController: UITableViewController, UIViewControllerPreviewingDelegate {

    

    var projects: Array<PDESketch>?
    var filteredProjects: Array<PDESketch>?
    let searchController = UISearchController(searchResultsController: nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Search Projects"
        if #available(iOS 9.1, *) {
            searchController.obscuresBackgroundDuringPresentation = false
        }
        searchController.searchBar.keyboardAppearance = .dark
        searchController.searchBar.tintColor = UIColor.white
        searchController.searchBar.barStyle = .black


        if #available(iOS 11.0, *) {
            navigationItem.searchController = searchController
        }
        definesPresentationContext = true

        SketchController.loadSketches { (projects) in
            self.projects = projects
            self.tableView.reloadData()
        }
        
        registerForPreviewing(with: self, sourceView: tableView)
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "project-cell", for: indexPath) as! ProjectTableViewCell

        if isFiltering() {
            if let project = filteredProjects?[indexPath.row] {
                cell.projectNameLabel.text = project.sketchName
            }
            return cell
        }
        
        if let project = projects?[indexPath.row] {
            cell.projectNameLabel.text = project.sketchName
        }
        

        return cell
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 66
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if isFiltering() {
            return false
        }
        return true
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            if let project = projects?[indexPath.row] {
                
                let alertController = UIAlertController(title: "Delete Project", message: "Are you sure that you want to delete the project \"\(project.sketchName!)\"? This cannot be undone.", preferredStyle: .alert)
                
                let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { (_) in
                    SketchController.deleteSketch(withName: project.sketchName)
                    
                    SketchController.loadSketches { (projects) in
                        self.projects = projects
                        self.tableView.deleteRows(at: [indexPath], with: .automatic)
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
        
        var currentProjects = projects
        if isFiltering() {
            currentProjects = filteredProjects
        }
        
        if let project = currentProjects?[indexPath.row] {
            let editor = PDEEditorViewController(pdeSketch: project)!
            navigationController?.pushViewController(editor, animated: true)
        }
    }
    
//    override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//        if #available(iOS 11.0, *) {
//            navigationController?.navigationBar.prefersLargeTitles = true
//        }
//    }


    @IBAction func about(_ sender: Any) {
        let aboutVC = AboutViewController()
        let aboutNavigationController = ProcessingNavigationViewController(rootViewController: aboutVC)
        aboutNavigationController.modalTransitionStyle = .coverVertical;
        aboutNavigationController.modalPresentationStyle = .formSheet;
        
        self.navigationController?.present(aboutNavigationController, animated: true, completion: nil)
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        if let indexPath = tableView.indexPathForRow(at: location) {
            let cell = tableView.cellForRow(at: indexPath)
            previewingContext.sourceRect = (cell?.frame)!
            
            let project: PDESketch
            if isFiltering() {
                project = filteredProjects![indexPath.row]
            } else {
                project = projects![indexPath.row]
            }
            let detailVC = PDEEditorViewController(pdeSketch: project)!
            return detailVC
        }
        
        return nil
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        navigationController?.pushViewController(viewControllerToCommit, animated: false)

    }
    
    private func searchBarIsEmpty() -> Bool {
        // Returns true if the text is empty or nil
        return searchController.searchBar.text?.isEmpty ?? true
    }
    
    func filterContentForSearchText(_ searchText: String, scope: String = "All") {
        filteredProjects = projects?.filter({ (project) -> Bool in
            return project.sketchName!.lowercased().contains(searchText.lowercased())
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
