//
//  Source.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/11.
//

import AVFoundation
 
/**
 框架提供了 4 种内置的源，分别为：1. AVAssetSource，AVAsset；2. ImageSource，静态图片；3. PHAssetVideoSource，相册视频；4. PHAssetImageSource，相册图片。我们也可以实现 Source 协议，提供自定义的素材来源。
 */
public protocol Source {
    ///选中时间段：在资源中的时间段
    var selectedTimeRange: CMTimeRange { get set }
    ///持续时间
    var duration: CMTime { get set }
    ///是否加载
    var isLoaded: Bool { get set }
    
    
    ///加载
    func load(completion: @escaping (NSError?) -> Void)
    ///资源轨道
    func tracks(for type: AVMediaType) -> [AVAssetTrack]
    ///纹理
    func texture(at time: CMTime) -> Texture?
    
}

extension Source {
    public func texture(at time: CMTime) -> Texture? {
        return nil
    }
}
