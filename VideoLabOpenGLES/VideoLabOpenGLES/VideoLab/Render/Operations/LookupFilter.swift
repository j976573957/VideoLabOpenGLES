//
//  LookupFilter.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/9/18.
//

import UIKit

class LookupFilter: BasicOperation {
    public var intensity: Float = 1.0 {
        didSet {
            uniformSettings["intensity"] = intensity
        }
    }

    public init() {
        super.init("LookupFilter", numberOfInputs: 1)
        
        ({ intensity = 1.0 })()
    }
}
