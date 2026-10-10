//
//  SelectableOptionsViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/22/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import UIKit

@objc protocol SelectableOptionsViewControllerDelegate {
    func replaceCharacters(inRange range: NSRange, withString string: String)
}

class SelectableOptionsViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    var selectableOptions = [ [String: String] ]()
    
    @IBOutlet weak var codeFixTitle: UILabel!
    @IBOutlet weak var codeFixSubtitle: UILabel!
    
    
    @objc weak var delegate: SelectableOptionsViewControllerDelegate?
    var range: NSRange!
    var bugType: String!
    var bug: DetectedBug!
    
    @objc convenience init(withSelectableOptions selectableOptions: [ [String: String] ], forRange range: NSRange, bug: DetectedBug) {
        self.init()
        self.selectableOptions = selectableOptions
        self.range = range
        self.bug = bug
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UINib(nibName: "CodeFixSuggestionTableViewCell", bundle: Bundle.main), forCellReuseIdentifier: "replace-cell")
        
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.contentInset = UIEdgeInsets(top: 1, left: 0, bottom: 0, right: 0)
        
        tableView.layoutIfNeeded()
        
        codeFixSubtitle.text = bug.displayMessage

        // Do any additional setup after loading the view.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.layoutIfNeeded()
        self.preferredContentSize = CGSize(width: tableView.contentSize.width, height: tableView.contentSize.height + tableView.frame.origin.y + 1)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }


}


extension SelectableOptionsViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if section == 0 {
            return 1
        }
        
        return selectableOptions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "replace-cell", for: indexPath) as! CodeFixSuggestionTableViewCell
        
        if indexPath.section == 0 {
            return cell
        }
        
        let suggestion = selectableOptions[indexPath.row]
        cell.codeFix = suggestion
        
        
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 {
            return .leastNonzeroMagnitude
        }
        
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        if indexPath.section == 0 {
            return
        }
        
        let suggestion = selectableOptions[indexPath.row]
        delegate?.replaceCharacters(inRange: range, withString: suggestion["suggestion"]!)
        
        dismiss(animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return .leastNonzeroMagnitude
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        .leastNonzeroMagnitude
    }
    
}
