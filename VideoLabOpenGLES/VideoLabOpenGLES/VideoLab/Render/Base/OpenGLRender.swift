//
//  OpenGLRender.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/17.
//

import AVFoundation

public let standardImageVertices:[Float] = [
    -1.0, 1.0,//左上
     1.0, 1.0,//右上
     -1.0, -1.0,//左下
     1.0, -1.0//右下
]
public let standardTextureCoordinates: [Float] = [
    0.0, 1.0,//左上
    1.0, 1.0,//右上
    0.0, 0.0,//左下
    1.0, 0.0,//右下 
]

// BT.601, which is the standard for SDTV.
public let kColorConversionMatrix601Default = Matrix3x3(rowMajorValues:[
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0
])

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
public let kColorConversionMatrix601FullRangeDefault = Matrix3x3(rowMajorValues:[
    1.0,    1.0,    1.0,
    0.0,    -0.343, 1.765,
    1.4,    -0.711, 0.0,
])

// BT.709, which is the standard for HDTV.
public let kColorConversionMatrix709Default = Matrix3x3(rowMajorValues:[
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
])


public let OneInputVertexShader = "attribute vec4 position;\n attribute vec4 inputTextureCoordinate;\n \n varying vec2 textureCoordinate;\n \n void main()\n {\n     gl_Position = position;\n     textureCoordinate = inputTextureCoordinate.xy;\n }\n "
public let TwoInputVertexShader = "attribute vec4 position;\n attribute vec4 inputTextureCoordinate;\n attribute vec4 inputTextureCoordinate2;\n \n varying vec2 textureCoordinate;\n varying vec2 textureCoordinate2;\n \n void main()\n {\n     gl_Position = position;\n     textureCoordinate = inputTextureCoordinate.xy;\n     textureCoordinate2 = inputTextureCoordinate2.xy;\n }\n "
public let PassthroughVertexShader = "attribute vec3 position;\n attribute vec2 inputTextureCoordinate;\n varying vec2 textureCoordinate;\n \n uniform mat4 projection;\n uniform mat4 modelView;\n \n void main (void) {\n    gl_Position = projection * modelView * vec4(position, 1.0);\n    textureCoordinate = inputTextureCoordinate;\n } "
public let PassthroughFragmentShader = "varying highp vec2 textureCoordinate;\n \n uniform sampler2D inputImageTexture;\n \n void main()\n {\n     gl_FragColor = texture2D(inputImageTexture, textureCoordinate);\n }\n "


public let sharedOpenGLRender = OpenGLRender()
public class OpenGLRender {
    
    public var context: EAGLContext?
    public var shaderCache:[String:ShaderProgram] = [:]
    public lazy var textureCache: TextureCache = {
        TextureCache()
    }()
    private var glesTextureCache: CVOpenGLESTextureCache?
    private var yuvConversionProgram: ShaderProgram!
    private var normalProgram: ShaderProgram!

    public var framebuffer: GLuint = 0
    
    private var pixelBufferCache: [String : CVPixelBuffer] = [:]
    private var framebufferCache: [String : [String : GLuint]] = [:]
    
    
    init() {
        let context = EAGLContext(api:.openGLES2)
        EAGLContext.setCurrent(context)
        self.context = context
        self.setupNormalProgramProgram()
        self.setupYUVConversionProgram()
    }
    
    public func makeCurrentContext() {
        if (EAGLContext.current() != self.context)
        {
            EAGLContext.setCurrent(self.context)
        }
    }
    
    public func openGLESTextureCache() -> CVOpenGLESTextureCache? {
        if let glesTextureCache = self.glesTextureCache { return glesTextureCache }//性能优化，CPU 爆表
        var _textureCache: CVOpenGLESTextureCache?
        let status: CVReturn = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, self.context!, nil, &_textureCache)
        if (status != kCVReturnSuccess) {
            NSLog("Can't create openGLESTextureCache")
        }
        self.glesTextureCache = _textureCache
        return _textureCache;
    }

    public func renderQuadWithShader(_ shader:ShaderProgram, uniformSettings:ShaderUniformSettings? = nil, vertices:[Float] = standardImageVertices, textureCoordinates:[Float] = standardTextureCoordinates, inputTextures:[UInt : GLuint]) {
        
        makeCurrentContext()
        shader.use()
        uniformSettings?.restoreShaderSettings(shader)
        
        guard let positionAttribute = shader.attributeIndex("position") else { fatalError("A position attribute was missing from the shader program during rendering.") }
        glVertexAttribPointer(positionAttribute, 2, GLenum(GL_FLOAT), 0, 0, vertices)
        
        for (idx, inputTexture) in inputTextures {
            if let textureCoordinateAttribute = shader.attributeIndex("inputTextureCoordinate".withNonZeroSuffix(Int(idx))) {
                glVertexAttribPointer(textureCoordinateAttribute, 2, GLenum(GL_FLOAT), 0, 0, textureCoordinates)
            }
            
            glActiveTexture(textureUnitForIndex(Int(idx)))
            glBindTexture(GLenum(GL_TEXTURE_2D), inputTexture)
            shader.setValue(GLint(idx), forUniform:"inputImageTexture".withNonZeroSuffix(Int(idx)))
        }
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        for (idx, _) in inputTextures {
            glActiveTexture(textureUnitForIndex(Int(idx)))
            glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        }
        
        
    }
    
    public func programWithShaderName(_ shaderName: String) throws -> ShaderProgram {
        let lookupKeyForShaderProgram = "V: \(shaderName) - F: \(shaderName)"
        if let shaderFromCache = shaderCache[lookupKeyForShaderProgram] {
            return shaderFromCache
        } else {
            let program = try ShaderProgram(shaderName)
            self.shaderCache[lookupKeyForShaderProgram] = program
            return program
        }
    }
    
    public func programForVertexShader(_ vertexShader:String, fragmentShader:String) throws -> ShaderProgram {
        let lookupKeyForShaderProgram = "V: \(vertexShader) - F: \(fragmentShader)"
        if let shaderFromCache = shaderCache[lookupKeyForShaderProgram] {
            return shaderFromCache
        } else {
            let program = try ShaderProgram(vertexShader:vertexShader, fragmentShader:fragmentShader)
            self.shaderCache[lookupKeyForShaderProgram] = program
            return program
        }
    }
    
    //MARK: - public
    /// 创建 RGB 格式的 pixelBuffer
    func createPixelBuffer(with size: CGSize) -> CVPixelBuffer? {
#warning("不缓存会导致内存爆炸，缓存会导致上一个视频帧出现在屏幕中, GPUImage 缓存的是framebuffer")
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferOpenGLESCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
        
        if status != kCVReturnSuccess {
            NSLog("Can't create pixelbuffer")
        }
        return pixelBuffer
    }
    
    /// YUV 格式的 PixelBuffer 转化为 RGBA 纹理
    func convertYUVToRGBTexture(_ pixelBuffer: CVPixelBuffer) -> GLuint {
        
        let textureSize = CGSizeMake(CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
                                     CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
        
        //1.设置上下文
        sharedOpenGLRender.makeCurrentContext()
        //2.创建纹理和帧缓冲区
        let textureID: GLuint = self.requestFramebufferWithProperties(size: textureSize).texture
        
        //3.激活帧缓冲区以进行渲染
        self.clearFramebufferWithColor(0.0, 0.0, 0.0, 1.0)
        self.activateFramebufferForRendering(textureSize)
        
        //4.纹理赋值
        glBindTexture(GLenum(GL_TEXTURE_2D), textureID)
        //当调用glTexImage2D时，当前绑定的纹理对象就会被附加上纹理图像
        //glTexImage2D 函数用于设置二维纹理图像。如果传递 NULL 作为数据参数，这意味着你想要创建一个不初始化的纹理。这通常用于创建一个用于捕获的纹理，这种纹理可以被FBO捕获，并且可以在后续被渲染。
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(textureSize.width), GLsizei(textureSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)// 将图片数据写入纹理缓存
        //用于将2D纹理附加到帧缓冲对象上。
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), textureID, 0)
        
       
        //5.着色器操作
        
        // texture
        var luminanceTextureRef: CVOpenGLESTexture?
        var chrominanceTextureRef: CVOpenGLESTexture?
        var status: CVReturn = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                            self.openGLESTextureCache()!,
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
                                                              self.openGLESTextureCache()!,
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
        
        
        var colorConversionMatrix: Matrix3x3 = kColorConversionMatrix601FullRangeDefault
        let pixelFormatType: OSType = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if (pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            if (pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                colorConversionMatrix = kColorConversionMatrix601Default
            } else {
                colorConversionMatrix = kColorConversionMatrix601FullRangeDefault
            }
        }
        var uniformSettings = ShaderUniformSettings()
        uniformSettings["colorConversionMatrix"] = colorConversionMatrix
        
        let luminanceTexture = CVOpenGLESTextureGetName(luminanceTextureRef!)
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), luminanceTexture)
#warning("设置如何把纹素映射成像素, 不设置图像不显示，画布显示红色")
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        
        let chrominanceTexture = CVOpenGLESTextureGetName(chrominanceTextureRef!)
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        
        self.renderQuadWithShader(self.yuvConversionProgram, uniformSettings: uniformSettings, inputTextures: [0 : luminanceTexture, 1 : chrominanceTexture])
        
        
        glDeleteFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glFlush()
        
        
        
        return textureID
    }

    /// RBG 格式的 PixelBuffer 转化为纹理
    func convertRGBPixelBufferToTexture(pixelBuffer: CVPixelBuffer) -> GLuint {
        let textureSize: CGSize = CGSizeMake(CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
                                             CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
        var texture: CVOpenGLESTexture?
        
        let status: CVReturn = CVOpenGLESTextureCacheCreateTextureFromImage(nil,
                                                                            self.openGLESTextureCache()!,
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
        
        return CVOpenGLESTextureGetName(texture!)
    }
    
    /// 纹理转化为 RGB 格式的 pixelBuffer
    @discardableResult
    func convertTextureToPixelBuffer(texture: GLuint, textureSize: CGSize) -> CVPixelBuffer
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
        glUseProgram(self.normalProgram.program);
        
        // texture
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        glUniform1i(glGetUniformLocation(self.normalProgram.program, "renderTexture"), 0)
        
        // Uniform
//        let orthographicMatrix = orthographicMatrix(-(Float(renderSize.width)/2), right:Float(renderSize.width)/2, bottom:-Float((renderSize.height/2)), top:Float(renderSize.height)/2, near:-1.0, far:1.0).toRowMajorGLArray()
//        let modelViewMatrix = Transform.identity.modelViewMatrix(textureSize: textureSize, renderSize: renderSize).toRowMajorGLArray()
//
//        let projectionMatrixUniform = glGetUniformLocation(self.normalProgram, "projection")
//        glUniformMatrix4fv(projectionMatrixUniform, 1, GLboolean(GL_FALSE), orthographicMatrix)
//        let modelViewMatrixUniform = glGetUniformLocation(self.normalProgram, "modelView")
//        glUniformMatrix4fv(modelViewMatrixUniform, 1, GLboolean(GL_FALSE), modelViewMatrix)
        
        // VBO
        let positionSlot = GLuint(glGetAttribLocation(self.normalProgram.program, "position"))
        glEnableVertexAttribArray(GLuint(positionSlot))
        glVertexAttribPointer(positionSlot, 2, GLenum(GL_FLOAT), 0, 0, standardImageVertices)
        
        let textureSlot = GLuint(glGetAttribLocation(self.normalProgram.program, "inputTextureCoordinate"))
        glEnableVertexAttribArray(textureSlot)
        glVertexAttribPointer(textureSlot, 2, GLenum(GL_FLOAT), 0, 0, standardTextureCoordinates)
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        glDeleteFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        glFlush()
        
        return pixelBuffer
    }
    
    
    /// 渲染纹理到目标纹理
    ///- Parameter shader: 着色器
    ///- Parameter uniformSettings: uniform属性
    ///- Parameter sourceTexture: 源纹理
    ///- Parameter outputTexture: 输出纹理
    ///- Parameter renderSize: 渲染size
    ///- Parameter newFramebuffer: 生成新的 framebuffer
    func renderTexture(_ shader: ShaderProgram, uniformSettings: ShaderUniformSettings? = nil, inputTextures: [UInt : Texture], outputTexture: Texture, renderSize: CGSize, newFramebuffer: Bool = false, setWrap: Bool = false)
    {
        //1.设置上下文
        sharedOpenGLRender.makeCurrentContext()
        //2.创建纹理和帧缓冲区
        if newFramebuffer {
            self.framebuffer = self.generateFramebufferForTexture(outputTexture.texture, width: GLsizei(renderSize.width), height: GLsizei(renderSize.height), internalFormat: GL_RGBA, format: GL_BGRA, type: GL_UNSIGNED_BYTE)
        } else {
            let textureID: GLuint = self.requestFramebufferWithProperties(size: renderSize).texture
            outputTexture.texture = textureID
        }
        
        //3.激活帧缓冲区以进行渲染
        self.clearFramebufferWithColor(0.0, 0.0, 0.0, 1.0)
        self.activateFramebufferForRendering(renderSize)
        
        //4.绑定纹理
        glBindTexture(GLenum(GL_TEXTURE_2D), outputTexture.texture)
        //TODO: - 不设置这个组合不显示，设置这个。关键帧demo出现碎片化
        //设置如何把纹素映射成像素
        if !setWrap {        
            glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
            glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        }
        //当调用glTexImage2D时，当前绑定的纹理对象就会被附加上纹理图像
        //glTexImage2D 函数用于设置二维纹理图像。如果传递 NULL 作为数据参数，这意味着你想要创建一个不初始化的纹理。这通常用于创建一个用于捕获的纹理，这种纹理可以被FBO捕获，并且可以在后续被渲染。
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(renderSize.width), GLsizei(renderSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)// 将图片数据写入纹理缓存
        //用于将2D纹理附加到帧缓冲对象上。
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), outputTexture.texture, 0)
       
        //5.着色器操作
        var sourceTextures: [UInt : GLuint] = [:]
        if inputTextures.count == 0 {
            sourceTextures[0] = outputTexture.texture
        } else {
            for i in 0..<inputTextures.count {
                sourceTextures[UInt(i)] = inputTextures[UInt(i)]!.texture
                if i == inputTextures.count - 1 {
                    sourceTextures[UInt(i+1)] = outputTexture.texture
                }
            }
        }
        self.renderQuadWithShader(shader, uniformSettings: uniformSettings, inputTextures: sourceTextures)
        
        //6.解绑帧缓冲区
        sharedOpenGLRender.destroyFramebuffer()
        
        //glFlush()是OpenGL中的函数,用于强制刷新缓冲,保证绘图命令将被执行,而不是存储在缓冲区中等待其他的OpenGL命令。（强制刷新）
        glFlush()
    }
    
    
    //MARK: - FrameBuffer 创建
    @discardableResult
    public func requestFramebufferWithProperties(size: CGSize, textureIndex: Int = 0, textureOnly:Bool = false, minFilter:Int32 = GL_LINEAR, magFilter:Int32 = GL_LINEAR, wrapS:Int32 = GL_CLAMP_TO_EDGE, wrapT:Int32 = GL_CLAMP_TO_EDGE, internalFormat:Int32 = GL_RGBA, format:Int32 = GL_BGRA, type:Int32 = GL_UNSIGNED_BYTE) -> (framebuffer: GLuint, texture: GLuint) {
        let hash = self.hashForFramebufferWithProperties(size:size, textureIndex: textureIndex, textureOnly:textureOnly, minFilter:minFilter, magFilter:magFilter, wrapS:wrapS, wrapT:wrapT, internalFormat:internalFormat, format:format, type:type)
        var framebuffer: GLuint = 0
        var texture: GLuint = 0
        let key = "\(hash)"
        if let f = self.framebufferCache[key] {
            return (f["framebuffer"] ?? 0, f["texture"] ?? 0)
        } else {
            texture = self.generateTexture(minFilter: minFilter, magFilter: magFilter, wrapS: wrapS, wrapT: wrapT)
            framebuffer = self.generateFramebufferForTexture(texture, width: GLint(size.width), height: GLint(size.height), internalFormat: internalFormat, format: format, type: type)
            self.framebufferCache[key] = ["framebuffer" : framebuffer, "texture" : texture]
        }
        self.framebuffer = framebuffer
        return (framebuffer, texture)
    }
    
    ///通过属性值计算hash值作为key 缓存framebuffer
    func hashForFramebufferWithProperties(size: CGSize, textureIndex: Int, textureOnly:Bool = false, minFilter:Int32 = GL_LINEAR, magFilter:Int32 = GL_LINEAR, wrapS:Int32 = GL_CLAMP_TO_EDGE, wrapT:Int32 = GL_CLAMP_TO_EDGE, internalFormat:Int32 = GL_RGBA, format:Int32 = GL_BGRA, type:Int32 = GL_UNSIGNED_BYTE, stencil:Bool = false) -> Int64 {
        var result:Int64 = 1
        let prime:Int64 = 31
        let yesPrime:Int64 = 1231
        let noPrime:Int64 = 1237
        
        // TODO: Complete the rest of this
        result = prime * result + Int64(size.width)
        result = prime * result + Int64(size.height)
        result = prime * result + Int64(textureIndex)
        result = prime * result + Int64(internalFormat)
        result = prime * result + Int64(format)
        result = prime * result + Int64(type)
        result = prime * result + (textureOnly ? yesPrime : noPrime)
        result = prime * result + (stencil ? yesPrime : noPrime)
        return result
    }
    
    ///生成纹理
    public func generateTexture(minFilter:Int32, magFilter:Int32, wrapS:Int32, wrapT:Int32) -> GLuint {
        var texture:GLuint = 0
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        glGenTextures(1, &texture)
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        // 设置如何把纹素映射成像素
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), minFilter)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), magFilter)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), wrapS)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), wrapT)

        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        
        return texture
    }
    
    ///为纹理生成帧缓冲区
    func generateFramebufferForTexture(_ texture:GLuint, width:GLint, height:GLint, internalFormat:Int32, format:Int32, type:Int32) -> GLuint {
        var framebuffer:GLuint = 0
        glActiveTexture(GLenum(GL_TEXTURE1))

        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        
        //当调用glTexImage2D时，当前绑定的纹理对象就会被附加上纹理图像
        //glTexImage2D 函数用于设置二维纹理图像。如果传递 NULL 作为数据参数，这意味着你想要创建一个不初始化的纹理。这通常用于创建一个用于捕获的纹理，这种纹理可以被FBO捕获，并且可以在后续被渲染。
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, internalFormat, width, height, 0, GLenum(format), GLenum(type), nil)// 将图片数据写入纹理缓存
        //用于将2D纹理附加到帧缓冲对象上。
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)

        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if (status != GLenum(GL_FRAMEBUFFER_COMPLETE)) {
            fatalError("can't not created framebuffer: \(status)")
        }
        
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        return framebuffer
    }
    
    ///激活帧缓冲区以进行渲染
    public func activateFramebufferForRendering(_ size: CGSize) {
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), self.framebuffer)
        glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
    }
    
    public func clearFramebufferWithColor(_ r: Float, _ g: Float, _ b: Float, _ a: Float) {
        glClearColor(r, g, b, a)
        glClear(GLenum(GL_COLOR_BUFFER_BIT))
    }

    ///销毁显示帧缓冲区
    func destroyFramebuffer() {
        glDeleteFramebuffers(1, &self.framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    
    //MARK: - Private
    private func setupYUVConversionProgram() {
        let program = crashOnShaderCompileFailure("YUVConversion"){return try self.programWithShaderName("YUVConversion")}
        self.yuvConversionProgram = program
    }
    
    private func setupNormalProgramProgram() {
        let program = crashOnShaderCompileFailure("Normal"){return try self.programWithShaderName("Normal")}
        self.normalProgram = program
    }
    
    
    func supportsTextureCaches() -> Bool {
#if targetEnvironment(simulator)
        return false // Simulator glitches out on use of texture caches
#else
        return true // Every iOS version and device that can run Swift can handle texture caches
#endif
    }
}

func textureUnitForIndex(_ index:Int) -> GLenum {
    switch index {
        case 0: return GLenum(GL_TEXTURE0)
        case 1: return GLenum(GL_TEXTURE1)
        case 2: return GLenum(GL_TEXTURE2)
        case 3: return GLenum(GL_TEXTURE3)
        case 4: return GLenum(GL_TEXTURE4)
        case 5: return GLenum(GL_TEXTURE5)
        case 6: return GLenum(GL_TEXTURE6)
        case 7: return GLenum(GL_TEXTURE7)
        case 8: return GLenum(GL_TEXTURE8)
        default: fatalError("Attempted to address too high a texture unit")
    }
}


extension String {
    func withNonZeroSuffix(_ suffix:Int) -> String {
        if suffix == 0 {
            return self
        } else {
            return "\(self)\(suffix + 1)"
        }
    }
    
    func withGLChar(_ operation:(UnsafePointer<GLchar>) -> ()) {
        if let value = self.cString(using:String.Encoding.utf8) {
            operation(UnsafePointer<GLchar>(value))
        } else {
            fatalError("Could not convert this string to UTF8: \(self)")
        }
    }
}

