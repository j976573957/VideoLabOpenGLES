//
//  AudioRenderLayerGroup.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/14.
//

import AVFoundation

class AudioRenderLayerGroup: AudioRenderLayer {
    var audioRenderLayers: [AudioRenderLayer] = []
    private var recursiveAudioRenderLayersInGroup: [AudioRenderLayer] = []
    
    override init(renderLayer: RenderLayer) {
        super.init(renderLayer: renderLayer)
        generateAudioRenderLayers()
    }
    
    // MARK: - Public
    ///递归音频渲染层
    public func recursiveAudioRenderLayers() -> [AudioRenderLayer] {
        var recursiveAudioRenderLayers: [AudioRenderLayer] = []
        for audioRenderLayer in audioRenderLayers {
            audioRenderLayer.timeRangeInTimeline.start = CMTimeAdd(audioRenderLayer.timeRangeInTimeline.start, timeRangeInTimeline.start)
            if let audioRenderLayerGroup = audioRenderLayer as? AudioRenderLayerGroup {
                recursiveAudioRenderLayers += audioRenderLayerGroup.recursiveAudioRenderLayers()
            } else {
                recursiveAudioRenderLayers.append(audioRenderLayer)
            }
        }
        self.recursiveAudioRenderLayersInGroup = recursiveAudioRenderLayers
        
        return recursiveAudioRenderLayers
    }
    
    
    // MARK: - Private
    ///通过 renderLayer 生成对应的 AudioRenderLayer
    private func generateAudioRenderLayers() {
        guard let renderLayerGroup = renderLayer as? RenderLayerGroup else {
            return
        }
        
        for subRenderLayer in renderLayerGroup.layers {
            if subRenderLayer is RenderLayerGroup {
                let audioRenderLayerGroup = AudioRenderLayerGroup(renderLayer: subRenderLayer)
                audioRenderLayerGroup.surperLayer = self
                audioRenderLayers.append(audioRenderLayerGroup)
            } else if subRenderLayer.canBeConvertedToAudioRenderLayer() {
                let audioRenderLayer = AudioRenderLayer(renderLayer: subRenderLayer)
                audioRenderLayer.surperLayer = self
                audioRenderLayers.append(audioRenderLayer)
            }
        }
    }
}


extension AudioRenderLayer {
    class func makeAudioRenderLayer(renderLayer: RenderLayer) -> AudioRenderLayer {
        if renderLayer is RenderLayerGroup {
            return AudioRenderLayerGroup(renderLayer: renderLayer)
        } else {
            return AudioRenderLayer(renderLayer: renderLayer)
        }
    }
}

extension RenderLayerGroup {
    override func canBeConvertedToAudioRenderLayer() -> Bool {
        for renderLayer in layers {
            if renderLayer.canBeConvertedToAudioRenderLayer() {
                return true
            }
        }
        return false
    }
}
