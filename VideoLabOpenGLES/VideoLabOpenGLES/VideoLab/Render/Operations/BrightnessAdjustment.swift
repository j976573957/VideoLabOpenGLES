//
//  BrightnessAdjustment.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/9/12.
//

import UIKit

class BrightnessAdjustment: BasicOperation {
    ///0～1
    public var brightness:Float = 0.0 {
        didSet {
            uniformSettings["brightness"] = brightness
        }
    }
    
    public init() {
        super.init("BrightnessFilter", numberOfInputs: 0)
        ({ brightness = 0.0 })()
    }
}
