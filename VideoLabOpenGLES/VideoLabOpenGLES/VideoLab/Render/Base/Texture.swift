//
//  Texture.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/11.
//

import AVFoundation


public class Texture {
    
    public var texture: GLuint
    public var format: Int32 = GL_BGRA
    
    private var textureWidth: Int = 0
    private var textureHeight: Int = 0
    
    public var width: Int {
        get {
            return textureWidth
        }
    }

    public var height: Int {
        get {
            return textureHeight
        }
    }
    
    public init(texture: GLuint, size: CGSize? = nil) {
        self.textureWidth = Int(size?.width ?? 0)
        self.textureHeight = Int(size?.height ?? 0)
        self.texture = texture
    }
    
    public class func makeTexture(pixelBuffer: CVPixelBuffer? = nil,
                                  internalFormat:Int32 = GL_RGBA,
                                  format:Int32 = GL_BGRA,
                                  type:Int32 = GL_UNSIGNED_BYTE,
                                  width: Int? = nil,
                                  height: Int? = nil,
                                  plane: Int = 0) -> Texture? {
//        let flags = CVPixelBufferLockFlags(rawValue: 0)
//        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, flags) else {
//          return nil
//        }
//        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, flags) }
//        
//        
//        let textureSize: CGSize = CGSizeMake(CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
//                                             CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
//        var texture: CVOpenGLESTexture?
//        let status: CVReturn = CVOpenGLESTextureCacheCreateTextureFromImage(nil,
//                                                                            sharedOpenGLRender.openGLESTextureCache()!,
//                                                                            pixelBuffer,
//                                                                            nil,
//                                                                            GLenum(GL_TEXTURE_2D),
//                                                                            GLint(internalFormat),//OpenGL
//                                                                            GLsizei(textureSize.width),
//                                                                            GLsizei(textureSize.height),
//                                                                            GLenum(format),//iOS
//                                                                            GLenum(type),
//                                                                            plane,
//                                                                            &texture)
//        
//        if (status != kCVReturnSuccess) {
//            NSLog("Can't create texture")
//            return nil
//        }
//        let renderTexture = CVOpenGLESTextureGetName(texture!)
        
        
        let textureSize: CGSize = (pixelBuffer != nil) ? CGSizeMake(CGFloat(CVPixelBufferGetWidth(pixelBuffer!)), CGFloat(CVPixelBufferGetHeight(pixelBuffer!))) : CGSizeMake(CGFloat(width!), CGFloat(height!))
        sharedOpenGLRender.makeCurrentContext()
        let renderTexture = sharedOpenGLRender.generateTexture(minFilter: GL_LINEAR, magFilter: GL_LINEAR, wrapS: GL_CLAMP_TO_EDGE, wrapT: GL_CLAMP_TO_EDGE)
        
        let t = Texture(texture: renderTexture)
        t.textureWidth = Int(textureSize.width)
        t.textureHeight = Int(textureSize.height)
        t.format = format
        return t
    }
    
    
    // TODO: Limit texture size to reduce memory
    public class func makeTexture(cgImage: CGImage) -> Texture? {
        NSLog("----> \(#function)")
        sharedOpenGLRender.makeCurrentContext()
        
        let cgImageRef = cgImage
        let width: GLuint = GLuint(cgImageRef.width)
        let height: GLuint = GLuint(cgImageRef.height)
        let rect = CGRectMake(0, 0, CGFloat(width), CGFloat(height))
        
        // 绘制图片
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let imageData = malloc(Int(width * height) * 4)
        let rawBitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: rawBitmapInfo)
        guard let context = CGContext(data: imageData,
                                      width: Int(width),
                                      height: Int(height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: Int(width) * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue)
        else {
            fatalError("creat context error")
        }
        
//        context.translateBy(x: 0, y: CGFloat(height))
//        context.scaleBy(x: 1.0, y: -1.0)
        context.clear(rect)
        context.draw(cgImageRef, in: rect)
        
        
        
        // 生成纹理
        let renderTexture = sharedOpenGLRender.generateTexture(minFilter: GL_LINEAR, magFilter: GL_LINEAR, wrapS: GL_CLAMP_TO_EDGE, wrapT: GL_CLAMP_TO_EDGE)
        glBindTexture(GLenum(GL_TEXTURE_2D), renderTexture)
        //glTexImage2D 函数用于设置二维纹理图像。如果传递 NULL 作为数据参数，这意味着你想要创建一个不初始化的纹理。这通常用于创建一个用于捕获的纹理，这种纹理可以被FBO捕获，并且可以在后续被渲染
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), imageData) // 将图片数据写入纹理缓存
        // 解绑
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        // 释放内存
        free(imageData)
        
        let t = Texture(texture: renderTexture)
        t.format = GL_RGBA
        t.textureWidth = Int(width)
        t.textureHeight = Int(height)
        return t
    }
    
    
    public class func makeTexture(cgImage: CGImage, completionHandler: @escaping (Texture?) -> Void) {
        let texture = makeTexture(cgImage: cgImage)
        completionHandler(texture)
    }
    
    public func debugQuickLook() -> UIImage? {
        return textureToUIImage(texture: self.texture, size: CGSize(width: self.width, height: self.height), framebuffer: 0)
    }
    
    public class func clearTexture(_ texture: Texture) {
        sharedOpenGLRender.makeCurrentContext()
        
        
//        // 创建一个帧缓冲区
//        var frameBuffer: GLuint = 0
//        glGenFramebuffers(1, &frameBuffer)
//        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
//        // 绑定纹理
//        glBindTexture(GLenum(GL_TEXTURE_2D), texture.texture)
//        //glTexImage2D 函数用于设置二维纹理图像。如果传递 NULL 作为数据参数，这意味着你想要创建一个不初始化的纹理。这通常用于创建一个用于捕获的纹理，这种纹理可以被FBO捕获，并且可以在后续被渲染
//        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, 0, 0, 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil) // 将图片数据写入纹理缓存
//        
//        // 设置如何把纹素映射成像素
//        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
//        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
//        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
//        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
//        
//        //用于将2D纹理附加到帧缓冲对象上。
//        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture.texture, 0)
//        
//        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
//        
//        // 解绑
//        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
//        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
//        glDeleteFramebuffers(1, &frameBuffer)
        

        glDeleteTextures(1, &texture.texture)
    }
    
    // MARK: - TextureCache
    var textureRetainCount = 0
    
    public func lock() {
        textureRetainCount += 1
    }
    
    public func unlock() {
        textureRetainCount -= 1
        if textureRetainCount < 1 {
            if textureRetainCount < 0 {
                fatalError("Tried to overrelease a texture")
            }
            textureRetainCount = 0
            sharedOpenGLRender.textureCache.returnToCache(self)
        }
    }
}


public func textureToUIImage(texture: GLuint, size: CGSize, framebuffer: GLuint) -> UIImage? {
    let outPixelBuffer = sharedOpenGLRender.convertTextureToPixelBuffer(texture: texture, textureSize: size)

    let ciimage = CIImage(cvImageBuffer: outPixelBuffer)
    let scaledImage = ciimage.transformed(by: CGAffineTransformMakeScale(0.5, 0.5))
    let context = CIContext(options: nil)
    guard let cgimage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
    let image = UIImage(cgImage: cgimage)
    return image
}


import UIKit
extension CGImage {
    public func cgImageToPixelBuffer(width: Int, height: Int,
                              pixelFormatType: OSType,
                              colorSpace: CGColorSpace,
                              alphaInfo: CGImageAlphaInfo,
                              orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
        assert(orientation == .up)

        var maybePixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         pixelFormatType,
                                         attrs as CFDictionary,
                                         &maybePixelBuffer)

        guard status == kCVReturnSuccess, let pixelBuffer = maybePixelBuffer else {
          return nil
        }

        let flags = CVPixelBufferLockFlags(rawValue: 0)
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, flags) else {
          return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, flags) }

        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: colorSpace,
                                      bitmapInfo: alphaInfo.rawValue)
        else {
          return nil
        }

        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
      }

}

