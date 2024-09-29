//
//  RenderLayer.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/7.
//

import AVFoundation

public enum BlendMode: Int {
    case normal = 0
    case darken
    case multiply
}


public class RenderLayer: Animatable {
    ///时间范围
    public var timeRange: CMTimeRange
    ///来源
    let source: Source?
    
    ///层级
    public var layerLevel: Int = 0
    ///变换
    public var transform: Transform = Transform.identity
    ///混合方式
    public var blendMode: BlendMode = .normal
    ///混合不透明度
    public var blendOpacity: Float = 1.0
    ///特效操作组
    public var operations: [BasicOperation] = []
    ///音频配置
    public var audioConfiguration: AudioConfiguration = AudioConfiguration()
    
    
    public init(timeRange: CMTimeRange, source: Source? = nil) {
        self.timeRange = timeRange
        self.source = source
    }
    
    // MARK: - Animatable
    public var animations: [KeyframeAnimation]?
    
    public func updateAnimationValues(at time: CMTime) {
        if let blendOpacity = KeyframeAnimation.value(for: "blendOpacity", at: time, animations: animations) {
            self.blendOpacity = blendOpacity
        }
        transform.updateAnimationValues(at: time)
        
        for operation in operations {
            let operationStartTime = operation.timeRange?.start ?? CMTime.zero
            let operationInternalTime = time - operationStartTime
            operation.updateAnimationValues(at: operationInternalTime)
        }
    }
    
    
}






//MARK: - String -> Texture

import UIKit
 

func textToTexture(text: String) -> GLuint? {
    // 创建一个图像上下文
    UIGraphicsBeginImageContextWithOptions(CGSize(width: 256, height: 256), false, 0)
    let context = UIGraphicsGetCurrentContext()
    
    // 设置文字属性
    let attributes = [
        NSAttributedString.Key.font: UIFont.systemFont(ofSize: 24),
        NSAttributedString.Key.foregroundColor: UIColor.white
    ]
    
    // 绘制文字
    text.draw(with: CGRect(x: 0, y: 0, width: 256, height: 256), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
    
    // 从图像上下文获取图像
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    // 创建纹理
    var texture: GLuint = 0
    image?.generateTexture(name: &texture)
    
    return texture
}
 
// 扩展以包含创建纹理的函数（需要OpenGL ES框架和相关的GLUtils实现）
extension UIImage {
    func generateTexture(name: inout GLuint) {
        let cgImage = self.cgImage!
        var width = cgImage.width
        var height = cgImage.height
        let rawData = calloc(width * height * 4, MemoryLayout<UInt8>.size)
        
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(data: rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo)
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        glGenTextures(1, &name)
        glBindTexture(GLenum(GL_TEXTURE_2D), name)
        
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), rawData!)
        
        free(rawData)
    }
}

