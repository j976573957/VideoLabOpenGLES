//
//  KeyframeAnimation.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/6/7.
//

import CoreMedia

public struct KeyframeAnimation {
    ///描述要设置动画的特性的关键路径。
    public var keyPath: String
    
    ///为每个关键帧提供动画函数值的数组。
    public var values: [Float]
    
    ///定义动画节奏的“CMTime”对象的数组。
    ///每个时间对应于“values”数组中的一个值，时间基于层时间。
    public var keyTimes: [CMTime]
    
    ///TimingFunction对象的可选数组。[线性、慢进快出、快进慢出等]
    ///如果“values”数组定义了n个关键帧，则“timingFunctions”数组中应该有n-1个对象
    public var timingFunctions: [TimingFunction]
    
    ///初始化方法：使用keyPath、值、keyTimes、计时函数创建KeyframeAnimation
    public init(keyPath: String, values: [Float], keyTimes: [CMTime], timingFunctions: [TimingFunction]) {
        self.keyPath = keyPath
        self.values = values
        self.keyTimes = keyTimes
        self.timingFunctions = timingFunctions
    }
    
    ///相应时间的值，时间基于图层时间。
    public func value(at time: CMTime) -> Float? {
        let timeValue = time.seconds
        for index in 0..<keyTimes.count - 1 {
            let startTimeValue = keyTimes[index].seconds
            let endTimeValue = keyTimes[index + 1].seconds
            
            // 小于最短时间
            if index == 0 && timeValue < startTimeValue {
                return values[0]
            }
            
            // 大于最长时间
            if index == keyTimes.count - 2 && timeValue > endTimeValue {
                return values[index + 1]
            }
            
            //在中间
            if timeValue >= startTimeValue && timeValue <= endTimeValue {
                let progress = Float(timeValue - startTimeValue) / Float(endTimeValue - startTimeValue)
                let timingFunction = timingFunctions[index]
                let normalizedValue = timingFunction.value(at: progress)
                let fromValue = values[index]
                let toValue = values[index + 1]
                let value = fromValue + normalizedValue * (toValue - fromValue)
                return value
            }
        }
        
        return nil
    }
    
    ///
    public static func value(for keyPath: String, at time: CMTime, animations: [KeyframeAnimation]?) -> Float? {
        guard let animations = animations else {
            return nil
        }
        
        for animation in animations {
            if animation.keyPath == keyPath {
                if let value = animation.value(at: time) {
                    return value
                }
            }
        }
        
        return nil
    }
}


///动画接口
public protocol Animatable {
    ///动画数组
    var animations: [KeyframeAnimation]? { get set}
    
    ///更新动画值
    mutating func updateAnimationValues(at time: CMTime)
    
}
