//
//  TextureCache.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/7/31.
//

import AVFoundation

public class TextureCache {
    var textureCache = [String:[Texture]]()
    
    public func requestTexture(format:Int32 = GL_BGRA, width: Int, height: Int) -> Texture? {
        let hash = hashForTexture(format: format, width: width, height: height)
        NSLog("----> \(#function) - \(hash)")
        let texture: Texture?
        
        if let textureCount = textureCache[hash]?.count, textureCount > 0 {
            texture = textureCache[hash]!.removeLast()
        } else {
            let pixelBuffer = sharedOpenGLRender.createPixelBuffer(with: CGSize(width: width, height: height))
            texture = Texture.makeTexture(pixelBuffer: pixelBuffer!, format:format, width: width, height: height)
        }
        
        return texture
    }
    
    public func purgeAllTextures() {
        textureCache.removeAll()
    }
    
    public func returnToCache(_ texture: Texture) {
        let hash = hashForTexture(format: texture.format, width: texture.width, height: texture.height)
        if textureCache[hash] != nil {
            textureCache[hash]?.append(texture)
        } else {
            textureCache[hash] = [texture]
        }
    }
    
    private func hashForTexture(format:Int32 = GL_BGRA, width: Int, height: Int) -> String {
        return "\(width)x\(height)-\(format)"
    }
}
