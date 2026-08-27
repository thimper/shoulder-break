import AppKit

/// 屏幕顶部菜单栏那个小图标。平时只显示「距下次还有几分钟」,
/// 点开能立刻做一次、暂停一小时、看今天的完成情况。
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "figure.arms.open",
                                   accessibilityDescription: "肩周提醒")
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }
        statusItem = item
        refresh()

        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t

        Scheduler.shared.onStateChanged = { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard let item = statusItem else { return }
        let sched = Scheduler.shared

        if OverlayController.shared.isActive {
            item.button?.title = " 活动中"
        } else if sched.state.isPaused {
            item.button?.title = " 暂停 \(sched.pausedRemainingMinutes)′"
        } else {
            let mins = max(0, sched.secondsUntilNextFire) / 60
            item.button?.title = mins >= 60
                ? String(format: " %.1fh", Double(mins) / 60.0)
                : " \(mins)′"
        }
        item.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let sched = Scheduler.shared
        let menu = NSMenu()

        let head = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        let now = NSMenuItem(title: "现在就做一次",
                             action: #selector(actionNow), keyEquivalent: "")
        now.target = self
        now.isEnabled = !OverlayController.shared.isActive
        menu.addItem(now)

        if sched.state.isPaused {
            let resume = NSMenuItem(title: "取消暂停(还剩 \(sched.pausedRemainingMinutes) 分钟)",
                                    action: #selector(actionResume), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        } else {
            let pause = NSMenuItem(title: "暂停 1 小时(开会/演讲用)",
                                   action: #selector(actionPause), keyEquivalent: "")
            pause.target = self
            pause.isEnabled = !OverlayController.shared.isActive
            menu.addItem(pause)
        }

        menu.addItem(.separator())

        let today = History.today()
        let week = History.thisWeek()
        let todayItem = NSMenuItem(
            title: "今天:完成 \(today.completed) · 延迟 \(today.snoozed) · 跳过 \(today.skipped)",
            action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        menu.addItem(todayItem)

        let escItem = NSMenuItem(
            title: week.escaped > 0 ? "本周强制跳过 \(week.escaped) 次" : "本周没有强制跳过 👍",
            action: nil, keyEquivalent: "")
        escItem.isEnabled = false
        menu.addItem(escItem)

        let snoozeItem = NSMenuItem(
            title: "本轮延迟:\(sched.state.snoozeUsed)/\(sched.config.maxSnoozes)",
            action: nil, keyEquivalent: "")
        snoozeItem.isEnabled = false
        menu.addItem(snoozeItem)

        menu.addItem(.separator())

        let cfg = NSMenuItem(title: "打开配置文件", action: #selector(actionOpenConfig), keyEquivalent: "")
        cfg.target = self
        menu.addItem(cfg)

        let reload = NSMenuItem(title: "重新载入配置", action: #selector(actionReload), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        let log = NSMenuItem(title: "查看日志", action: #selector(actionOpenLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 ShoulderBreak", action: #selector(actionQuit), keyEquivalent: "")
        quit.target = self
        quit.isEnabled = !OverlayController.shared.isActive   // 黑幕期间不给退出
        menu.addItem(quit)

        return menu
    }

    private func statusLine() -> String {
        let sched = Scheduler.shared
        if OverlayController.shared.isActive { return "正在进行肩部活动" }
        if sched.state.isPaused { return "已暂停,\(sched.pausedRemainingMinutes) 分钟后恢复" }
        if !sched.config.isWithinActiveHours() {
            return "当前不在生效时段(\(sched.config.activeHours.start)–\(sched.config.activeHours.end))"
        }
        return "下一次:\(sched.describeNextFire())"
    }

    // MARK: - 动作

    @objc private func actionNow() { Scheduler.shared.triggerNow() }
    @objc private func actionPause() { Scheduler.shared.pause(hours: 1) }
    @objc private func actionResume() { Scheduler.shared.resumeFromPause() }
    @objc private func actionReload() { Scheduler.shared.reloadConfig() }

    @objc private func actionOpenConfig() {
        Scheduler.shared.config.saveIfAbsent()
        NSWorkspace.shared.open(Paths.configFile)
    }

    @objc private func actionOpenLog() {
        if FileManager.default.fileExists(atPath: Paths.logFile.path) {
            NSWorkspace.shared.open(Paths.logFile)
        } else {
            NSWorkspace.shared.open(Paths.logDir)
        }
    }

    @objc private func actionQuit() {
        guard !OverlayController.shared.isActive else { return }
        Log.info("用户从菜单栏退出")
        OverlayController.shared.emergencyRestore()
        NSApp.terminate(nil)
    }
}
