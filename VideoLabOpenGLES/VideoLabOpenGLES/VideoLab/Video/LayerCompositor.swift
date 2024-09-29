//
//  LayerCompositor.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/14.
//

import AVFoundation
import UIKit

/**
 
 我们的渲染混合规则如下：

 排序 VideoRenderLayer 组，依据其所包含的 RenderLayer 的 layerLevel。如上图所示在纵向从高到低的排序。
 遍历 VideoRenderLayer 组，对每个 VideoRenderLayer 分为以下三种混合方式：
    1.当前 VideoRenderLayer 是 VideoRenderLayerGroup，即为预合成方式。遍历处理完自己内部的 VideoRenderLayer 组，生成一张纹理，混合到前面的纹理。
    2.当前 VideoRenderLayer 的 Source 包含视频轨道或 Source 为图片类型，拿到纹理处理自己的特效操作组（Operations），接着混合到前面的纹理。
    3.当前 VideoRenderLayer 仅特效操作组，所有的操作作用于前面混合的纹理。
 渲染混合规则总结来说，按层级渲染，从下往上。如当前层级有纹理则先处理自己的纹理，再混合进前面的纹理。如当前层级没有纹理，则操作直接作用于前面的纹理。

 让我们将规则用在上图的示例中，假设我们最后输出的纹理为 Output Texture：

    1.处理最底层的 VideoRenderLayerGroup 生成 Texture1，将 Texture1 混合进 Output Texture。
    2.处理 VideoRenderLayer2 生成 Texture 2，将 Texture2 混合进 Output Texture。
    3.处理 VideoRenderLayer3 生成 Texture 3，将 Texture3 混合进 Output Texture。
    4.处理 VideoRenderLayer4 的特效操作组，作用于 Output Texture。
 */

///渲染混合
class LayerCompositor {
//    let blendOperation = BlendOperation()
    let passthrough = Passthrough()
//    let yuvConversionProgram: ShaderProgram = {
//        return crashOnShaderCompileFailure("YUV"){try sharedOpenGLRender.programForVertexShader(OneInputVertexShader, fragmentShader:YUVConversionFullRangeFragmentShader)}
//    }()
    
    lazy var normalBlendProgram: ShaderProgram = {
        let program = crashOnShaderCompileFailure("NormalBlend"){return try sharedOpenGLRender.programWithShaderName("NormalBlend")}
        return program
    }()
    
    // MARK: - Public
    func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer, for request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
        guard let instruction = request.videoCompositionInstruction as? VideoCompositionInstruction else {
            return nil
        }
        //TODO: - 使用 法1 不会有残影，而 法2 有
        //法1: 生成outputTexture
        let textureSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        guard let outputPixelBuffer = sharedOpenGLRender.createPixelBuffer(with: textureSize) else { return nil }
        let rgbTexture = sharedOpenGLRender.convertRGBPixelBufferToTexture(pixelBuffer: outputPixelBuffer)
        let outputTexture = Texture(texture: rgbTexture, size: textureSize)
        //法2: 生成outputTexture
//        guard let outputTexture = Texture.makeTexture(pixelBuffer: pixelBuffer) else { return nil }
//        guard instruction.videoRenderLayers.count > 0 else {
////            Texture.clearTexture(outputTexture)
//            sharedOpenGLRender.convertTextureToPixelBuffer(texture: 0, textureSize: textureSize, renderSize: textureSize, textureID: outputTexture.texture)
//            return nil
//        }
        
        guard instruction.videoRenderLayers.count > 0 else { return nil }
        for (_, videoRenderLayer) in instruction.videoRenderLayers.enumerated() {
            autoreleasepool {
//                //第一个输出必须禁用才能读取，因为newPixelBuffer是从缓冲池中获取的，它可能是以前的pixelBuffer
//                let enableOutputTextureRead = (index != 0)
                renderLayer(videoRenderLayer, outputTexture: outputTexture, for: request)
            }
        }
        
        return outputPixelBuffer
    }
    
    
    // MARK: - Private
    private func renderLayer(_ videoRenderLayer: VideoRenderLayer, outputTexture: Texture?, for request: AVAsynchronousVideoCompositionRequest) {
        guard let outputTexture = outputTexture else {
            return
        }

        //将合成时间转换为内层时间
        let layerInternalTime = request.compositionTime - videoRenderLayer.timeRangeInTimeline.start

        // Update keyframe animation values
        videoRenderLayer.renderLayer.updateAnimationValues(at: layerInternalTime)


        //纹理层：层源包含视频轨迹，层源为图像，层组
        //渲染纹理层的步骤
        //步骤1：处理自己的操作
        //步骤2：与上一个输出纹理混合。上一个输出纹理是读回渲染缓冲区
        func renderTextureLayer(_ sourceTexture: Texture) {
            //1.自己的操作
            for operation in videoRenderLayer.renderLayer.operations {
                autoreleasepool {
                    if operation.shouldInputSourceTexture, let clonedSourceTexture = cloneTexture(from: sourceTexture) {
                        operation.addTexture(clonedSourceTexture, at: 0)
                        operation.renderTexture(sourceTexture)
                        clonedSourceTexture.unlock()
                    } else {
                        operation.renderTexture(sourceTexture, newFramebuffer: true)
                    }
                }
            }

            blendOutputText(outputTexture,
                            with: sourceTexture,
                            blendMode: videoRenderLayer.renderLayer.blendMode,
                            blendOpacity: videoRenderLayer.renderLayer.blendOpacity,
                            transform: videoRenderLayer.renderLayer.transform, 
                            setWrap: videoRenderLayer.renderLayer.animations?.count ?? 0 > 0)
        }

        if let videoRenderLayerGroup = videoRenderLayer as? VideoRenderLayerGroup {
            // Layer group
            let textureWidth = outputTexture.width
            let textureHeight = outputTexture.height
            //法1:
            let textureSize = CGSize(width: textureWidth, height: textureHeight)
            guard let outputPixelBuffer = sharedOpenGLRender.createPixelBuffer(with: textureSize) else { return }
            let rgbTexture = sharedOpenGLRender.convertRGBPixelBufferToTexture(pixelBuffer: outputPixelBuffer)
            let groupTexture = Texture(texture: rgbTexture, size: textureSize)
            //法2:从缓存中去有重影
//            guard let groupTexture = sharedOpenGLRender.textureCache.requestTexture(width: textureWidth, height: textureHeight) else {
//                return
//            }
            groupTexture.lock()
            
            //过滤与合成时间相交的图层。遍历相交的层以渲染每个层
            let intersectingVideoRenderLayers = videoRenderLayerGroup.videoRenderLayers.filter { $0.timeRangeInTimeline.containsTime(request.compositionTime) }
            for (_, subVideoRenderLayer) in intersectingVideoRenderLayers.enumerated() {
                autoreleasepool {
                    renderLayer(subVideoRenderLayer, outputTexture: groupTexture, for: request)
                }
            }
            
            renderTextureLayer(groupTexture)
            groupTexture.unlock()
        } else if videoRenderLayer.trackID != kCMPersistentTrackID_Invalid {
            // Texture layer source contains a video track
            //纹理层源包含视频轨迹
            guard let pixelBuffer = request.sourceFrame(byTrackID: videoRenderLayer.trackID) else {
                return
            }

            let videoTexture = sharedOpenGLRender.convertYUVToRGBTexture(pixelBuffer)
//            guard let videoTexture = bgraVideoTexture(from: pixelBuffer,
//                                                      preferredTransform: videoRenderLayer.preferredTransform) else {
//                return
//            }

            renderTextureLayer(Texture(texture: videoTexture, size: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))))
//            if videoTexture.textureRetainCount > 0 {
//                // Lock is invoked in the bgraVideoTexture method
//                //锁定在bgraVideoTexture方法中调用
//                videoTexture.unlock()
//            }
        } else if let sourceTexture = videoRenderLayer.renderLayer.source?.texture(at: layerInternalTime) {
            //纹理层源为图像
            guard let imageTexture = cloneTexture(from: sourceTexture) else {
                return
            }
            
            renderTextureLayer(imageTexture)
            // Lock is invoked in the imageTexture method
            imageTexture.unlock()
        } else {
            //2.处理混合之后的Filter
            //无纹理层。层的所有操作都应用于上一个输出纹理
            for operation in videoRenderLayer.renderLayer.operations {
                autoreleasepool {
                    if operation.shouldInputSourceTexture, let clonedOutputTexture = cloneTexture(from: outputTexture) {
                        operation.addTexture(clonedOutputTexture, at: 0)
                        operation.renderTexture(outputTexture)
                        clonedOutputTexture.unlock()
                    } else {
                        operation.renderTexture(outputTexture, newFramebuffer: true)
                    }
                }
            }
        }
        
    }
    
    private func cloneTexture(from sourceTexture: Texture) -> Texture? {
        let textureWidth = sourceTexture.width
        let textureHeight = sourceTexture.height
    
        guard let cloneTexture = sharedOpenGLRender.textureCache.requestTexture(width: textureWidth, height: textureHeight) else {
            return nil
        }
        cloneTexture.lock()
        //把 sourceTexture 纹理绘制到 cloneTexture 中
//        sharedOpenGLRender.renderTexture(self.normalProgram, sourceTextures: [sourceTexture], outputTexture: cloneTexture, renderSize: CGSize(width: 1280, height: 720))
        passthrough.addTexture(sourceTexture, at: 0)
        passthrough.renderTexture(cloneTexture)
        return cloneTexture
    }
    
    ///把 sourceTexture 混合到 outputTexture 上/
    private func blendOutputText(_ outputTexture: Texture,
                                 with texture: Texture,
                                 blendMode: BlendMode,
                                 blendOpacity: Float,
                                 transform: Transform,
                                 setWrap: Bool = false) {
        // Generate model, view, projection matrix
        let renderSize = CGSize(width: outputTexture.width, height: outputTexture.height)
        let textureSize = CGSize(width: texture.width, height: texture.height)
        let modelViewMatrix = transform.modelViewMatrix(textureSize: textureSize, renderSize: renderSize)
        let projectionMatrix = transform.projectionMatrix(renderSize: renderSize)
        
        
//        //1.设置上下文
//        sharedOpenGLRender.makeCurrentContext()
//        //2.创建帧缓冲区
//        sharedOpenGLRender.framebuffer = sharedOpenGLRender.generateFramebufferForTexture(outputTexture.texture, width: GLsizei(renderSize.width), height: GLsizei(renderSize.height), internalFormat: GL_RGBA, format: GL_BGRA, type: GL_UNSIGNED_BYTE)
//        //3.激活帧缓冲区以进行渲染
//        sharedOpenGLRender.activateFramebufferForRendering(renderSize)
//       
//        //4.着色器操作
//        var uniformSettings = ShaderUniformSettings()
//        uniformSettings["projection"] = projectionMatrix
//        uniformSettings["modelView"] = modelViewMatrix
//        uniformSettings["blendOpacity"] = blendOpacity
//        
//        sharedOpenGLRender.renderQuadWithShader(self.normalBlendProgram, uniformSettings: uniformSettings, inputTextures: [0 : texture.texture, 1 : outputTexture.texture])
// 
//        //5.解绑帧缓冲区
//        sharedOpenGLRender.destroyFramebuffer()
//        
//        //glFlush()是OpenGL中的函数,用于强制刷新缓冲,保证绘图命令将被执行,而不是存储在缓冲区中等待其他的OpenGL命令。（强制刷新）
//        glFlush()
        
        //从上面优化：
        var uniformSettings = ShaderUniformSettings()
        uniformSettings["projection"] = projectionMatrix
        uniformSettings["modelView"] = modelViewMatrix
        uniformSettings["blendOpacity"] = blendOpacity
        sharedOpenGLRender.renderTexture(self.normalBlendProgram, 
                                         uniformSettings: uniformSettings,
                                         inputTextures: [0 : texture],
                                         outputTexture: outputTexture,
                                         renderSize: renderSize,
                                         newFramebuffer: true,
                                         setWrap: setWrap)
    }
    
}
