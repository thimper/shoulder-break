import AppKit
import SwiftUI

/// 无边框窗口默认拿不到键盘焦点,必须重写这两个属性,
/// 否则按键吞不掉、Esc 逃生阀也失灵。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 黑幕里跟声音有关的一组设置,打包传进来免得参数列表越拖越长
struct AudioSettings {
    var ambientStyle: AmbientStyle
    var ambientFile: String
    var ambientEnabled: Bool
    var ambientVolume: Double
    var stepChimeEnabled: Bool
    var chimeVolume: Double
    var breathingGuide: Bool
    var breathInSeconds: Double
    var breathOutSeconds: Double
}

final class OverlayController {
    static let shared = OverlayController()
    private init() {}

    /// 展台模式(kiosk mode):苹果给公共展示机准备的一组开关。
    /// 这个组合里 hideMenuBar 和 disableProcessSwitching 都依赖 hideDock,
    /// 组合非法会直接抛 ObjC 异常崩掉,所以固定用这一套、不要随意增删。
    /// 刻意不含 disableSessionTermination —— 那会连关机注销都禁掉,
    /// 万一程序失控就只剩硬按电源键,不值得。
    private let kioskOptions: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching,
        .disableForceQuit, .disableAppleMenu, .disableHideApplication,
    ]

    private var windows: [NSWindow] = []
    private var primaryWindow: NSWindow?
    private var savedPresentationOptions: NSApplication.PresentationOptions = []
    private var savedPolicy: NSApplication.ActivationPolicy = .accessory
    private var keyMonitor: Any?
    private var tickTimer: Timer?
    private var watchdogTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    /// 活动期间合盖入睡的时刻
    private var resignObserver: NSObjectProtocol?

    private var sleptAt: Date?
    private var escDownAt: Date?
    private var endsAt: Date = .distantFuture
    /// 上一次心跳的时刻。两次心跳之间隔太久 = 中间被系统冻结(合盖睡眠)过
    private var lastTickAt: Date = .distantPast
    /// 截止时刻被顺延时通知外面,好把状态文件一起改掉
    var onDeadlineExtended: ((Date) -> Void)?
    /// 用户在黑幕上点了静音,通知外面记进状态文件
    var onMuteChanged: ((Bool) -> Void)?

    private var audio = AudioSettings(ambientStyle: .bowl, ambientFile: "", ambientEnabled: false, ambientVolume: 0.28,
                                      stepChimeEnabled: false, chimeVolume: 0.45,
                                      breathingGuide: false,
                                      breathInSeconds: 4, breathOutSeconds: 6)
    private var stepEndsAt: Date = .distantFuture
    private var completion: ((OverlayResult) -> Void)?
    private let model = OverlayModel()

    private(set) var isActive = false

    // MARK: - 显示

    func present(forced: Bool,
                 seconds: Int,
                 snoozeRemaining: Int,
                 escapeHoldSeconds: Int,
                 affectedSide: String,
                 playSound: Bool,
                 audio: AudioSettings,
                 muted: Bool,
                 completion: @escaping (OverlayResult) -> Void) {
        guard !isActive else { return }
        isActive = true
        self.completion = completion

        let plan = ExerciseLibrary.plan(totalSeconds: seconds)
        model.exercises = plan
        model.totalSeconds = seconds
        model.remaining = seconds
        model.stepIndex = 0
        model.stepTotal = plan.first?.seconds ?? seconds
        model.stepRemaining = plan.first?.seconds ?? seconds
        model.forced = forced
        model.snoozeRemaining = snoozeRemaining
        model.escapeHoldSeconds = escapeHoldSeconds
        model.escProgress = 0
        model.finished = false
        model.mirrored = (affectedSide == "left")
        model.bothSides = (affectedSide == "both")
        self.audio = audio
        model.breathingOn = audio.breathingGuide && audio.ambientEnabled
        model.startedAt = Date()
        model.ambientAvailable = audio.ambientEnabled
        model.muted = muted
        model.onToggleMute = { [weak self] in self?.toggleMute() }
        model.onSnooze = { [weak self] in self?.finish(.snoozed) }

        let now = Date()
        lastTickAt = now
        endsAt = now.addingTimeInterval(TimeInterval(seconds))
        stepEndsAt = now.addingTimeInterval(TimeInterval(plan.first?.seconds ?? seconds))
        escDownAt = nil

        enterKiosk()
        buildWindows()
        installKeyMonitor()
        startTimers()
        observeSystemChanges()

        if playSound { NSSound(named: NSSound.Name("Hero"))?.play() }
        startAudio(muted: muted)
        Log.info("黑幕已开启:时长 \(seconds)s,强制=\(forced),剩余延迟=\(snoozeRemaining)")
    }

    // MARK: - 关闭

    private func finish(_ result: OverlayResult) {
        guard isActive else { return }
        if result == .completed {
            model.finished = true
            if audio.stepChimeEnabled {
                AmbientAudio.shared.playCompletionChime(volume: audio.chimeVolume)
            }
            // 让"完成"画面停留一下再撤,免得屏幕闪一下就没了
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.teardown(result)
            }
        } else {
            teardown(result)
        }
    }

    private func teardown(_ result: OverlayResult) {
        guard isActive else { return }
        isActive = false

        tickTimer?.invalidate(); tickTimer = nil
        watchdogTimer?.invalidate(); watchdogTimer = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        let ws = NSWorkspace.shared.notificationCenter
        if let o = sleepObserver { ws.removeObserver(o); sleepObserver = nil }
        if let o = wakeObserver { ws.removeObserver(o); wakeObserver = nil }
        sleptAt = nil

        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
        primaryWindow = nil

        AmbientAudio.shared.stop()
        exitKiosk()

        let cb = completion
        completion = nil
        Log.info("黑幕已关闭:\(result)")
        cb?(result)
    }

    /// 外部强制解除(panic 子命令、进程退出前的兜底)
    func forceDismiss() {
        guard isActive else { return }
        teardown(.escaped)
    }

    /// 进程要退出时的最后兜底:哪怕状态乱了也要把 Dock 和菜单栏还回去
    func emergencyRestore() {
        AmbientAudio.shared.stop(fadeOutSeconds: 0)
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        NSApp.presentationOptions = []
        NSApp.setActivationPolicy(.accessory)
        isActive = false
    }

    // MARK: - 展台模式

    private func enterKiosk() {
        savedPolicy = NSApp.activationPolicy()
        savedPresentationOptions = NSApp.presentationOptions
        // 顺序不能反:必须先变成前台应用并抢到焦点,展台模式才生效
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = kioskOptions
    }

    private func exitKiosk() {
        NSApp.presentationOptions = savedPresentationOptions
        NSApp.setActivationPolicy(savedPolicy == .regular ? .accessory : savedPolicy)
    }

    // MARK: - 窗口

    private func buildWindows() {
        // 注意用 screens.first 而不是 NSScreen.main:
        // main 指的是「当前活动窗口所在的屏」,遮罩刚创建时还没有活动窗口,结果不确定;
        // screens.first 稳定地就是菜单栏所在的那块主屏。
        let primaryScreen = NSScreen.screens.first
        primaryWindow = nil
        for screen in NSScreen.screens {
            let isPrimary = (screen == primaryScreen)
            let w = makeWindow(for: screen, primary: isPrimary)
            if isPrimary { primaryWindow = w }
            windows.append(w)
        }
        // 键盘焦点交给显示完整界面的那块屏
        (primaryWindow ?? windows.first)?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(for screen: NSScreen, primary: Bool) -> NSWindow {
        let w = OverlayWindow(contentRect: screen.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false,
                              screen: screen)
        // 屏蔽窗口层级 —— 屏保和登录界面用的那一档,压得住全屏应用
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                .fullScreenAuxiliary, .ignoresCycle]
        w.backgroundColor = .black
        w.isOpaque = true
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = false
        w.acceptsMouseMovedEvents = true

        let scale = min(max(screen.frame.height / 900.0, 0.72), 1.7)
        let host: NSView = primary
            ? NSHostingView(rootView: OverlayView(model: model, scale: scale))
            : NSHostingView(rootView: OverlaySecondaryView(model: model, scale: scale))
        host.frame = CGRect(origin: .zero, size: screen.frame.size)
        host.autoresizingMask = [.width, .height]
        w.contentView = host

        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        return w
    }

    private func rebuildWindowsForScreenChange() {
        guard isActive else { return }
        Log.info("检测到显示器变化,重建黑幕窗口")
        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
        buildWindows()
    }

    // MARK: - 键盘

    /// 用本地事件监听器在事件分发前就截住,比重写 keyDown 可靠。
    /// 返回 nil = 这个按键被吞掉,不会传给任何控件。
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    private static let escKeyCode: UInt16 = 53
    private static let sKeyCode: UInt16 = 1

    private func handleKey(_ event: NSEvent) {
        guard isActive else { return }

        // S 键 = 延迟,和点右下角按钮等价。
        // 留这个冗余是怕鼠标点不动时把人困在屏幕前;
        // 额度用完的强制场次里它同样无效,所以不构成绕过。
        if event.keyCode == Self.sKeyCode, event.type == .keyDown,
           !model.forced, !model.finished {
            Log.info("按 S 键延迟")
            finish(.snoozed)
            return
        }

        guard event.keyCode == Self.escKeyCode else { return }
        switch event.type {
        case .keyDown:
            if escDownAt == nil { escDownAt = Date() }   // 忽略系统的按键重复,只认第一次按下
        case .keyUp:
            escDownAt = nil
            model.escProgress = 0
        default:
            break
        }
    }

    // MARK: - 定时器

    private func startTimers() {
        // 20 毫秒一跳:同时驱动倒计时和 Esc 长按进度条
        let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t

        let wd = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.watchdog() }
        RunLoop.main.add(wd, forMode: .common)
        watchdogTimer = wd
    }

    private func tick() {
        guard isActive, !model.finished else { return }
        let now = Date()

        // 兜底:万一没收到睡眠通知,靠心跳间隔发现自己被冻结过。
        // 正常心跳是 20 毫秒一次,隔了好几秒说明中间没在跑。
        let gap = now.timeIntervalSince(lastTickAt)
        lastTickAt = now
        if gap > 3, sleptAt == nil {
            extendDeadline(by: gap, reason: "进程被挂起")
        }

        // 倒计时用绝对结束时刻算,不受定时器漂移影响。
        // 注意只在数字真的变了才写回去:SwiftUI 只要被赋值就重绘,
        // 心跳是 20 毫秒一次,无条件赋值等于让整个界面每秒重画 50 次。
        let left = Int(ceil(endsAt.timeIntervalSince(now)))
        let newRemaining = max(0, left)
        if model.remaining != newRemaining { model.remaining = newRemaining }

        let stepLeft = Int(ceil(stepEndsAt.timeIntervalSince(now)))
        let newStepRemaining = max(0, stepLeft)
        if model.stepRemaining != newStepRemaining { model.stepRemaining = newStepRemaining }

        if stepLeft <= 0 { advanceStep(from: now) }

        if left <= 0 {
            finish(.completed)
            return
        }

        // Esc 长按进度
        if let down = escDownAt {
            let held = now.timeIntervalSince(down)
            let need = Double(model.escapeHoldSeconds)
            let p = min(1.0, held / need)
            // 进度条只有百分之一的变化才值得重绘一次
            if abs(model.escProgress - p) > 0.01 { model.escProgress = p }
            if held >= need {
                escDownAt = nil
                model.escProgress = 0
                Log.warn("用户长按 Esc 强制解除了本次提醒")
                finish(.escaped)
            }
        }
    }

    /// 调试用:假装刚睡了 N 秒,用来验证顺延逻辑,不用真让机器睡
    func simulateSleep(seconds: TimeInterval) {
        extendDeadline(by: seconds, reason: "模拟睡眠")
    }

    private func startAudio(muted: Bool) {
        guard audio.ambientEnabled else { return }
        AmbientAudio.shared.start(style: audio.ambientStyle,
                                  volume: audio.ambientVolume,
                                  muted: muted,
                                  breathing: audio.breathingGuide,
                                  breathInSeconds: audio.breathInSeconds,
                                  breathOutSeconds: audio.breathOutSeconds,
                                  filePath: audio.ambientFile)
    }

    private func toggleMute() {
        let next = !model.muted
        model.muted = next
        AmbientAudio.shared.setMuted(next)
        onMuteChanged?(next)
        Log.info(next ? "背景音已静音(提示音保留)" : "背景音已恢复")
    }

    /// 把截止时刻整体往后推。人不在电脑前的时间不能算进锻炼时长,
    /// 否则合上盖子再打开就白捡一次。
    private func extendDeadline(by seconds: TimeInterval, reason: String) {
        guard isActive, seconds > 0 else { return }
        endsAt = endsAt.addingTimeInterval(seconds)
        stepEndsAt = stepEndsAt.addingTimeInterval(seconds)
        lastTickAt = Date()
        escDownAt = nil
        model.escProgress = 0
        Log.info("活动期间\(reason) \(Int(seconds)) 秒,倒计时顺延,这段不算锻炼时间")
        onDeadlineExtended?(endsAt)
    }

    private func advanceStep(from now: Date) {
        let next = model.stepIndex + 1
        guard next < model.exercises.count else {
            // 最后一步走完但总时长还有富余,就把剩下的时间留给最后一步
            stepEndsAt = endsAt
            model.stepTotal = max(1, model.exercises.last?.seconds ?? 1)
            return
        }
        model.stepIndex = next
        // 做动作时人常常低着头、面对墙或者闭着眼,响一声比屏幕上换字管用
        if audio.stepChimeEnabled {
            AmbientAudio.shared.playStepChime(volume: audio.chimeVolume)
        }
        let secs = model.exercises[next].seconds
        model.stepTotal = secs
        model.stepRemaining = secs
        stepEndsAt = now.addingTimeInterval(TimeInterval(secs))
        if stepEndsAt > endsAt { stepEndsAt = endsAt }
    }

    /// 看门狗:每秒确认一次自己还在最前面、展台模式没被系统摘掉。
    /// 被别的应用抢走焦点(比如某些通知或输入法)时立刻抢回来。
    private func watchdog() {
        guard isActive else { return }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if NSApp.presentationOptions != kioskOptions {
            NSApp.presentationOptions = kioskOptions
        }
        for w in windows where !w.isVisible {
            w.orderFrontRegardless()
        }
        if let key = primaryWindow, !key.isKeyWindow {
            key.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - 系统事件

    private func observeSystemChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildWindowsForScreenChange()
        }

        // 睡眠通知比「两次心跳隔了多久」可靠得多:
        // 实测系统唤醒后定时器的节奏未必能反映出真实流逝的时间。
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            self.sleptAt = Date()
        }
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive, let from = self.sleptAt else { return }
            self.sleptAt = nil
            let slept = Date().timeIntervalSince(from)
            guard slept > 1 else { return }
            self.extendDeadline(by: slept, reason: "系统睡眠")
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            // 按住 Esc 期间掉焦点会收不到 keyUp,进度条得清零免得误判成长按满
            self.escDownAt = nil
            self.model.escProgress = 0
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
