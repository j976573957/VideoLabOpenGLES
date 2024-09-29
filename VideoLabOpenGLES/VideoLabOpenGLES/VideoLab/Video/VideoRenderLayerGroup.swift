//
//  VideoRenderLayerGroup.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/13.
//

import AVFoundation

///VideoRenderLayerGroup 是 RenderLayerGroup 对应视频的框架内部对象，包含一个 RenderLayerGroup。可转换为 VideoRenderLayerGroup 的 RenderLayerGroup 只需满足一个条件：包含的 RenderLayer 组有一个可以转化为 VideoRenderLayer。
class VideoRenderLayerGroup: VideoRenderLayer {
    var videoRenderLayers: [VideoRenderLayer] = []
    private var recursiveVideoRenderLayersInGroup: [VideoRenderLayer] = []
    
    override init(renderLayer: RenderLayer) {
        super.init(renderLayer: renderLayer)
        generateVideoRenderLayers()
    }

    // MARK: - Public
    ///递归视频渲染层
    public func recursiveVideoRenderLayers() -> [VideoRenderLayer] {
        var recursiveVideoRenderLayers: [VideoRenderLayer] = []
        for videoRenderLayer in videoRenderLayers {
            videoRenderLayer.timeRangeInTimeline.start = CMTimeAdd(videoRenderLayer.timeRangeInTimeline.start, timeRangeInTimeline.start)
            if let videoRenderLayerGroup = videoRenderLayer as? VideoRenderLayerGroup {
                recursiveVideoRenderLayers += videoRenderLayerGroup.recursiveVideoRenderLayers()
            } else {
                recursiveVideoRenderLayers.append(videoRenderLayer)
            }
        }
        self.recursiveVideoRenderLayersInGroup = recursiveVideoRenderLayers
        
        return recursiveVideoRenderLayers
    }
    
    ///递归渲染的 trackID
    public func recursiveTrackIDs() -> [CMPersistentTrackID] {
        return recursiveVideoRenderLayersInGroup.compactMap { $0.trackID }
    }
    
    // MARK: - Private
    ///通过 renderLayer 生成对应的 VideoRenderLayer
    private func generateVideoRenderLayers() {
        guard let renderLayerGroup = renderLayer as? RenderLayerGroup else {
            return
        }
        
        for subRenderLayer in renderLayerGroup.layers {
            if subRenderLayer is RenderLayerGroup {
                videoRenderLayers.append(VideoRenderLayerGroup(renderLayer: subRenderLayer))
            } else if subRenderLayer.canBeConvertedToVideoRenderLayer() {
                videoRenderLayers.append(VideoRenderLayer(renderLayer: subRenderLayer))
            }
        }
    }
}


extension VideoRenderLayer {
    ///通过RenderLayer 创建 VideoRenderLayer
    class func makeVideoRenderLayer(renderLayer: RenderLayer) -> VideoRenderLayer {
        if renderLayer is RenderLayerGroup {
            return VideoRenderLayerGroup(renderLayer: renderLayer)
        } else {
            return VideoRenderLayer(renderLayer: renderLayer)
        }
    }
}

extension RenderLayerGroup {
    
    ///4.VideoRenderLayerGroup 是 RenderLayerGroup 对应视频的框架内部对象，包含一个 RenderLayerGroup。
    ///可转换为 VideoRenderLayerGroup 的 RenderLayerGroup 只需满足一个条件：包含的 RenderLayer 组有一个可以转化为 VideoRenderLayer。
    override func canBeConvertedToVideoRenderLayer() -> Bool {
        for renderLayer in layers {
            if renderLayer.canBeConvertedToVideoRenderLayer() {
                return true
            }
        }
        return false
    }
}
