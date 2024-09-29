//
//  VideoLab.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/7.
//

import AVFoundation


/*
 整体的工作流程如下：
                                                      |--> AVPlayerItem
 RenderLayer(s) --> RenderComposition --> VideoLab -->|
                                                      |--> AVAssetExportSession
 
 我们来拆解下步骤：

 1.创建一个或多个 RenderLayer。
 2.创建 RenderComposition，设置其 BackgroundColor、FrameDuration、RenderSize，以及 RenderLayer 数组。
 3.使用创建的 RenderComposition 创建 VideoLab。
 4.使用创建的 VideoLab 生成 AVPlayerItem 或 AVAssetExportSession。
 
 */


public class VideoLab {
    ///渲染合成器配置
    public private(set) var renderComposition: RenderComposition
    
    private var videoRenderLayers: [VideoRenderLayer] = []
    private var audioRenderLayersInTimeline: [AudioRenderLayer] = []
    
    ///系统合成器
    private var composition: AVComposition?
    ///视频合成器：AVVideoComposition 可以用来指定渲染大小和渲染缩放，以及帧率。此外，还有一组存储了混合参数的 Instruction（指令）。有了这些混合参数之后，AVVideoComposition 可以通过自定义 Compositor（混合器） 来混合对应的图像帧。
    private var videoComposition: AVMutableVideoComposition?
    ///音频混合
    private var audioMix: AVAudioMix?
    
    // MARK: - Public
    ///初始化
    public init(renderComposition: RenderComposition) {
        self.renderComposition = renderComposition
    }

    ///生成 playerItem
    public func makePlayerItem() -> AVPlayerItem {
        let composition = makeComposition()
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = makeVideoComposition()
        playerItem.audioMix = makeAudioMix()
        return playerItem
    }
    
    ///图片生成器
    public func makeImageGenerator() -> AVAssetImageGenerator {
        let composition = makeComposition()
        let imageGenerator = AVAssetImageGenerator(asset: composition)
        imageGenerator.videoComposition = makeVideoComposition()
        return imageGenerator
    }
    
    ///导出会话
    public func makeExportSession(presetName: String, outputURL: URL) -> AVAssetExportSession? {
        let composition = makeComposition()
        let exportSession = AVAssetExportSession(asset: composition, presetName: presetName)
        let videoComposition = makeVideoComposition()
        videoComposition.animationTool = makeAnimationTool()
        exportSession?.videoComposition = videoComposition
        exportSession?.audioMix = makeAudioMix()
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = AVFileType.mp4
        return exportSession
    }
    
    
    // MARK: - Private
    private func makeComposition() -> AVComposition {
        //TODO:优化生成性能，如存在时返回
        
        let composition = AVMutableComposition()
        self.composition = composition
        
        //自增trackID
        var increasementTrackID: CMPersistentTrackID = 0
        func increaseTrackID() -> Int32 {
            let trackID = increasementTrackID + 1
            increasementTrackID = trackID
            return trackID
        }
        
        
        //步骤1：添加视频轨道  1.将 RenderLayer 转换为 VideoRenderLayer
        //子步骤1：生成按开始时间排序的videoRenderLayers。
        //videoRenderLayer可以包含视频轨道，或者该层的源为ImageSource。
        videoRenderLayers = renderComposition.layers.filter {
            $0.canBeConvertedToVideoRenderLayer()
        }.sorted {
            CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
        }.compactMap {
            VideoRenderLayer.makeVideoRenderLayer(renderLayer: $0)
        }
        
        //生成视频轨道ID。这个内联方法在子步骤2中使用。
        //如果轨道ID与之前的某些轨道没有交集，则可以重用该轨道ID，否则可以增加ID。
        var videoTrackIDInfo: [CMPersistentTrackID: CMTimeRange] = [:]
        func videoTrackID(for layer: VideoRenderLayer) -> CMPersistentTrackID {
            var videoTrackID: CMPersistentTrackID?
            for (trackID, timeRange) in videoTrackIDInfo {
                if layer.timeRangeInTimeline.start > timeRange.end {// 不在同一时间段，公用一条轨道: -_-
                    videoTrackID = trackID
                    videoTrackIDInfo[trackID] = layer.timeRangeInTimeline
                    break
                }
            }
            
            if let videoTrackID = videoTrackID {
                return videoTrackID
            } else {
                let videoTrackID = increaseTrackID()
                videoTrackIDInfo[videoTrackID] = layer.timeRangeInTimeline
                return videoTrackID
            }
        }
        
    
        //子步骤2：将时间轴中的所有VideoRenderLayer 视频轨道添加到合成中。 2. 将 VideoRenderLayer 视频轨道添加到 AVComposition 中
        //计算子步骤3的最小开始时间和最大结束时间。
        //所有videoRenderLayer, 因为videoRenderLayers可能有 VideoRenderLayerGroup
        var videoRenderLayersInTimeline: [VideoRenderLayer] = []
        videoRenderLayers.forEach { videoRenderLayer in
            if let videoRenderLayerGroup = videoRenderLayer as? VideoRenderLayerGroup {
                videoRenderLayersInTimeline += videoRenderLayerGroup.recursiveVideoRenderLayers()
            } else {
                videoRenderLayersInTimeline.append(videoRenderLayer)
            }
        }
        
        let minimumStartTime = videoRenderLayersInTimeline.first?.timeRangeInTimeline.start
        var maximumEndTime = videoRenderLayersInTimeline.first?.timeRangeInTimeline.end
        videoRenderLayersInTimeline.forEach { videoRenderLayer in
            //把视频轨道添加到 AVComposition 中
            if videoRenderLayer.renderLayer.source?.tracks(for: .video).first != nil {
                let trackID = videoTrackID(for: videoRenderLayer)
                videoRenderLayer.addVideoTrack(to: composition, preferredTrackID: trackID)
            }
            
            //更新结束时间
            if maximumEndTime! < videoRenderLayer.timeRangeInTimeline.end {
                maximumEndTime = videoRenderLayer.timeRangeInTimeline.end
            }
        }
        
        
        //子步骤3：为图像或效果层添加空白视频轨道。
        //轨道的持续时间与时间线的持续时间相同。
        if let minimumStartTime = minimumStartTime, let maximumEndTime = maximumEndTime {
            let timeRange = CMTimeRange(start: minimumStartTime, end: maximumEndTime)
            let videoTrackID = increaseTrackID()
            VideoRenderLayer.addBlankVideoTrack(to: composition, in: timeRange, preferredTrackID: videoTrackID)
        }
        
        
        
        //步骤2：添加音频轨道
        //子步骤1：生成按开始时间排序的audioRenderLayers。
        //audioRenderLayer必须包含音轨。
        let audioRenderLayers = renderComposition.layers.filter {
            $0.canBeConvertedToAudioRenderLayer()
        }.sorted {
            CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
        }.compactMap {
            AudioRenderLayer.makeAudioRenderLayer(renderLayer: $0)
        }
        
        //子步骤2：将时间轴中的曲目添加到合成中。
        //由于AVAudioMixInputParameters仅对应于一个音轨ID，因此该音轨ID不会重复使用。一个音频层对应于一个音轨ID。
        //不同于视频轨道的重用，音频的每个 AudioRenderLayer 都对应一个音频轨道。这是由于一个 AVAudioMixInputParameters 与一个音频的轨道一一对应，而其音高设置（audioTimePitchAlgorithm）作用于整个音频轨道。如果重用的话，会存在一个音频轨道有多个 AudioRenderLayer 的情况，这样会导致所有的 AudioRenderLayer 都要配置同样的音高，这显然是不合理的。。
        audioRenderLayersInTimeline = []
        audioRenderLayers.forEach { audioRenderLayer in
            if let audioRenderLayerGroup = audioRenderLayer as? AudioRenderLayerGroup {
                audioRenderLayersInTimeline += audioRenderLayerGroup.recursiveAudioRenderLayers()
            } else {
                audioRenderLayersInTimeline.append(audioRenderLayer)
            }
        }
        audioRenderLayersInTimeline.forEach { audioRenderLayer in
            if audioRenderLayer.renderLayer.source?.tracks(for: .audio).first != nil {
                let trackID = increaseTrackID()
                audioRenderLayer.trackID = trackID
                audioRenderLayer.addAudioTrack(to: composition, preferredTrackID: trackID)
            }
        }
        
        
        return composition
    }
    
    ///AVVideoComposition 可以用来指定渲染大小和渲染缩放，以及帧率。此外，还有一组存储了混合参数的 Instruction（指令）。有了这些混合参数之后，AVVideoComposition 可以通过自定义 Compositor（混合器） 来混合对应的图像帧。
    /**
     这个 AVComposition 有 VideoRenderLayer1、VideoRenderLayer2、VideoRenderLayer3 三个 VideoRenderLayer。转换过程包含以下步骤：

     在时间轴上记录每个 VideoRenderLayer 的起始时间点与结束时间点（如下图 T1-T6）。
     为每个时间间隔创建一个 Instruction，与时间间隔有交集的 VideoRenderLayer，都作为 Instruction 的混合参数（如下图 Instruction1-Instruction5）。
        T1 --- T2 --- T3 --- T4 --- T5 --- T6
          ｜       ｜      ｜      ｜      ｜
          Ins1  Ins2   Ins3   Ins4   Ins5
     */
    private func makeVideoComposition() -> AVMutableVideoComposition {
        //TODO:优化生成性能，如存在时返回
        
        //步骤1：将图层的开始时间和结束时间放在时间线上，每个间隔都是一条指令。然后按时间排序
        //确保时间为零
        var times: [CMTime] = []
        videoRenderLayers.forEach { videoRenderLayer in
            let startTime = videoRenderLayer.timeRangeInTimeline.start
            let endTime = videoRenderLayer.timeRangeInTimeline.end
            if !times.contains(startTime) {
                times.append(startTime)
            }
            if !times.contains(endTime) {
                times.append(endTime)
            }
        }
        times.sort { $0 < $1 }
        
        //步骤2：为每个间隔创建指令
        var instructions: [VideoCompositionInstruction] = []
        for index in 0..<times.count - 1 {
            let startTime = times[index]
            let endTime = times[index+1]
            let timeRange = CMTimeRange(start: startTime, end: endTime)
            //与时间间隔有交集的 VideoRenderLayer，都作为 Instruction 的混合参数
            var intersectingVideoRenderLayers: [VideoRenderLayer] = []//交叉视频渲染层
            videoRenderLayers.forEach { videoRenderLayer in
                if !videoRenderLayer.timeRangeInTimeline.intersection(timeRange).isEmpty {
                    intersectingVideoRenderLayers.append(videoRenderLayer)
                }
            }
            
            intersectingVideoRenderLayers.sort { $0.renderLayer.layerLevel < $1.renderLayer.layerLevel }
            let instruction = VideoCompositionInstruction(videoRenderLayers: intersectingVideoRenderLayers, timeRange: timeRange)
            instructions.append(instruction)
        }
        
        //创建视频合成。指定帧持续时间、渲染大小、指令和自定义视频合成器类。
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = renderComposition.frameDuration
        videoComposition.renderSize = renderComposition.renderSize
        videoComposition.instructions = instructions
        videoComposition.customVideoCompositorClass = VideoCompositor.self
        self.videoComposition = videoComposition
        
        return videoComposition
    }
    
    private func makeAudioMix() -> AVAudioMix {
        //TODO:优化生成性能，如存在时返回
        
        //将audioRenderLayers转换为inputParameters
        var inputParameters: [AVMutableAudioMixInputParameters] = []
        audioRenderLayersInTimeline.forEach { audioRenderLayer in
            let audioMixInputParameters = AVMutableAudioMixInputParameters()
            audioMixInputParameters.trackID = audioRenderLayer.trackID
            audioMixInputParameters.audioTimePitchAlgorithm = audioRenderLayer.pitchAlgorithm
            audioMixInputParameters.audioTapProcessor = audioRenderLayer.makeAudioTapProcessor()
            inputParameters.append(audioMixInputParameters)
        }

        //创建audioMix。指定inputParameters。
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters
        self.audioMix = audioMix
        
        return audioMix
    }
    
    ///在AVVideoCompositionCoreAnimationTool类-这是部分AVFoundation-是在为您的视频后处理阶段整合核心动画的主力。在此阶段，您可以在输出视频中添加叠加层(水印、文字、边框等)，背景和动画。
    private func makeAnimationTool() -> AVVideoCompositionCoreAnimationTool? {
        guard let animationLayer = renderComposition.animationLayer else { return nil }
        let parentLayer = CALayer()
        //已翻转几何图形
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: CGPoint.zero, size: renderComposition.renderSize)
        videoLayer.frame = CGRect(origin: CGPoint.zero, size: renderComposition.renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(animationLayer)
        let animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        return animationTool
    }
}
