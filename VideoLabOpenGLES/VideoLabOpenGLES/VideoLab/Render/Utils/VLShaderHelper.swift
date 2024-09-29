//
//  VLShaderHelper.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/8/2.
//

import AVFoundation
import UIKit

class VLShaderHelper {
    // 将一个顶点着色器和一个片段着色器挂载到一个着色器程序上，并返回程序的 id
    class func programWithShaderName(_ shaderName: String) -> GLuint {
        // 编译两个着色器
        let vertexShader = self.compileShader(shaderName, type: .vertex)
        let fragmentShader = self.compileShader(shaderName, type: .fragment)
        
        // 挂载 shader 到 program 上
        let program = glCreateProgram()
        glAttachShader(program, vertexShader)
        glAttachShader(program, fragmentShader)
        
        // 链接 program
        glLinkProgram(program)
        
        // 检查链接是否成功
        glLinkProgram(program)
        
        var linkStatus:GLint = 0
        glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linkStatus)
        if (linkStatus == 0) {
            var logLength:GLint = 0
            glGetProgramiv(program, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            if (logLength > 0) {
                var compileLog = [CChar](repeating:0, count:Int(logLength))
                
                glGetProgramInfoLog(program, logLength, &logLength, &compileLog)
                print("Link log: \(String(cString:compileLog))")
            }
            
            fatalError("Link error")
        }
        
        glDeleteShader(vertexShader)
        glDeleteShader(fragmentShader)
        
        return program
    }

    // 通过一张图片来创建纹理
    class func createTextureWithImage(image: UIImage) -> GLuint {
        // 将 UIImage 转换为 CGImageRef
        let cgImageRef = image.cgImage!
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
        
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        context.clear(rect)
        context.draw(cgImageRef, in: rect)
        
        
        
        // 生成纹理
        var textureID: GLuint = 0
        glGenTextures(1, &textureID)
        glBindTexture(GLenum(GL_TEXTURE_2D), textureID)
        //glTexImage2D 函数用于设置二维纹理图像。如果传递 NULL 作为数据参数，这意味着你想要创建一个不初始化的纹理。这通常用于创建一个用于捕获的纹理，这种纹理可以被FBO捕获，并且可以在后续被渲染
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), imageData) // 将图片数据写入纹理缓存
        
        // 设置如何把纹素映射成像素
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        
        // 解绑
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        
        // 释放内存
        free(imageData)
        
        return textureID
    }

    //MARK: - Private

    // 编译一个 shader，并返回 shader 的 id
    private class func compileShader(_ name:String, type:ShaderType) -> GLuint {
        let shaderPath = Bundle.main.path(forResource: name, ofType: type == .vertex ? "vsh" : "fsh")! // 根据不同的类型确定后缀名
        let shaderString = try! String(contentsOfFile: shaderPath, encoding: .utf8)
        
        let shaderHandle:GLuint
        switch type {
            case .vertex: shaderHandle = glCreateShader(GLenum(GL_VERTEX_SHADER))
            case .fragment: shaderHandle = glCreateShader(GLenum(GL_FRAGMENT_SHADER))
        }
        
        shaderString.withGLChar{glString in
            var tempString:UnsafePointer<GLchar>? = glString
            glShaderSource(shaderHandle, 1, &tempString, nil)
            glCompileShader(shaderHandle)
        }
        
        var compileStatus:GLint = 1
        glGetShaderiv(shaderHandle, GLenum(GL_COMPILE_STATUS), &compileStatus)
        if (compileStatus != 1) {
            var logLength:GLint = 0
            glGetShaderiv(shaderHandle, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            if (logLength > 0) {
                var compileLog = [CChar](repeating:0, count:Int(logLength))
                
                glGetShaderInfoLog(shaderHandle, logLength, &logLength, &compileLog)
                print("Compile log: \(String(cString:compileLog))")
                // let compileLogString = String(bytes:compileLog.map{UInt8($0)}, encoding:NSASCIIStringEncoding)
                
                switch type {
                    case .vertex: fatalError("Vertex shader compile error:")
                    case .fragment: fatalError("Fragment shader compile error:")
                }
            }
        }
        
        return shaderHandle
    }
}
