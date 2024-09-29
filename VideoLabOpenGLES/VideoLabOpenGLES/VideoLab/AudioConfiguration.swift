//
//  AudioConfiguration.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/11.
//

import AVFoundation

public struct AudioConfiguration {
    ///一种用于在速率变化时设置音频音高的算法。
    public var pitchAlgorithm: AVAudioTimePitchAlgorithm = .varispeed
    public var volumeRamps: [VolumeRamp] = []
    
    public init(pitchAlgorithm: AVAudioTimePitchAlgorithm = .varispeed, volumeRamps: [VolumeRamp] = []) {
        self.pitchAlgorithm = pitchAlgorithm
        self.volumeRamps = volumeRamps
    }
}

public struct VolumeRamp {
    public var startVolume: Float
    public var endVolume: Float
    public var timeRange: CMTimeRange
    public var timingFunction: TimingFunction = .linear
    
    public init(startVolume: Float, endVolume: Float, timeRange: CMTimeRange, timingFunction: TimingFunction = .linear) {
        self.startVolume = startVolume
        self.endVolume = endVolume
        self.timeRange = timeRange
        self.timingFunction = timingFunction
    }
}
