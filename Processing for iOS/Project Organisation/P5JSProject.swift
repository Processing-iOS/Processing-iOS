//
//  P5JSProject.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/15/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import Foundation

@objc class P5JSProject: SimpleTextProject {
    
    @objc init(withProjectName name: String, importingFiles: [URL] = []) {
        super.init(with: name, sourceCodeExtension: "js", importingFiles: importingFiles)
    }
    
    override var emptyFile: String {
        let sketchJs = try! String(contentsOfFile: Bundle.main.path(forResource: "p5js-sketch", ofType: "js")!)
        return sketchJs
    }
    
}
