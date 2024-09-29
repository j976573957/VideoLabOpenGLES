//
//  AVAssetSource.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/12.
//

import AVFoundation

public class AVAssetSource: Source {
    
    private var asset: AVAsset?
    
    public init(asset: AVAsset) {
        self.asset = asset
        self.selectedTimeRange = .zero
        self.duration = .zero
    }
    
    // MARK: - Source
    public var selectedTimeRange: CMTimeRange
    
    public var duration: CMTime
    
    public var isLoaded: Bool = false
    
    public func load(completion: @escaping (NSError?) -> Void) {
        guard let asset = asset else {
            let error = NSError(domain: "com.source.load", code: 0, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Asset is nil", comment: "")])
            completion(error)
            return
        }
        
        asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { [weak self] in
            guard let `self` = self else { return }
            defer {
                self.isLoaded = true
            }
            
            var error: NSError?
            let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &error)
            if tracksStatus != .loaded {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
            
            let durationStatus = asset.statusOfValue(forKey: "duration", error: &error)
            if durationStatus != .loaded {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
            
            if let videoTrack = self.tracks(for: .video).first {
                // Make sure source's duration not beyond video track's duration
                self.duration = videoTrack.timeRange.duration
            } else {
                self.duration = asset.duration
            }
            self.selectedTimeRange = CMTimeRange(start: .zero, duration: self.duration)
            DispatchQueue.main.async {
                completion(nil)
            }
        }
        
        //iOS 16.0
//        Task {
//            do {
//                let (tracks, duration) = try await asset.load(.tracks, .duration)
//
//            } catch {
//
//            }
//        }
        
        
    }
    
    public func tracks(for type: AVMediaType) -> [AVAssetTrack] {
        guard let asset = asset else { return [] }
        return asset.tracks(withMediaType: type)
    }
    
    
}
