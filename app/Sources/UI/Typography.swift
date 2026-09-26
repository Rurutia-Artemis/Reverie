import SwiftUI
import AppKit
import CoreText

/// 两套字体方案：系统圆体（SF Pro Rounded + 圆体），阿里妈妈方圆体（可变字体，可调粗细与圆角）。
enum FontScheme: String, CaseIterable, Identifiable {
    case systemRounded
    case alimama
    var id: String { rawValue }
    var title: String {
        switch self {
        case .systemRounded: return "系统圆体（SF Pro Rounded + 圆体）"
        case .alimama: return "阿里妈妈方圆体"
        }
    }
}

struct TypeSettings: Equatable {
    var scheme: FontScheme = .systemRounded
    var weightAdjust: Double = 0      // 方圆体整体粗细，-3…+3，每档 50
    var bevel: Double = 60            // 方圆体圆角，1…100
    var japanese: String = "Hiragino Sans"
}

/// 渲染时读取的当前字体设置；SettingsStore 改动后同步到这里，并通过发布属性触发重绘。
var typeSettings = TypeSettings()

enum VariableFont {
    static let fileName = "AlimamaFangYuanTiVF-Thin.ttf"
    private static let wght: UInt32 = 0x7767_6874   // 'wght'
    private static let bevl: UInt32 = 0x4245_564C   // 'BEVL'
    private static var cache: [String: Font] = [:]

    static let baseDescriptor: CTFontDescriptor? = {
        let candidates = [
            Bundle.main.resourcePath.map { $0 + "/Fonts/" + fileName },
            Config.projectDir + "/app/Resources/Fonts/" + fileName,
        ].compactMap { $0 }
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path) as CFURL
            if let ds = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor], let d = ds.first { return d }
        }
        return nil
    }()

    static var isAvailable: Bool { baseDescriptor != nil }

    static func font(size: CGFloat, weight: Double, bevel: Double) -> Font? {
        guard let base = baseDescriptor else { return nil }
        let w = min(700, max(200, weight)), b = min(100, max(1, bevel))
        let key = "\(size)-\(w)-\(b)"
        if let f = cache[key] { return f }
        var d = CTFontDescriptorCreateCopyWithVariation(base, NSNumber(value: wght), CGFloat(w))
        d = CTFontDescriptorCreateCopyWithVariation(d, NSNumber(value: bevl), CGFloat(b))
        let f = Font(CTFontCreateWithFontDescriptor(d, size, nil))
        cache[key] = f
        return f
    }
}

enum Script { case latin, cjk, kana }

private func scriptOf(_ ch: Character) -> Script {
    for v in ch.unicodeScalars.map(\.value) {
        if (0x3040...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) || (0xFF66...0xFF9D).contains(v) { return .kana }
        if (0x2E80...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || (0xFF00...0xFF65).contains(v) || (0x3000...0x303F).contains(v) { return .cjk }
    }
    return .latin
}

/// 按当前方案取某个脚本的字体。bold 对应界面里的粗字（标题、数字），否则是常规字。
func schemeFont(_ script: Script, size: CGFloat, bold: Bool, weight: Font.Weight? = nil) -> Font {
    let s = typeSettings
    if script == .kana {
        return .custom(s.japanese, size: size).weight(bold ? .bold : .regular)
    }
    switch s.scheme {
    case .systemRounded:
        if script == .cjk { return .custom(bold ? "STYuanti-SC-Bold" : "STYuanti-SC-Regular", size: size) }
        return .system(size: size, weight: weight ?? (bold ? .bold : .semibold), design: .rounded)
    case .alimama:
        var base: Double = bold ? 640 : 430
        if weight == .heavy || weight == .black { base = 700 }
        if let f = VariableFont.font(size: size, weight: base + s.weightAdjust * 50, bevel: s.bevel) { return f }
        return schemeFontFallback(script, size: size, bold: bold)
    }
}

private func schemeFontFallback(_ script: Script, size: CGFloat, bold: Bool) -> Font {
    script == .cjk ? .custom(bold ? "STYuanti-SC-Bold" : "STYuanti-SC-Regular", size: size)
        : .system(size: size, weight: bold ? .bold : .semibold, design: .rounded)
}

/// 混排文字：中文、日文假名、拉丁与数字各用各的字体。
func tx(_ s: String, _ size: CGFloat, bold: Bool = true, weight: Font.Weight? = nil, cjkTracking: CGFloat = 0, latinTracking: CGFloat = 0) -> Text {
    var out = AttributedString()
    var run = ""
    var runScript: Script? = nil
    func flush() {
        guard !run.isEmpty, let sc = runScript else { return }
        var a = AttributedString(run)
        a.font = schemeFont(sc, size: size, bold: bold, weight: weight)
        a.tracking = sc == .latin ? latinTracking : cjkTracking
        out += a
        run = ""
    }
    for ch in s {
        let sc = scriptOf(ch)
        if runScript == nil { runScript = sc }
        if sc != runScript { flush(); runScript = sc }
        run.append(ch)
    }
    flush()
    return Text(out)
}

/// 纯数字与符号（百分比、时间）。
func num(_ s: String, _ size: CGFloat, weight: Font.Weight = .bold) -> Text {
    Text(s).font(schemeFont(.latin, size: size, bold: weight != .semibold && weight != .medium && weight != .regular, weight: weight).monospacedDigit())
}
