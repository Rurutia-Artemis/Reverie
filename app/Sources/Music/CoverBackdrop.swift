import AppKit
import CoreImage

/// 音乐页背景：把封面缩小、重度模糊、稍微提饱和，铺满整页，封面的颜色就从封面往外延展开。
/// 在小图上模糊（96px）再放大显示：只算一次、结果固定，离屏出图也不会出块。
struct CoverBackdrop: Equatable {
    let image: NSImage
    let luminance: Double     // 平均亮度 0–1，决定盖多深的遮罩，保证文字看得清

    static func make(from cover: NSImage) -> CoverBackdrop? {
        guard let tiff = cover.tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let side: CGFloat = 96
        let scale = side / max(ci.extent.width, ci.extent.height)
        let small = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 9)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25])
            .cropped(to: small.extent)
        let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        guard let cg = ctx.createCGImage(blurred, from: small.extent) else { return nil }

        // 平均亮度：CIAreaAverage 出 1×1 像素。
        var px = [UInt8](repeating: 0, count: 4)
        let avg = blurred.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: small.extent)])
        ctx.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let lum = (0.2126 * Double(px[0]) + 0.7152 * Double(px[1]) + 0.0722 * Double(px[2])) / 255
        return CoverBackdrop(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), luminance: lum)
    }

    static func == (a: CoverBackdrop, b: CoverBackdrop) -> Bool { a.image === b.image }
}
