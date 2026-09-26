import SwiftUI
import AppKit

func hex(_ h: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: a)
}

// macOS 图标网格：1024 画布，824 的圆角方块居中，圆角约 185，带轻投影。
struct Squircle<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            content
                .frame(width: 824, height: 824)
                .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        }
        .frame(width: 1024, height: 1024)
    }
}

struct Arc: Shape {
    var from: Double, to: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        return p
    }
}

struct PlayGlyph: Shape {
    func path(in r: CGRect) -> Path {
        // 圆角三角形
        var p = Path()
        let a = CGPoint(x: r.minX + r.width * 0.12, y: r.minY)
        let b = CGPoint(x: r.maxX, y: r.midY)
        let c = CGPoint(x: r.minX + r.width * 0.12, y: r.maxY)
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.closeSubpath()
        return p
    }
}

// A：深色底 + 三道额度圆环 + 中心播放键
struct IconA: View {
    var body: some View {
        Squircle {
            ZStack {
                LinearGradient(colors: [hex(0x1C1D24), hex(0x0A0B0F)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [hex(0xFF6A3D, 0.25), .clear], center: .init(x: 0.25, y: 0.3), startRadius: 0, endRadius: 520)
                RadialGradient(colors: [hex(0x2F7BFF, 0.22), .clear], center: .init(x: 0.85, y: 0.85), startRadius: 0, endRadius: 480)
                ForEach(0..<3) { i in
                    let d = 560.0 - Double(i) * 132
                    let cols: [(UInt32, UInt32)] = [(0xFF5A36, 0xFF9A6E), (0xFF2D6F, 0xFF7AA2), (0x2F7BFF, 0x64D2FF)]
                    let end: [Double] = [300, 250, 210]
                    ZStack {
                        Circle().stroke(hex(cols[i].0, 0.16), lineWidth: 50)
                        Arc(from: 0, to: end[i]).stroke(LinearGradient(colors: [hex(cols[i].1), hex(cols[i].0)], startPoint: .top, endPoint: .bottom),
                                                        style: StrokeStyle(lineWidth: 50, lineCap: .round))
                    }
                    .frame(width: d, height: d)
                }
                PlayGlyph().fill(.white).frame(width: 110, height: 124).offset(x: 10)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            }
        }
    }
}

// B：海上日落
struct IconB: View {
    var body: some View {
        Squircle {
            ZStack(alignment: .top) {
                LinearGradient(colors: [hex(0x1E4C5E), hex(0x6B6E8A), hex(0xF08A63), hex(0xFBC89A)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.62))
                Circle().fill(LinearGradient(colors: [hex(0xFFF1D6), hex(0xFFD9A8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 330, height: 330).offset(y: 330)
                    .shadow(color: hex(0xFFC98F, 0.8), radius: 60)
                VStack(spacing: 0) {
                    Spacer().frame(height: 505)
                    ZStack(alignment: .top) {
                        LinearGradient(colors: [hex(0x1F5763), hex(0x0B2A33)], startPoint: .top, endPoint: .bottom)
                        VStack(spacing: 22) {
                            ForEach(0..<5) { i in
                                Capsule().fill(hex(0xFFD9A8, 0.75 - Double(i) * 0.13)).frame(width: 260 - CGFloat(i) * 42, height: 10)
                            }
                        }
                        .padding(.top, 34)
                    }
                }
            }
        }
    }
}

// C：封面色渐变底 + 白色播放键 + 一圈白色进度环
struct IconC: View {
    var body: some View {
        Squircle {
            ZStack {
                hex(0x3B2250)
                RadialGradient(colors: [hex(0xFF7A59), .clear], center: .init(x: 0.08, y: 0.08), startRadius: 0, endRadius: 640)
                RadialGradient(colors: [hex(0xB84DFF), .clear], center: .init(x: 1.0, y: 0.12), startRadius: 0, endRadius: 600)
                RadialGradient(colors: [hex(0x22C3D0), .clear], center: .init(x: 0.78, y: 1.05), startRadius: 0, endRadius: 620)
                RadialGradient(colors: [hex(0xFFB35C, 0.85), .clear], center: .init(x: 0.0, y: 1.0), startRadius: 0, endRadius: 460)
                LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
                ZStack {
                    Circle().stroke(.white.opacity(0.3), lineWidth: 30)
                    Arc(from: 0, to: 250).stroke(.white, style: StrokeStyle(lineWidth: 30, lineCap: .round))
                }
                .frame(width: 540, height: 540)
                Circle().fill(.white).frame(width: 316, height: 316)
                    .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
                Image(systemName: "play.fill").font(.system(size: 132, weight: .bold)).foregroundStyle(hex(0x3A2447)).offset(x: 10)
            }
        }
    }
}

@MainActor func save(_ v: some View, _ name: String) {
    let r = ImageRenderer(content: v.frame(width: 1024, height: 1024))
    r.scale = 1
    guard let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
          let png = rep.representation(using: .png, properties: [:]) else { print("fail", name); return }
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/" + name))
    print("wrote", name)
}
MainActor.assumeIsolated {
    save(IconA(), "A.png"); save(IconB(), "B.png"); save(IconC(), "C.png")
}
