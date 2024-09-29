//
//  BasicOperation.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/11.
//

import AVFoundation

public func defaultVertexShaderForInputs(_ inputCount:UInt) -> String {
    switch inputCount {
    case 0:
        return OneInputVertexShader
    case 1:
        return OneInputVertexShader
    case 2:
        return TwoInputVertexShader
    default:
        return OneInputVertexShader
    }
}

open class BasicOperation: Animatable {
    
    public let maximumInputs: UInt
    public var uniformSettings = ShaderUniformSettings()
    public var enableOutputTextureRead = true
    public var shouldInputSourceTexture = false
    public var timeRange: CMTimeRange?
    var inputTextures = [UInt : Texture]()
    let textureInputSemaphore = DispatchSemaphore(value:1)
    ///着色器程序
    var shader:ShaderProgram
    ///输出纹理
    var outputTexture: Texture!
    
    public init(vertexShader:String? = nil, fragmentShader:String, numberOfInputs:UInt = 1, operationName:String = #file) {
        let compiledShader = crashOnShaderCompileFailure(operationName){try sharedOpenGLRender.programForVertexShader(vertexShader ?? defaultVertexShaderForInputs(numberOfInputs), fragmentShader:fragmentShader)}
        self.maximumInputs = numberOfInputs
        self.shader = compiledShader
    }
    
    public init(_ shaderName: String, numberOfInputs:UInt = 1, operationName:String = #file) {
        let compiledShader = crashOnShaderCompileFailure(operationName){try sharedOpenGLRender.programWithShaderName(shaderName)}
        self.maximumInputs = numberOfInputs
        self.shader = compiledShader
    }
    
    public func addTexture(_ texture: Texture, at index: UInt) {
        inputTextures[index] = texture
    }
    
    public func renderTexture(_ outputTexture: Texture, newFramebuffer: Bool = false) {
        let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
        defer {
            textureInputSemaphore.signal()
        }
        
        if inputTextures.count >= maximumInputs {
            sharedOpenGLRender.renderTexture(shader, uniformSettings: uniformSettings, inputTextures: inputTextures, outputTexture: outputTexture, renderSize: CGSize(width: outputTexture.width, height: outputTexture.height), newFramebuffer: newFramebuffer)
            self.outputTexture = outputTexture
        }
    }
    
    // MARK: - Animatable
    public var animations: [KeyframeAnimation]?
    public func updateAnimationValues(at time: CMTime) {
        
    }
    
}
