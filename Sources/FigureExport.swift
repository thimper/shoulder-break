import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 调试/文档用:把某个动作的循环动画导成 GIF 或者一张多帧拼图。
/// 不参与正常运行流程。
enum FigureExport {
    private static let accent = Color(red: 0.42, green: 0.78, blue: 0.72)
    private static let dim = Color(red: 0.58, green: 0.62, blue: 0.67)
    private static let bg = Color(red: 0.05, green: 0.07, blue: 0.10)

    static func motion(named name: String) -> ExerciseMotion? {
        switch name {
        case "pendulum": return .pendulum
        case "wallwalk": return .wallWalk
        case "crossbody": return .crossBody
        case "rotation": return .externalRotation
        case "squeeze": return .scapularSqueeze
        default: return nil
        }
    }

    /// 渲染单帧成 CGImage
    private static func frame(_ motion: ExerciseMotion, phase: Double,
                              mirrored: Bool, side: CGFloat) -> CGImage? {
        let view = ZStack {
            bg
            StickFigureCanvas(motion: motion, phase: phase, mirrored: mirrored,
                              bothSides: false, accent: accent, dim: dim)
                .padding(side * 0.06)
        }
        .frame(width: side, height: side)

        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: side, height: side)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        win.contentView = host
        win.orderBack(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.frame = CGRect(x: 0, y: 0, width: side, height: side)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        win.orderOut(nil)
        return rep.cgImage
    }

    /// 导成循环 GIF
    static func gif(_ motion: ExerciseMotion, to path: String,
                    frames: Int = 30, side: CGFloat = 320, mirrored: Bool = false) {
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames, nil) else {
            print("创建 GIF 失败"); return
        }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let delay = motion.cycleSeconds / Double(frames)
        for i in 0..<frames {
            let phase = Double(i) / Double(frames)
            guard let img = frame(motion, phase: phase, mirrored: mirrored, side: side) else { continue }
            CGImageDestinationAddImage(dest, img, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
            ] as CFDictionary)
        }
        if CGImageDestinationFinalize(dest) {
            print("已导出 GIF:\(path)")
        } else {
            print("写入 GIF 失败")
        }
    }

    /// 把一圈动作摊成一排关键帧,方便一眼检查动作对不对
    static func contactSheet(_ motion: ExerciseMotion, to path: String,
                             frames: Int = 6, side: CGFloat = 300, mirrored: Bool = false) {
        var images: [CGImage] = []
        for i in 0..<frames {
            let phase = Double(i) / Double(frames)
            if let img = frame(motion, phase: phase, mirrored: mirrored, side: side) {
                images.append(img)
            }
        }
        guard !images.isEmpty else { print("没渲染出帧"); return }
        let w = images[0].width, h = images[0].height
        let total = CGSize(width: w * images.count, height: h)
        guard let ctx = CGContext(data: nil, width: Int(total.width), height: Int(total.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        for (i, img) in images.enumerated() {
            ctx.draw(img, in: CGRect(x: i * w, y: 0, width: w, height: h))
        }
        guard let out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
        print("已导出关键帧拼图:\(path)")
    }
}
