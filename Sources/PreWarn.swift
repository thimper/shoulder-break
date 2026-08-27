import AppKit
import SwiftUI

/// 黑幕前的预告小横幅。用不抢焦点的面板,右上角飘一下,不挡你手上的活。
/// 目的是让你有几十秒把当前这行字打完,而不是屏幕突然一黑。
final class PreWarnController {
    static let shared = PreWarnController()
    private init() {}

    private var panel: NSPanel?
    private var timer: Timer?
    private let model = PreWarnModel()

    func show(seconds: Int, playSound: Bool) {
        hide()
        guard seconds > 0 else { return }
        model.remaining = seconds

        // 同样用 screens.first 锁定菜单栏所在的主屏,而不是随活动窗口漂移的 NSScreen.main
        guard let screen = NSScreen.screens.first else { return }
        let size = CGSize(width: 320, height: 92)
        let origin = CGPoint(x: screen.visibleFrame.maxX - size.width - 24,
                             y: screen.visibleFrame.maxY - size.height - 16)

        let p = NSPanel(contentRect: CGRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true          // 点击穿透,不影响你操作
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false

        let host = NSHostingView(rootView: PreWarnView(model: model))
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        p.orderFrontRegardless()
        panel = p

        if playSound { NSSound(named: NSSound.Name("Ping"))?.play() }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.remaining -= 1
            if self.model.remaining <= 0 { self.hide() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func hide() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    var isShowing: Bool { panel != nil }
}

final class PreWarnModel: ObservableObject {
    @Published var remaining: Int = 20
}

struct PreWarnView: View {
    @ObservedObject var model: PreWarnModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 3)
                Text("\(max(0, model.remaining))")
                    .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("准备活动肩膀")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(max(0, model.remaining)) 秒后进入活动模式")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.13).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 0.42, green: 0.78, blue: 0.72).opacity(0.35), lineWidth: 1)
                )
        )
    }
}
