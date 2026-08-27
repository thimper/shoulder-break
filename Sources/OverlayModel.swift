import Foundation
import SwiftUI

enum OverlayResult {
    case completed   // 倒计时走完
    case snoozed     // 用掉一次延迟
    case escaped     // 长按 Esc 强制解除
}

/// 黑幕界面的数据源。控制器改这里的值,SwiftUI 自动重绘。
final class OverlayModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var totalSeconds: Int = 180
    @Published var remaining: Int = 180
    @Published var stepIndex: Int = 0
    @Published var stepRemaining: Int = 0
    @Published var stepTotal: Int = 1

    /// true = 延迟额度已用完,这一次躲不掉
    @Published var forced: Bool = false
    @Published var snoozeRemaining: Int = 0

    /// 长按 Esc 的进度,0...1
    @Published var escProgress: Double = 0
    @Published var escapeHoldSeconds: Int = 10

    @Published var finished: Bool = false

    /// 患侧在画面哪边(示意图高亮用)
    @Published var mirrored: Bool = false
    @Published var bothSides: Bool = false

    /// 呼吸引导:圆环和背景音用同一个起点算相位,保证看到的和听到的一致
    @Published var breathingOn: Bool = false
    @Published var startedAt: Date = Date()
    @Published var ambientAvailable: Bool = false
    @Published var muted: Bool = false
    var onToggleMute: (() -> Void)?

    var onSnooze: (() -> Void)?

    var currentExercise: Exercise? {
        guard stepIndex >= 0 && stepIndex < exercises.count else { return nil }
        return exercises[stepIndex]
    }
}

func mmss(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
}
