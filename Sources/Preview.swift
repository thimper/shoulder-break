import AppKit
import SwiftUI

/// 调试用:把黑幕界面离屏渲染成 PNG,方便在不占用屏幕的情况下检查排版。
/// 不参与正常运行流程。
enum Preview {
    static func render(to path: String, width: CGFloat = 2560, height: CGFloat = 1440,
                       forced: Bool, elapsed: Int, escProgress: Double,
                       affectedSide: String = "right") {
        let model = OverlayModel()
        let total = 180
        let plan = ExerciseLibrary.plan(totalSeconds: total)
        model.exercises = plan
        model.totalSeconds = total
        model.remaining = max(0, total - elapsed)
        model.forced = forced
        model.snoozeRemaining = forced ? 0 : 2
        model.escProgress = escProgress
        model.escapeHoldSeconds = 10
        model.mirrored = (affectedSide == "left")
        model.bothSides = (affectedSide == "both")
        model.breathingOn = true
        model.ambientAvailable = true
        model.startedAt = Date().addingTimeInterval(-2.4)   // 定在吸气快满的位置

        // 按已过秒数定位到对应的动作步骤
        var acc = 0
        var idx = 0
        for (i, ex) in plan.enumerated() {
            if elapsed < acc + ex.seconds { idx = i; break }
            acc += ex.seconds
            idx = i
        }
        model.stepIndex = idx
        model.stepTotal = plan[idx].seconds
        model.stepRemaining = max(0, acc + plan[idx].seconds - elapsed)

        let size = CGSize(width: width, height: height)
        let scale = min(max(height / 900.0, 0.72), 1.7)
        let host = NSHostingView(rootView: OverlayView(model: model, scale: scale))
        host.frame = CGRect(origin: .zero, size: size)

        let win = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderBack(nil)

        // 给 SwiftUI 一个 runloop 完成布局,否则渲染出来是空的
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        // NSHostingView 会按内容的理想尺寸把自己撑大,渲染前必须拉回目标画布尺寸
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.frame = CGRect(origin: .zero, size: size)

        guard let rep = host.bitmapImageRepForCachingDisplay(in: CGRect(origin: .zero, size: size)) else {
            print("渲染失败:拿不到位图"); return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("渲染失败:PNG 编码失败"); return
        }
        try? data.write(to: URL(fileURLWithPath: path))
        win.orderOut(nil)
        print("已渲染:\(path)")
    }
}
