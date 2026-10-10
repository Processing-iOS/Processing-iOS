//
//  PDEProject.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/15/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import Foundation

@objc class PDEProject: SimpleTextProject {
    
    @objc init(withProjectName name: String, importingFiles: [URL] = []) {
        super.init(with: name, sourceCodeExtension: "pde", importingFiles: importingFiles)
    }
    
    override var emptyFile: String {
        return "void setup() {\n   size(screenWidth, screenHeight);\n}\n\n" +
               "void draw() {\n   background(0,0,255);\n}"
    }
}
