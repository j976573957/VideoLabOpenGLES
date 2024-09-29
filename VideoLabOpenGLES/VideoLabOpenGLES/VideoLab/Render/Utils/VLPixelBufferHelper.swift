//
//  VLPixelBufferHelper.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/8/2.
//

import UIKit
import AVFoundation

class VLPixelBufferHelper {

    private var context: EAGLContext!
    private var yuvConversionProgram: GLuint = 0
    private var normalProgram: GLuint = 0
    private var normalBlendProgram: GLuint = 0
    private var lookupFilterProgram: GLuint = 0
    private var brightnessFilterProgram: GLuint = 0
    private var zoomBlurFilterProgram: GLuint = 0
    private var textureCache: CVOpenGLESTextureCache? {
//        var _textureCache: CVOpenGLESTextureCache?
//        let status: CVReturn = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, self.context, nil, &_textureCache)
//        if (status != kCVReturnSuccess) {
//            NSLog("VLPixelBufferHelper Can't create textureCache")
//        }
//        return _textureCache
        return sharedOpenGLRender.openGLESTextureCache()
    }

    private var VBO: GLuint = 0

    private var luminanceTexture: CVOpenGLESTexture?
    private var chrominanceTexture: CVOpenGLESTexture?
    private var renderTexture: CVOpenGLESTexture?
    private var textureIDCache: [String : GLuint] = [:]
    private var tempPixelBuffer: CVPixelBuffer?
    
    init(context: EAGLContext) {
        self.context = context
        self.setupYUVConversionProgram()
        self.setupNormalProgram()
        self.setupNormalBlendProgram()
        self.setupLookupFilterProgram()
        self.setupBrightnessFilterProgram()
        self.setupZoomBlurFilterProgram()
        self.setupVBO()
    }
    
    //MARK: - public
    /// 创建 RGB 格式的 pixelBuffer
    func createPixelBuffer(with size: CGSize) -> CVPixelBuffer? {
        #warning("缓存会导致上一个视频帧出现在屏幕中")
//        if self.tempPixelBuffer != nil {
//            return self.tempPixelBuffer
//        }
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferOpenGLESCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
        
        if status != kCVReturnSuccess {
            NSLog("Can't create pixelbuffer")
        }
//        self.tempPixelBuffer = pixelBuffer
        return pixelBuffer
    }
    
    /// YUV 格式的 PixelBuffer 转化为 RGBA 纹理
    func convertYUVPixelBufferToTexture(pixelBuffer: CVPixelBuffer) -> GLuint {
        
        let textureSize = CGSizeMake(CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
                                     CGFloat(CVPixelBufferGetHeight(pixelBuffer)))

        sharedOpenGLRender.makeCurrentContext()
        
        var frameBuffer: GLuint = 0
        var textureID: GLuint = 0
        
        // 创建一个帧缓冲区
        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
        
        // 生成纹理
        let key = "YUV-\(textureSize.width)-\(textureSize.height)"
        if let textureIDInCache = self.textureIDCache[key] {
            textureID = textureIDInCache
        } else {
            glGenTextures(1, &textureID)
            glBindTexture(GLenum(GL_TEXTURE_2D), textureID)
            //当调用glTexImage2D时，当前绑定的纹理对象就会被附加上纹理图像
            //glTexImage2D 函数用于设置二维纹理图像。如果传递 NULL 作为数据参数，这意味着你想要创建一个不初始化的纹理。这通常用于创建一个用于捕获的纹理，这种纹理可以被FBO捕获，并且可以在后续被渲染。
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(textureSize.width), GLsizei(textureSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)
            
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
            
            self.textureIDCache[key] = textureID
        }
        
        //用于将2D纹理附加到帧缓冲对象上。
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), textureID, 0)
        
        
        
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        glViewport(0, 0, GLsizei(textureSize.width), GLsizei(textureSize.height))
        
        // program
        glUseProgram(self.yuvConversionProgram)
        
        // texture
        var luminanceTextureRef: CVOpenGLESTexture?
        var chrominanceTextureRef: CVOpenGLESTexture?
        var status: CVReturn = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                            self.textureCache!,
                                                                            pixelBuffer,
                                                                            nil,
                                                                            GLenum(GL_TEXTURE_2D),
                                                                            GL_LUMINANCE,
                                                                            GLsizei(textureSize.width),
                                                                            GLsizei(textureSize.height),
                                                                            GLenum(GL_LUMINANCE),
                                                                            GLenum(GL_UNSIGNED_BYTE),
                                                                            0,
                                                                            &luminanceTextureRef)
        if (status != kCVReturnSuccess) {
            NSLog("Can't create luminanceTexture")
        }
        
        status = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                              self.textureCache!,
                                                              pixelBuffer,
                                                              nil,
                                                              GLenum(GL_TEXTURE_2D),
                                                              GL_LUMINANCE_ALPHA,
                                                              Int32(textureSize.width) / 2,
                                                              Int32(textureSize.height) / 2,
                                                              GLenum(GL_LUMINANCE_ALPHA),
                                                              GLenum(GL_UNSIGNED_BYTE),
                                                              1,
                                                              &chrominanceTextureRef)
        
        if (status != kCVReturnSuccess) {
            NSLog("Can't create chrominanceTexture")
        }
        
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), CVOpenGLESTextureGetName(luminanceTextureRef!))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.yuvConversionProgram, "luminanceTexture"), 0)
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), CVOpenGLESTextureGetName(chrominanceTextureRef!))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.yuvConversionProgram, "chrominanceTexture"), 1)
        
        let yuvConversionMatrixUniform = glGetUniformLocation(self.yuvConversionProgram, "colorConversionMatrix")
        let pixelFormatType: OSType = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if (pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            if (pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                glUniformMatrix3fv(yuvConversionMatrixUniform, 1, GLboolean(GL_FALSE), colorConversionMatrix601Default.toRowMajorGLArray())
            } else {
                glUniformMatrix3fv(yuvConversionMatrixUniform, 1, GLboolean(GL_FALSE), colorConversionMatrix601FullRangeDefault.toRowMajorGLArray())
            }
        } else {
            
        }
        
        
        // VBO
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.VBO)
        
        let positionSlot = GLuint(glGetAttribLocation(self.yuvConversionProgram, "position"))
        glEnableVertexAttribArray(positionSlot)
        glVertexAttribPointer(positionSlot, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                              MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 0))
        
        let textureSlot = GLuint(glGetAttribLocation(self.yuvConversionProgram, "inputTextureCoordinate"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                             MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 3))
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        glDeleteFramebuffers(1, &frameBuffer)
        
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glFlush()
        
        self.luminanceTexture = luminanceTextureRef
        self.chrominanceTexture = chrominanceTextureRef
        
        
        return textureID
    }

    /// RBG 格式的 PixelBuffer 转化为纹理
    func convertRGBPixelBufferToTexture(pixelBuffer: CVPixelBuffer) -> GLuint {
//        if self.renderTexture != nil {
//            return CVOpenGLESTextureGetName(renderTexture!)
//        }
        let textureSize: CGSize = CGSizeMake(CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
                                             CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
        var texture: CVOpenGLESTexture?
        
        let status: CVReturn = CVOpenGLESTextureCacheCreateTextureFromImage(nil,
                                                                            self.textureCache!,
                                                                            pixelBuffer,
                                                                            nil,
                                                                            GLenum(GL_TEXTURE_2D),
                                                                            GL_RGBA,//OpenGL
                                                                            GLsizei(textureSize.width),
                                                                            GLsizei(textureSize.height),
                                                                            GLenum(GL_BGRA),//iOS
                                                                            GLenum(GL_UNSIGNED_BYTE),
                                                                            0,
                                                                            &texture)
        
        if (status != kCVReturnSuccess) {
            NSLog("Can't create texture")
            return 0
        }
        self.renderTexture = texture
        return CVOpenGLESTextureGetName(texture!)
    }
    
    /// 纹理转化为 RGB 格式的 pixelBuffer
    @discardableResult
    func convertTextureToPixelBuffer(texture: GLuint, textureSize: CGSize, renderSize: CGSize, textureID: GLuint = 0) -> CVPixelBuffer
    {
        sharedOpenGLRender.makeCurrentContext()
        
        let pixelBuffer: CVPixelBuffer = self.createPixelBuffer(with: textureSize)!
        let targetTextureID: GLuint = textureID != 0 ? textureID : self.convertRGBPixelBufferToTexture(pixelBuffer: pixelBuffer)
        
        var frameBuffer: GLuint = 0
        
        // FBO
        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
        // texture
        glBindTexture(GLenum(GL_TEXTURE_2D), targetTextureID)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(textureSize.width), GLsizei(textureSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)
        
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), targetTextureID, 0)
        
        
        
        glViewport(0, 0, GLsizei(textureSize.width), GLsizei(textureSize.height))
        
        // program
        glUseProgram(self.normalProgram);
        
        // texture
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.normalProgram, "renderTexture"), 0)
        
        // Uniform
//        let orthographicMatrix = orthographicMatrix(-(Float(renderSize.width)/2), right:Float(renderSize.width)/2, bottom:-Float((renderSize.height/2)), top:Float(renderSize.height)/2, near:-1.0, far:1.0).toRowMajorGLArray()
//        let modelViewMatrix = Transform.identity.modelViewMatrix(textureSize: textureSize, renderSize: renderSize).toRowMajorGLArray()
//        
//        let projectionMatrixUniform = glGetUniformLocation(self.normalProgram, "projection")
//        glUniformMatrix4fv(projectionMatrixUniform, 1, GLboolean(GL_FALSE), orthographicMatrix)
//        let modelViewMatrixUniform = glGetUniformLocation(self.normalProgram, "modelView")
//        glUniformMatrix4fv(modelViewMatrixUniform, 1, GLboolean(GL_FALSE), modelViewMatrix)
        
        // VBO
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.VBO)
        
        let positionSlot = GLuint(glGetAttribLocation(self.normalProgram, "position"))
        glEnableVertexAttribArray(GLuint(positionSlot))
        glVertexAttribPointer(positionSlot, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                              MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 0))
        
        let textureSlot = GLuint(glGetAttribLocation(self.normalProgram, "inputTextureCoordinate"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                             MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 3))
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        glDeleteFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glFlush()
        
        return pixelBuffer
    }

    ///把 sourceTexture 混合到 outputTexture 上，并输出CVPixelBufferRef
    @discardableResult
    func blendTextureToPixelBufferWithOutputTexture(_ outputTexture: GLuint, sourceTexture: GLuint, renderSize: CGSize, orthographicMatrix: [GLfloat], modelViewMatrix: [GLfloat], blendOpacity: Float = 1.0) -> (pixelBuffer: CVPixelBuffer, texture: GLuint)
    {
        sharedOpenGLRender.makeCurrentContext()
        
        let pixelBuffer: CVPixelBuffer = self.createPixelBuffer(with: renderSize)!
//        let targetTextureID: GLuint = self.convertRGBPixelBufferToTexture(pixelBuffer: pixelBuffer)
        
        var frameBuffer: GLuint = 0
        
        // FBO
        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
        // texture
        glBindTexture(GLenum(GL_TEXTURE_2D), outputTexture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(renderSize.width), GLsizei(renderSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)
        
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), outputTexture, 0)
        
        
        
        glViewport(0, 0, GLsizei(renderSize.width), GLsizei(renderSize.height))
        
        // program
        glUseProgram(self.normalBlendProgram);
        
        // texture
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), sourceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.normalBlendProgram, "inputImageTexture"), 0)
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), outputTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.normalBlendProgram, "inputImageTexture2"), 1)
        
        //Uniform
//        let orthographicMatrix = orthographicMatrix(-(Float(renderSize.width)/2), right:Float(renderSize.width)/2, bottom:-Float((renderSize.height/2)), top:Float(renderSize.height)/2, near:-1.0, far:1.0).toRowMajorGLArray()
//        let modelViewMatrix = Transform.identity.modelViewMatrix(textureSize: textureSize, renderSize: renderSize).toRowMajorGLArray()
        let projectionMatrixUniform = glGetUniformLocation(self.normalBlendProgram, "projection")
        glUniformMatrix4fv(projectionMatrixUniform, 1, GLboolean(GL_FALSE), orthographicMatrix)
        let modelViewMatrixUniform = glGetUniformLocation(self.normalBlendProgram, "modelView")
        glUniformMatrix4fv(modelViewMatrixUniform, 1, GLboolean(GL_FALSE), modelViewMatrix)
        let blendOpacityUniform = glGetUniformLocation(self.normalBlendProgram, "blendOpacity")
        glUniform1f(blendOpacityUniform, blendOpacity)
        
        // VBO
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.VBO)
        
        let positionSlot = GLuint(glGetAttribLocation(self.normalBlendProgram, "position"))
        glEnableVertexAttribArray(GLuint(positionSlot))
        glVertexAttribPointer(positionSlot, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                              MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 0))
        
        let textureSlot = GLuint(glGetAttribLocation(self.normalBlendProgram, "inputTextureCoordinate"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                             MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 3))
        
        let textureSlot2 = GLuint(glGetAttribLocation(self.normalBlendProgram, "inputTextureCoordinate2"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                             MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 3))
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        glDeleteFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glFlush()

        return (pixelBuffer, outputTexture)
    }
    
    
    /// 亮度调节 brightness: [-1.0, 1.0]
    @discardableResult
    func brightnessAdjust(texture: GLuint, textureSize: CGSize, renderSize: CGSize, brightness: Float) -> (pixelBuffer: CVPixelBuffer, texture: GLuint)
    {
        sharedOpenGLRender.makeCurrentContext()
        
        let pixelBuffer: CVPixelBuffer = self.createPixelBuffer(with: textureSize)!
        let targetTextureID: GLuint = self.convertRGBPixelBufferToTexture(pixelBuffer: pixelBuffer)
        
        var frameBuffer: GLuint = 0
        
        // FBO
        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
        // texture
        glBindTexture(GLenum(GL_TEXTURE_2D), targetTextureID)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(textureSize.width), GLsizei(textureSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)
        
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), targetTextureID, 0)
        
        
        
        glViewport(0, 0, GLsizei(textureSize.width), GLsizei(textureSize.height))
        
        // program
        glUseProgram(self.brightnessFilterProgram);
        
        // texture
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.brightnessFilterProgram, "inputImageTexture"), 0)
        
        // Uniform
        let brightnessUniform = glGetUniformLocation(self.brightnessFilterProgram, "brightness")
        glUniform1f(brightnessUniform, brightness)

        
        // VBO
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.VBO)
        
        let positionSlot = GLuint(glGetAttribLocation(self.brightnessFilterProgram, "position"))
        glEnableVertexAttribArray(GLuint(positionSlot))
        glVertexAttribPointer(positionSlot, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                              MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 0))
        
        let textureSlot = GLuint(glGetAttribLocation(self.brightnessFilterProgram, "inputTextureCoordinate"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                             MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 3))
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        glDeleteFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glFlush()
        
        return (pixelBuffer, targetTextureID)
    }
    
    /// zoomBlurFilter
    ///- Parameter blurSize: [0.0, 1.0]
    ///- Parameter blurCenter: (0.5, 0.5) by default
    @discardableResult
    func zoomBlurFilterAdjust(texture: GLuint, textureSize: CGSize, renderSize: CGSize, blurCenter: CGPoint = .init(x: 0.5, y: 0.5), blurSize: Float = 1.0) -> (pixelBuffer: CVPixelBuffer, texture: GLuint)
    {
        sharedOpenGLRender.makeCurrentContext()
        
        let pixelBuffer: CVPixelBuffer = self.createPixelBuffer(with: textureSize)!
        let targetTextureID: GLuint = self.convertRGBPixelBufferToTexture(pixelBuffer: pixelBuffer)
        
        var frameBuffer: GLuint = 0
        
        // FBO
        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
        // texture
        glBindTexture(GLenum(GL_TEXTURE_2D), targetTextureID)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(textureSize.width), GLsizei(textureSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)
        
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), targetTextureID, 0)
        
        
        
        glViewport(0, 0, GLsizei(textureSize.width), GLsizei(textureSize.height))
        
        // program
        glUseProgram(self.zoomBlurFilterProgram);
        
        // texture
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.zoomBlurFilterProgram, "inputImageTexture"), 0)
        
        // Uniform
        let blurSizeUniform = glGetUniformLocation(self.zoomBlurFilterProgram, "blurSize")
        glUniform1f(blurSizeUniform, blurSize)
        let blurCenterUniform = glGetUniformLocation(self.zoomBlurFilterProgram, "blurCenter")
        glUniform2f(blurCenterUniform, GLfloat(blurCenter.x), GLfloat(blurCenter.y))

        
        // VBO
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.VBO)
        
        let positionSlot = GLuint(glGetAttribLocation(self.zoomBlurFilterProgram, "position"))
        glEnableVertexAttribArray(GLuint(positionSlot))
        glVertexAttribPointer(positionSlot, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                              MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 0))
        
        let textureSlot = GLuint(glGetAttribLocation(self.zoomBlurFilterProgram, "inputTextureCoordinate"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                             MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 3))
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        glDeleteFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glFlush()
        
        return (pixelBuffer, targetTextureID)
    }
    
    
    ///lookupFilter
    ///- Parameter intensity: Opacity/intensity of lookup filter ranges from 0.0 to 1.0, with 1.0 as the normal setting
    @discardableResult
    func lookupFilter(_ filterTexture: GLuint, sourceTexture: GLuint, renderSize: CGSize, intensity: Float = 1.0) -> (pixelBuffer: CVPixelBuffer, texture: GLuint)
    {
        sharedOpenGLRender.makeCurrentContext()
        
        let pixelBuffer: CVPixelBuffer = self.createPixelBuffer(with: renderSize)!
//        let targetTextureID: GLuint = self.convertRGBPixelBufferToTexture(pixelBuffer: pixelBuffer)
        
        var frameBuffer: GLuint = 0
        
        // FBO
        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
        // texture
        glBindTexture(GLenum(GL_TEXTURE_2D), sourceTexture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(renderSize.width), GLsizei(renderSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)
        
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), sourceTexture, 0)
        
        
        
        glViewport(0, 0, GLsizei(renderSize.width), GLsizei(renderSize.height))
        
        // program
        glUseProgram(self.lookupFilterProgram);
        
        // texture
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), sourceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.lookupFilterProgram, "inputImageTexture"), 0)
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), filterTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.lookupFilterProgram, "inputImageTexture2"), 1)
        
        //Uniform
        let blendOpacityUniform = glGetUniformLocation(self.lookupFilterProgram, "intensity")
        glUniform1f(blendOpacityUniform, intensity)
        
        // VBO
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.VBO)
        
        let positionSlot = GLuint(glGetAttribLocation(self.lookupFilterProgram, "position"))
        glEnableVertexAttribArray(GLuint(positionSlot))
        glVertexAttribPointer(positionSlot, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                              MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 0))
        
        let textureSlot = GLuint(glGetAttribLocation(self.lookupFilterProgram, "inputTextureCoordinate"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                             MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 3))
        
        let textureSlot2 = GLuint(glGetAttribLocation(self.lookupFilterProgram, "inputTextureCoordinate2"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(5 *
                                                                                             MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: MemoryLayout<GLfloat>.size * 3))
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        glDeleteFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glFlush()

        return (pixelBuffer, sourceTexture)
    }
    
    //MARK: - Private
    private func setupYUVConversionProgram() {
        self.yuvConversionProgram = VLShaderHelper.programWithShaderName("YUVConversion")
    }
    
    private func setupNormalProgram() {
        self.normalProgram = VLShaderHelper.programWithShaderName("Normal")
    }
    
    private func setupNormalBlendProgram() {
        self.normalBlendProgram = VLShaderHelper.programWithShaderName("NormalBlend")
    }
    
    private func setupLookupFilterProgram() {
        self.lookupFilterProgram = VLShaderHelper.programWithShaderName("LookupFilter")
    }
    
    private func setupBrightnessFilterProgram() {
        self.brightnessFilterProgram = VLShaderHelper.programWithShaderName("BrightnessFilter")
    }
    
    private func setupZoomBlurFilterProgram() {
        self.zoomBlurFilterProgram = VLShaderHelper.programWithShaderName("ZoomBlurFilter")
    }
    
    private func setupVBO() {
        let vertices: [GLfloat] = [
            -1.0, -1.0, 0.0, 0.0, 0.0,
            -1.0, 1.0, 0.0, 0.0, 1.0,
            1.0, -1.0, 0.0, 1.0, 0.0,
            1.0, 1.0, 0.0, 1.0, 1.0,
        ]
        
        glGenBuffers(1, &self.VBO)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.VBO)
        glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<GLfloat>.size * vertices.count, vertices, GLenum(GL_STATIC_DRAW))
    }
    
}
