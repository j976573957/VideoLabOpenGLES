//
//  AudioRenderLayer.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/12.
//

import AVFoundation
import Accelerate
/**
 AudioRenderLayer 是框架内部对象，包含一个 RenderLayer，主要负责将 RenderLayer 的音频轨道添加到 AVComposition 中。可转换为 AudioRenderLayer 的 RenderLayer 只需满足一个条件：Source 包含音频轨道。

 AudioRenderLayerGroup 是 RenderLayerGroup 对应音频的框架内部对象，包含一个 RenderLayerGroup。可转换为 AudioRenderLayerGroup 的 RenderLayerGroup 只需满足一个条件：包含的 RenderLayer 组有一个可以转化为 AudioRenderLayer。
 */

class AudioRenderLayer {
    ///渲染层
    let renderLayer: RenderLayer
    ///父类Layer
    var surperLayer: AudioRenderLayer?
    ///轨道ID
    var trackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    ///时间范围
    var timeRangeInTimeline: CMTimeRange
    ///一种用于在速率变化时设置音频音高的算法。
    var pitchAlgorithm: AVAudioTimePitchAlgorithm? {
        return renderLayer.audioConfiguration.pitchAlgorithm
    }
    
    ///初始化
    init(renderLayer: RenderLayer) {
        self.renderLayer = renderLayer
        self.timeRangeInTimeline = renderLayer.timeRange
    }
    
    ///添加音频轨道到合成中
    func addAudioTrack(to composition: AVMutableComposition, preferredTrackID: CMPersistentTrackID) {
        guard let source = renderLayer.source else { return }
        guard let assetTrack = source.tracks(for: .audio).first else { return }
        let compositionTrack: AVMutableCompositionTrack? = {
            if let compositionTrack = composition.track(withTrackID: preferredTrackID) {
                return compositionTrack
            }
            return composition.addMutableTrack(withMediaType: .audio, preferredTrackID: preferredTrackID)
        }()
        
        if let compositionTrack = compositionTrack {
            do {
                try compositionTrack.insertTimeRange(source.selectedTimeRange, of: assetTrack, at: timeRangeInTimeline.start)
            } catch {
                
            }
        }
    }
    
    ///实时音频处理需要实现 MTAudioProcessingTap ，传入到 AVAudioMix 里
    func makeAudioTapProcessor() -> MTAudioProcessingTap? {
        guard renderLayer.canBeConvertedToAudioRenderLayer() else {
            return nil
        }
        
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: nil,
            unprepare: nil,
            process: tapProcess)
        
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        if status != noErr {
            print("Failed to create audio processing tap")
        }
        return tap?.takeRetainedValue()
    }
    
    // MARK: - Private
    private func processAudio(_ bufferListInOut: UnsafeMutablePointer<AudioBufferList>, timeRange: CMTimeRange) {
        guard timeRange.duration.isValid else {
            return
        }
        if timeRangeInTimeline.intersection(timeRange).isEmpty {
            return
        }
        
        let volumeRamps = renderLayer.audioConfiguration.volumeRamps
        if volumeRamps.count > 0 {
            let processTime = timeRange.end.seconds - timeRangeInTimeline.start.seconds
            var processVolumeRamp: VolumeRamp?
            for volumeRamp in volumeRamps {
                if processTime < volumeRamp.timeRange.start.seconds {
                    return
                }
                processVolumeRamp = volumeRamp
            }
            
            if let processVolumeRamp = processVolumeRamp {
                let startTimeValue = processVolumeRamp.timeRange.start.seconds
                let endTimeValue = processVolumeRamp.timeRange.end.seconds
                var progress = (processTime - startTimeValue) / (endTimeValue - startTimeValue)
                if progress > 1.0 {
                    progress = 1.0
                }
                let normalizedValue = processVolumeRamp.timingFunction.value(at: Float(progress))
                let startVolume = processVolumeRamp.startVolume
                let endVolume = processVolumeRamp.endVolume
                let volume = startVolume + normalizedValue * (endVolume - startVolume)
                
                changeAudio(bufferListInOut, volume: volume)
            }
        }
        
        if let surperLayer = surperLayer {
            surperLayer.processAudio(bufferListInOut, timeRange: timeRange)
        }
    }
    
    private func changeAudio(_ bufferListInOut: UnsafeMutablePointer<AudioBufferList>, volume: Float) {
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
        for bufferIndex in 0..<bufferList.count {
            let audioBuffer = bufferList[bufferIndex]
            if let rawBuffer = audioBuffer.mData {
                let floatRawPointer = rawBuffer.assumingMemoryBound(to: Float.self)
                let frameCount = UInt(audioBuffer.mDataByteSize) / UInt(MemoryLayout<Float>.size)
                var volume = volume
                vDSP_vsmul(floatRawPointer, 1, &volume, floatRawPointer, 1, frameCount)
            }
        }
    }
    
    // MARK: - MTAudioProcessingTapCallbacks
    private let tapInit: MTAudioProcessingTapInitCallback = { (tap, clientInfo, tapStorageOut) in
        tapStorageOut.pointee = clientInfo
    }
    
    let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
        Unmanaged<AudioRenderLayer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
    }
    
    private let tapProcess: MTAudioProcessingTapProcessCallback = { (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        var timeRange: CMTimeRange = .zero
        let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, &timeRange, numberFramesOut)
        if status != noErr {
            print("Failed to get source audio")
            return
        }
        
        let audioRenderLayer = Unmanaged<AudioRenderLayer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        audioRenderLayer.processAudio(bufferListInOut, timeRange: timeRange)
    }
    
}

extension RenderLayer {
    @objc func canBeConvertedToAudioRenderLayer() -> Bool {
        return source?.tracks(for: .audio).first != nil
    }
}
