//
//  AddToHomeScreenViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/11/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import UIKit

class AddToHomeScreenViewController: UIViewController {
    
    @IBOutlet weak var continueInSafariButton: ActivityButton!
    @objc var project: SimpleTextProject?
    @IBOutlet weak var instructionLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        continueInSafariButton.layer.cornerRadius = 16
        
        
        if #available(iOS 14.0, *) {
            instructionLabel.text = """
                Processing will copy the rendered app code to your clipboard.

                Next, open Safari and paste the code into the URL bar and load the page.

                From there, tap the share button, and select “Add to Homescreen”.
                """
            
            continueInSafariButton.setTitle("Copy to Clipboard", for: .normal)
        }
        
        // Do any additional setup after loading the view.
    }
    
    @IBAction func openSafari(_ sender: Any) {
        if #available(iOS 14.0, *) {
            if let project = project {
                let sourceCode = project.htmlPage
                let base64 = sourceCode.base64
                let base64URL = "data:text/html;charset=UTF-8;base64,\(base64)"
                UIPasteboard.general.string = base64URL
                
                let alert = UIAlertController(title: "Sketch Copied to Clipboard", message: "Next, proceed to Safari to paste the code into the URL bar to add the app to your home screen.", preferredStyle: .alert)
                
                alert.addAction(UIAlertAction(title: "Proceed in Safari", style: .default, handler: { (_) in
                    HomeScreenSharer.openLocalHostInstructions()
                    self.dismiss(animated: true)
                }))
                
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
                    
                }))
                
                self.present(alert, animated: true)
            }
            
        } else {
            if let project = project {
                HomeScreenSharer.share(sketch: project)
            }
            
            dismiss(animated: true)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        super.viewWillAppear(animated)
    }
}
