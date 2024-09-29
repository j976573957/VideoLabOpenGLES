//
//  ZoomBlurFilter.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/9/18.
//

import AVFoundation

class ZoomBlur: BasicOperation {
    public var blurSize:Float = 1.0 { didSet { uniformSettings["blurSize"] = blurSize } }
    public var blurCenter:Position = Position.center { didSet { uniformSettings["blurCenter"] = blurCenter } }
    
    public init() {
        super.init("ZoomBlurFilter", numberOfInputs:0)
        
        ({blurSize = 1.0})()
        ({blurCenter = Position.center})()
    }
    
    public override func updateAnimationValues(at time: CMTime) {
        if let blurSize = KeyframeAnimation.value(for: "blurSize", at: time, animations: animations) {
            self.blurSize = blurSize
        }
    }
}
