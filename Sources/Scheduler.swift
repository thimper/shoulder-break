import AppKit
import Foundation

/// 整个程序的大脑:什么时候该弹、该不该跳过、延迟怎么算。
/// 所有时间判断都用绝对时刻,不依赖定时器精度,睡眠唤醒后也能算对。
final class Scheduler {
    static let shared = Scheduler()
    private init() {}

    private(set) var config = Config()
    private(set) var state = AppState()

    private var timer: Timer?
    private var preWarnShown = false
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    /// 合盖入睡的时刻,用来算醒来时到底睡了多久
    private var sleptAt: Date?

    /// 菜单栏用它来刷新显示
    var onStateChanged: (() -> Void)?

    // MARK: - 启动

    func start() {
        config = Config.load()
        state = AppState.load()
        History.prune()

        let now = Date().timeIntervalSince1970

        // 上一次遮罩没走完就被杀了(或者断电),把它接着盖回去
        if state.overlayActive && state.overlayEndsAt > now + 3 && !ScreenLock.isLocked {
            let remain = Int(state.overlayEndsAt - now)
            Log.warn("上次的肩部活动没做完(还剩 \(remain) 秒),恢复黑幕")
            presentOverlay(seconds: remain, forced: state.overlayForced, resumed: true)
        } else if state.overlayActive {
            // 时间已经过了,清掉残留标记
            state.overlayActive = false
            state.overlayForced = false
            state.overlayEndsAt = 0
            state.save()
        }

        if state.nextFireAt <= 0 || state.nextFireAt > now + 24 * 3600 {
            state.nextFireAt = computeNextFire(from: Date()).timeIntervalSince1970
            state.save()
        }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.sleptAt = Date()
            Log.info("系统即将睡眠")
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        Log.info("已启动。模式=\(config.mode) 间隔=\(config.intervalMinutes)分钟 " +
                 "时长=\(config.exerciseSeconds)秒 生效时段=\(config.activeHours.start)-\(config.activeHours.end)")
        Log.info("下一次提醒:\(describeNextFire())")
        onStateChanged?()
    }

    // MARK: - 每秒心跳

    private func tick() {
        guard !OverlayController.shared.isActive else { return }
        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970
        var changed = false

        // 暂停到期
        if state.pausedUntil > 0 && state.pausedUntil <= now {
            state.pausedUntil = 0
            changed = true
            Log.info("暂停已到期,恢复提醒")
        }
        if state.isPaused {
            if preWarnShown { PreWarnController.shared.hide(); preWarnShown = false }
            if changed { state.save(); onStateChanged?() }
            return
        }

        if state.nextFireAt <= 0 {
            state.nextFireAt = computeNextFire(from: nowDate).timeIntervalSince1970
            changed = true
        }

        let secondsToFire = state.nextFireAt - now

        // 兜底:没收到入睡通知(比如断电、程序被换掉重启)时,
        // 靠「错过了多久」推断人是不是离开过。
        // 错过很久 = 那段时间没在用电脑,重新开始完整计时,别一回座位就弹;
        // 只错过一小会儿 = 大概是程序卡了一下,给 60 秒缓冲照常提醒。
        if secondsToFire < -90 {
            let missedBy = -secondsToFire
            preWarnShown = false
            if missedBy >= Double(config.sleepResetMinutes) * 60 {
                state.nextFireAt = computeNextFire(from: nowDate).timeIntervalSince1970
                Log.info("错过了 \(Int(missedBy / 60)) 分钟(期间应该不在电脑前), " +
                         "重新开始完整计时:\(describeNextFire())")
            } else {
                state.nextFireAt = now + 60
                Log.info("检测到时间跳变,错过的提醒不补弹,60 秒后重新开始计时")
            }
            state.save()
            onStateChanged?()
            return
        }

        // 生效时段外:把闹钟压到下一个时段开头
        if !config.isWithinActiveHours(nowDate) {
            let start = config.nextActiveWindowStart(after: nowDate).timeIntervalSince1970
            if abs(state.nextFireAt - start) > 1 {
                state.nextFireAt = start
                preWarnShown = false
                changed = true
                Log.info("当前不在生效时段,下一次提醒排到 \(describeNextFire())")
            }
            if changed { state.save(); onStateChanged?() }
            return
        }

        // 预告横幅
        if !preWarnShown, config.preWarnSeconds > 0,
           secondsToFire <= Double(config.preWarnSeconds), secondsToFire > 0 {
            PreWarnController.shared.show(seconds: Int(ceil(secondsToFire)),
                                          playSound: config.soundEnabled)
            preWarnShown = true
        }

        if secondsToFire <= 0 {
            preWarnShown = false
            PreWarnController.shared.hide()

            // 屏幕锁着 / 切到了别的用户 —— 人根本不在,弹了也是白弹
            if ScreenLock.isLocked || !ScreenLock.isOnConsole {
                Log.info("屏幕处于锁定状态,跳过本次并重排")
                History.append(.skippedIdle, snoozeUsed: state.snoozeUsed)
                state.nextFireAt = computeNextFire(from: nowDate).timeIntervalSince1970
                state.save()
                onStateChanged?()
                return
            }

            // 人已经离开电脑,本身就是在休息,不用弹
            let idle = Idle.seconds()
            if config.idleSkipSeconds > 0 && idle >= Double(config.idleSkipSeconds) {
                Log.info("已 \(Int(idle)) 秒没碰键鼠,判定人不在,跳过本次并重排")
                History.append(.skippedIdle, snoozeUsed: state.snoozeUsed)
                state.nextFireAt = computeNextFire(from: nowDate).timeIntervalSince1970
                state.save()
                onStateChanged?()
                return
            }
            fire()
            return
        }

        if changed { state.save(); onStateChanged?() }
    }

    // MARK: - 睡眠唤醒

    /// 休眠这段时间人不在电脑前,肩膀没在受累,不该算进「又坐了多久」里。
    /// 睡得久 = 已经歇过了,醒来重新开始完整计时;
    /// 只是打个盹 = 把睡掉的时间补回去接着算。
    private func handleWake() {
        preWarnShown = false
        PreWarnController.shared.hide()

        let slept = sleptAt.map { Date().timeIntervalSince($0) } ?? 0
        sleptAt = nil

        guard !OverlayController.shared.isActive else {
            // 活动进行中的顺延由遮罩自己处理,这里不插手
            Log.info("唤醒时活动仍在进行,倒计时已由活动界面顺延")
            tick()
            return
        }

        let resetThreshold = Double(config.sleepResetMinutes) * 60
        if slept >= resetThreshold {
            state.nextFireAt = computeNextFire(from: Date()).timeIntervalSince1970
            state.save()
            Log.info("睡了 \(Int(slept / 60)) 分钟(超过 \(config.sleepResetMinutes) 分钟), " +
                     "当作已经离开休息过,重新开始计时:\(describeNextFire())")
        } else if slept > 0 {
            state.nextFireAt += slept
            state.save()
            Log.info("睡了 \(Int(slept)) 秒,把这段时间补回去,下一次:\(describeNextFire())")
        } else {
            Log.info("系统唤醒,重新校准计时")
        }
        onStateChanged?()
        tick()
    }

    // MARK: - 触发

    private func fire() {
        let forced = state.snoozeUsed >= config.maxSnoozes
        presentOverlay(seconds: config.exerciseSeconds, forced: forced, resumed: false)
    }

    private func presentOverlay(seconds: Int, forced: Bool, resumed: Bool) {
        let endsAt = Date().timeIntervalSince1970 + Double(seconds)
        state.overlayActive = true
        state.overlayForced = forced
        state.overlayEndsAt = endsAt
        state.save()

        OverlayController.shared.onDeadlineExtended = { [weak self] newEnd in
            guard let self else { return }
            self.state.overlayEndsAt = newEnd.timeIntervalSince1970
            self.state.save()
        }

        OverlayController.shared.onMuteChanged = { [weak self] muted in
            guard let self else { return }
            self.state.ambientMuted = muted
            self.state.save()
        }

        OverlayController.shared.present(
            forced: forced,
            seconds: seconds,
            snoozeRemaining: max(0, config.maxSnoozes - state.snoozeUsed),
            escapeHoldSeconds: config.escapeHoldSeconds,
            affectedSide: config.affectedSide,
            playSound: config.soundEnabled && !resumed,
            audio: AudioSettings(ambientStyle: AmbientStyle(rawValue: config.ambientStyle) ?? .bowl,
                                 ambientFile: config.ambientFile,
                                 ambientEnabled: config.ambientEnabled && config.soundEnabled,
                                 ambientVolume: config.ambientVolume,
                                 stepChimeEnabled: config.stepChimeEnabled && config.soundEnabled,
                                 chimeVolume: config.chimeVolume,
                                 breathingGuide: config.breathingGuide,
                                 breathInSeconds: Double(config.breathInSeconds),
                                 breathOutSeconds: Double(config.breathOutSeconds)),
            muted: state.ambientMuted
        ) { [weak self] result in
            self?.handleResult(result)
        }
        onStateChanged?()
    }

    private func handleResult(_ result: OverlayResult) {
        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970

        state.overlayActive = false
        state.overlayForced = false
        state.overlayEndsAt = 0

        switch result {
        case .completed:
            History.append(.completed, snoozeUsed: state.snoozeUsed)
            state.snoozeUsed = 0
            state.lastCompletedAt = now
            state.nextFireAt = computeNextFire(from: nowDate).timeIntervalSince1970

        case .snoozed:
            state.snoozeUsed += 1
            History.append(.snoozed, snoozeUsed: state.snoozeUsed)
            state.nextFireAt = now + Double(config.snoozeMinutes) * 60
            let left = max(0, config.maxSnoozes - state.snoozeUsed)
            Log.info("延迟 \(config.snoozeMinutes) 分钟,还剩 \(left) 次延迟机会" +
                     (left == 0 ? " —— 下一次将无法延迟" : ""))

        case .escaped:
            History.append(.escaped, snoozeUsed: state.snoozeUsed)
            state.snoozeUsed = 0
            state.nextFireAt = computeNextFire(from: nowDate).timeIntervalSince1970
            Log.warn("本次被强制跳过,已记入逃跑次数")
        }

        preWarnShown = false
        state.save()
        Log.info("下一次提醒:\(describeNextFire())")
        onStateChanged?()
    }

    // MARK: - 下次时刻计算

    private func computeNextFire(from date: Date) -> Date {
        if config.mode == "fixed" {
            return nextFixedTime(after: date)
        }
        var candidate = date.addingTimeInterval(Double(config.intervalMinutes) * 60)
        if !config.isWithinActiveHours(candidate) {
            // 落到了下班之后,推到下一个时段开始再等 5 分钟,别一进时段就弹
            candidate = config.nextActiveWindowStart(after: candidate).addingTimeInterval(300)
        }
        return candidate
    }

    private func nextFixedTime(after date: Date) -> Date {
        let times = config.fixedTimes.compactMap(Config.minutesOfDay).sorted()
        guard !times.isEmpty else {
            return date.addingTimeInterval(Double(config.intervalMinutes) * 60)
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        for m in times {
            let t = today.addingTimeInterval(Double(m) * 60)
            if t.timeIntervalSince(date) > 30 { return t }
        }
        return today.addingTimeInterval(86400 + Double(times[0]) * 60)
    }

    // MARK: - 外部命令

    func triggerNow() {
        guard !OverlayController.shared.isActive else { return }
        Log.info("收到「现在就做一次」")
        preWarnShown = false
        PreWarnController.shared.hide()
        fire()
    }

    /// 调试用:假装刚睡了 N 秒。遮罩开着就顺延倒计时,
    /// 没开就按真实唤醒的规则重排下一次提醒。
    func simulateSleep(seconds: TimeInterval) {
        if OverlayController.shared.isActive {
            OverlayController.shared.simulateSleep(seconds: seconds)
            return
        }
        sleptAt = Date().addingTimeInterval(-seconds)
        handleWake()
    }

    func panic() {
        Log.warn("收到 panic 命令,强制解除黑幕")
        PreWarnController.shared.hide()
        OverlayController.shared.forceDismiss()
    }

    func pause(hours: Double) {
        state.pausedUntil = Date().timeIntervalSince1970 + hours * 3600
        History.append(.skippedPaused, snoozeUsed: state.snoozeUsed)
        state.save()
        PreWarnController.shared.hide()
        preWarnShown = false
        Log.info("已暂停 \(Int(hours * 60)) 分钟")
        onStateChanged?()
    }

    func resumeFromPause() {
        state.pausedUntil = 0
        state.nextFireAt = computeNextFire(from: Date()).timeIntervalSince1970
        state.save()
        Log.info("已取消暂停,下一次提醒:\(describeNextFire())")
        onStateChanged?()
    }

    func reloadConfig() {
        config = Config.load()
        Log.info("配置已重新载入:间隔=\(config.intervalMinutes)分钟 时长=\(config.exerciseSeconds)秒")
        state.nextFireAt = computeNextFire(from: Date()).timeIntervalSince1970
        state.save()
        onStateChanged?()
    }

    // MARK: - 展示用

    var secondsUntilNextFire: Int {
        Int((state.nextFireAt - Date().timeIntervalSince1970).rounded())
    }

    func describeNextFire() -> String {
        let d = Date(timeIntervalSince1970: state.nextFireAt)
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let mins = max(0, secondsUntilNextFire) / 60
        return "\(f.string(from: d))(约 \(mins) 分钟后)"
    }

    var pausedRemainingMinutes: Int {
        max(0, Int((state.pausedUntil - Date().timeIntervalSince1970) / 60))
    }
}
