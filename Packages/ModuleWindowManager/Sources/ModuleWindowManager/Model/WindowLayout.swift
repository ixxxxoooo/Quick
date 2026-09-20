// WindowLayout.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 窗口布局枚举
enum WindowLayout: String, CaseIterable, Sendable {
    case leftHalf = "left"
    case rightHalf = "right"
    case topHalf = "top"
    case bottomHalf = "bottom"
    case maximize = "maximize"
    case center = "center"
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"

    var title: String {
        switch self {
        case .leftHalf: "左半屏"
        case .rightHalf: "右半屏"
        case .topHalf: "上半屏"
        case .bottomHalf: "下半屏"
        case .maximize: "最大化"
        case .center: "居中"
        case .topLeft: "左上角"
        case .topRight: "右上角"
        case .bottomLeft: "左下角"
        case .bottomRight: "右下角"
        }
    }

    var description: String {
        switch self {
        case .leftHalf: "将窗口移到屏幕左半部分"
        case .rightHalf: "将窗口移到屏幕右半部分"
        case .topHalf: "将窗口移到屏幕上半部分"
        case .bottomHalf: "将窗口移到屏幕下半部分"
        case .maximize: "窗口最大化"
        case .center: "窗口居中"
        case .topLeft: "将窗口移到左上角"
        case .topRight: "将窗口移到右上角"
        case .bottomLeft: "将窗口移到左下角"
        case .bottomRight: "将窗口移到右下角"
        }
    }

    var icon: String {
        switch self {
        case .leftHalf: "rectangle.leadinghalf.inset.filled"
        case .rightHalf: "rectangle.trailinghalf.inset.filled"
        case .topHalf: "rectangle.tophalf.inset.filled"
        case .bottomHalf: "rectangle.bottomhalf.inset.filled"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .center: "rectangle.center.inset.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        }
    }

    var keywords: [String] {
        switch self {
        case .leftHalf: ["左半屏", "左半", "left half", "left"]
        case .rightHalf: ["右半屏", "右半", "right half", "right"]
        case .topHalf: ["上半屏", "上半", "top half"]
        case .bottomHalf: ["下半屏", "下半", "bottom half"]
        case .maximize: ["最大化", "全屏", "maximize", "max"]
        case .center: ["居中", "center"]
        case .topLeft: ["左上角", "左上", "top left"]
        case .topRight: ["右上角", "右上", "top right"]
        case .bottomLeft: ["左下角", "左下", "bottom left"]
        case .bottomRight: ["右下角", "右下", "bottom right"]
        }
    }

    /// 计算布局在屏幕中的比例（x, y, w, h 相对于屏幕）
    var rect: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        switch self {
        case .leftHalf: (0, 0, 0.5, 1.0)
        case .rightHalf: (0.5, 0, 0.5, 1.0)
        case .topHalf: (0, 0, 1.0, 0.5)
        case .bottomHalf: (0, 0.5, 1.0, 0.5)
        case .maximize: (0, 0, 1.0, 1.0)
        case .center: (0.15, 0.1, 0.7, 0.8)
        case .topLeft: (0, 0, 0.5, 0.5)
        case .topRight: (0.5, 0, 0.5, 0.5)
        case .bottomLeft: (0, 0.5, 0.5, 0.5)
        case .bottomRight: (0.5, 0.5, 0.5, 0.5)
        }
    }
}
