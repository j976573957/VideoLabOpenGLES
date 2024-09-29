//
//  TextAnimationLayer.swift
//  VideoLabOpenGLES
//
//  Created by Mac on 2024/8/28.
//
// iOS文本布局探讨之一——文本布局框架TextKit浅析： https://cloud.tencent.com/developer/article/1186305

import UIKit
import AVFoundation

class TextAnimationLayer: CALayer, NSLayoutManagerDelegate {
    ///对应要渲染展示的内容
    private let textStorege: NSTextStorage = NSTextStorage()
    ///布局操作管理者
    private let layoutManager: NSLayoutManager = NSLayoutManager()
    ///对应渲染的尺寸位置和形状信息
    private let textContainer: NSTextContainer = NSTextContainer()
    private var textSize: CGSize = .zero
    private var animationLayers: [CATextLayer] = []
    
    public var attributedText: NSAttributedString {
        get {
            return textStorege as NSAttributedString
        }
        set {
            textStorege.setAttributedString(newValue)
        }
    }
    
    override var bounds: CGRect {
        get {
            super.bounds
        }
        set {
            textContainer.size = newValue.size
            super.bounds = newValue
        }
    }
    
    override init() {
        super.init()
        setupTextkit()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        setupTextkit()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public
    ///将动画添加到层中，子类需要重写此方法以自定义动画
    ///- Parameter layers：拆分字母或单词对应的层
    func addAnimations(to layers: [CATextLayer]) {
        let animationGroup = CAAnimationGroup()
        animationGroup.duration = 15
        animationGroup.beginTime = AVCoreAnimationBeginTimeAtZero
        animationGroup.fillMode = .both
        animationGroup.isRemovedOnCompletion = false
        self.add(animationGroup, forKey: "animationGroup")
    }
    
    // MARK: - Private
    private func setupTextkit() {
        textStorege.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.delegate = self
        textContainer.size = .zero
    }
    
    ///更新动画层
    private func updateAnimationLayers() {
        if textContainer.size.equalTo(.zero) || attributedText.length == 0 {
            return
        }
        
        //1.删除旧动画层
        for layer in animationLayers {
            layer.removeAllAnimations()
            layer.removeFromSuperlayer()
        }
        animationLayers.removeAll()
        self.removeAllAnimations()
        
        //2.拆分字母或单词以生成相应的图层
        let string = attributedText.string
        string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byComposedCharacterSequences) { [weak self] (subString, substringRange, _, _) in
            guard let `self` = self else { return }
            let glyphRange = NSRange(substringRange, in: string)//字形范围
            let textRect = self.layoutManager.boundingRect(forGlyphRange: glyphRange, in: self.textContainer)
            let textLayer = CATextLayer()
            textLayer.frame = textRect
            textLayer.string = self.attributedText.attributedSubstring(from: glyphRange)
            self.animationLayers.append(textLayer)
            self.addSublayer(textLayer)
        }
        
        //3.向图层添加动画
        addAnimations(to: animationLayers)
    }
    
    // MARK: - NSLayoutManagerDelegate
    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        if textContainer == nil {
            return
        }
        
        updateAnimationLayers()
    }
}
