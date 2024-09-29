//
//  VideoRenderLayer.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/12.
//

import AVFoundation

/**
 VideoRenderLayer 是框架内部对象，包含一个 RenderLayer，主要负责将 RenderLayer 的视频轨道添加到 AVComposition 中。可转换为 VideoRenderLayer 的 RenderLayer 包含以下几类：1. Source 包含视频轨道；2. Source 为图片类型；3. 特效操作组不为空（Operations）。

 VideoRenderLayerGroup 是 RenderLayerGroup 对应视频的框架内部对象，包含一个 RenderLayerGroup。可转换为 VideoRenderLayerGroup 的 RenderLayerGroup 只需满足一个条件：包含的 RenderLayer 组有一个可以转化为 VideoRenderLayer。
 */
class VideoRenderLayer {
    ///渲染层
    let renderLayer: RenderLayer
    ///轨道ID
    var trackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    ///时间范围
    var timeRangeInTimeline: CMTimeRange
    ///首选变换
    var preferredTransform: CGAffineTransform = CGAffineTransform.identity
    
    init(renderLayer: RenderLayer) {
        self.renderLayer = renderLayer
        self.timeRangeInTimeline = renderLayer.timeRange
    }
    
    ///主要负责将 RenderLayer 的视频轨道添加到 AVComposition 中
    ///对于 RenderLayer 的 Source 包含视频轨道的 VideoRenderLayer，从 Source 中获取视频 AVAssetTrack，添加到 AVComposition。
    func addVideoTrack(to composition: AVMutableComposition, preferredTrackID: CMPersistentTrackID) {
        guard let source = renderLayer.source else { return }
        guard let assetTrack = source.tracks(for: AVMediaType.video).first else { return }
        trackID = preferredTrackID
        preferredTransform = assetTrack.preferredTransform
        
        let compositionTrack: AVMutableCompositionTrack? = {
            if let compositionTrack = composition.track(withTrackID: preferredTrackID) {
                return compositionTrack
            }
            return composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: preferredTrackID)
        }()
        
        if let compositionTrack = compositionTrack {
            do {
                try compositionTrack.insertTimeRange(source.selectedTimeRange, of: assetTrack, at: timeRangeInTimeline.start)
            } catch {
                
            }
        }
    }
    
    ///对于 RenderLayer 的 Source 为图片类型或仅有特效操作组类型（Source 为空）的 VideoRenderLayer，使用空视频添加一个新的视频轨道（这里的空视频是指视频轨道是黑帧且不包含音频轨道的视频）
    class func addBlankVideoTrack(to composition: AVMutableComposition, in timeRange: CMTimeRange, preferredTrackID: CMPersistentTrackID) {
        guard let assetTrack = blankVideoAsset?.tracks(withMediaType: .video).first else {
            return
        }
        
        let compositionTrack: AVMutableCompositionTrack? = {
            if let compositionTrack = composition.track(withTrackID: preferredTrackID) {
                return compositionTrack
            }
            return composition.addMutableTrack(withMediaType: .video, preferredTrackID: preferredTrackID)
        }()
        
        var insertTimeRange = assetTrack.timeRange
        if insertTimeRange.duration > timeRange.duration {
            insertTimeRange.duration = timeRange.duration
        }
        
        if let compositionTrack = compositionTrack {
            do {
                try compositionTrack.insertTimeRange(insertTimeRange, of: assetTrack, at: timeRange.start)
                compositionTrack.scaleTimeRange(CMTimeRange(start: timeRange.start, duration: insertTimeRange.duration), toDuration: timeRange.duration)
            } catch {
                
            }
        }
        
    }
    
    
    // MARK: - Private
    private static let blankVideoAsset: AVAsset? = {
        guard let videoURL = Bundle.main.url(forResource: "BlankVideo", withExtension: "mov") else {
            return nil
        }
        return AVAsset(url: videoURL)
    }()
    
}

extension RenderLayer {
    ///1. Source 包含视频轨道；2. Source 为图片类型；3. 特效操作组不为空（Operations）。
    ///能被转换为VideoRenderLayer的RenderLayer
    @objc func canBeConvertedToVideoRenderLayer() -> Bool {
        //
        if source?.tracks(for: .video).first != nil {
            return true
        }
        if source is ImageSource {
            return true
        }
        if operations.count > 0 {
            return true
        }
        
        return false
    }
}
