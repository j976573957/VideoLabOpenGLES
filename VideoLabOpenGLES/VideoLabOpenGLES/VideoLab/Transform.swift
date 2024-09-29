//
//  Transform.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/11.
//

import AVFoundation

public struct Transform: Animatable {
    public var center: CGPoint
    public var rotation: Float
    public var scale: Float
    
    public static let identity = Transform(center: CGPoint(x: 0.5, y: 0.5),
                                           rotation: 0,
                                           scale: 1.0)
    
    public init(center: CGPoint, rotation: Float, scale: Float) {
        self.center = center
        self.rotation = rotation
        self.scale = scale
    }
    
    ///视图模型矩阵
    func modelViewMatrix(textureSize: CGSize, renderSize: CGSize) -> Matrix4x4 {
        // Vertex coordinates are from -1 to 1, so need to divide by 2
        var w: CGFloat = 0, h: CGFloat = 0
        w = textureSize.width
        h = textureSize.height
        
        if textureSize.width >= textureSize.height {//源视频是：横视频
            w = (textureSize.width == renderSize.width ? w : renderSize.width) * 0.5
            h = textureSize.height * renderSize.width / textureSize.width * 0.5
        } else {//源视频是：竖视频
            h = (textureSize.height == renderSize.height ? h : renderSize.height) * 0.5
            w = textureSize.width * renderSize.height / textureSize.height * 0.5
        }
        
        
        let translationTransform = CATransform3DMakeTranslation((center.x - 0.5) * renderSize.width, (0.5 - center.y) * renderSize.height, 0)

        /*
         注意顺序：平移旋转缩放。这样可以保证先缩放，再旋转，最后平移。
        transformMatrix = translateMatrix * rotateMatrix * scaleMatrix
        矩阵会按照从右到左的顺序应用到position上。也就是先缩放（scale）,再旋转（rotate）,最后平移（translate）
        如果这个顺序反过来，就完全不同了。从线性代数角度来讲，就是矩阵A乘以矩阵B不等于矩阵B乘以矩阵A。
        */
        var modelViewTransform = CATransform3DRotate(translationTransform, CGFloat(rotation), 0, 0, -1)
        modelViewTransform = CATransform3DScale(modelViewTransform, w * CGFloat(self.scale), h * CGFloat(self.scale), 1)
 
        return Matrix4x4(modelViewTransform)
    }
    
    ///投影矩阵
    func projectionMatrix(renderSize: CGSize) -> Matrix4x4 {
        return orthographicMatrix(-Float(renderSize.width / 2),
                        right:Float(renderSize.width / 2),
                        bottom: -Float(renderSize.height) / 2,
                        top: Float(renderSize.height) / 2,
                        near: -1,
                        far: 1)
    }
    
    
    // MARK: - Animatable
    public var animations: [KeyframeAnimation]?
    
    public mutating func updateAnimationValues(at time: CMTime) {
        // Center point animation
        if let centerX = KeyframeAnimation.value(for: "center.x", at: time, animations: animations) {
            self.center.x = CGFloat(centerX)
        }
        if let centerY = KeyframeAnimation.value(for: "center.y", at: time, animations: animations) {
            self.center.y = CGFloat(centerY)
        }
        
        // Rotation animation
        if let rotation = KeyframeAnimation.value(for: "rotation", at: time, animations: animations) {
            self.rotation = rotation
        }
        
        // Scale animatio
        if let scale = KeyframeAnimation.value(for: "scale", at: time, animations: animations) {
            self.scale = scale
        }
    }
    
}
