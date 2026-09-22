// CaptureOutput.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 截图落地：裁剪、把标注烘焙进像素图、编码
///
/// 纯 CoreGraphics / ImageIO，不碰 AppKit —— 剪贴板与磁盘写入在 `ScreenshotDelivery`。
enum CaptureOutput {

    // MARK: - 裁剪

    /// 把某块显示器上的画布局部选区（point，原点左下）裁成像素图
    static func crop(_ snapshot: DisplaySnapshot, toLocalRect rect: CGRect) -> CGImage? {
        let pixelRect = snapshot.pixelRect(fromLocalRect: rect)
        let imageBounds = CGRect(origin: .zero, size: snapshot.pixelSize)
        let clamped = pixelRect.intersection(imageBounds)
        guard !clamped.isEmpty else { return nil }
        return snapshot.image.cropping(to: clamped)
    }

    // MARK: - 烘焙

    /// 把标注画到裁剪图上，返回最终图
    ///
    /// - Parameters:
    ///   - base: 裁剪后的底图
    ///   - annotations: **已经换算到底图像素坐标（原点左下）**的标注
    static func flatten(base: CGImage, annotations: [Annotation]) -> CGImage {
        guard !annotations.isEmpty else { return base }

        let width = base.width
        let height = base.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return base }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: bounds)
        AnnotationRenderer.draw(annotations, in: context, baseImage: base)
        return context.makeImage() ?? base
    }

    // MARK: - 缩放

    /// 把一张图缩放到指定尺寸（保持朝向）
    ///
    /// 遮罩的实时预览需要一张「点尺度」的底图给马赛克取样：预览里的坐标是点，
    /// 而冻结帧是像素，两者尺度不同，取样会错位。
    static func scaled(_ image: CGImage, to size: CGSize) -> CGImage {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    // MARK: - 编码

    static func pngData(_ image: CGImage) -> Data? {
        encode(image, as: .png)
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.9) -> Data? {
        encode(image, as: .jpeg, options: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    static func tiffData(_ image: CGImage) -> Data? {
        encode(image, as: .tiff)
    }

    static func data(_ image: CGImage, format: CaptureFormat) -> Data? {
        switch format {
        case .png: pngData(image)
        case .jpeg: jpegData(image)
        case .heic: encode(image, as: .heic)
        }
    }

    private static func encode(
        _ image: CGImage, as type: UTType, options: [CFString: Any]? = nil
    ) -> Data? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, options as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
