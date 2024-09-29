//
//  RenderComposition.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/7.
//

import AVFoundation
import UIKit

public class RenderComposition {
    ///openGL 清除颜色glclear()
    public var backgroundColor: Color = Color.black {
        didSet {
            Color.clearColor = backgroundColor
        }
    }
    
    ///视频帧率
    public var frameDuration: CMTime = CMTime(value: 1, timescale: 30)
    ///渲染尺寸
    public var renderSize: CGSize = CGSize(width: 720, height: 1280)
    ///渲染Layer
    public var layers: [RenderLayer] = []
    ///动画层
    public var animationLayer: CALayer?
    
    public init() {}
    
}
