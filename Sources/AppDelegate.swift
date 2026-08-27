import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarController()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureDirs()
        Config().saveIfAbsent()

        menuBar.install()
        installSignalHandlers()

        IPC.listen { [weak self] command in
            self?.handle(command: command)
        }

        Scheduler.shared.start()
        menuBar.refresh()
    }

    private func handle(command: String) {
        switch command {
        case "now":    Scheduler.shared.triggerNow()
        case "panic":  Scheduler.shared.panic()
        case "pause":  Scheduler.shared.pause(hours: 1)
        case "resume": Scheduler.shared.resumeFromPause()
        case "reload": Scheduler.shared.reloadConfig()
        case "quit":
            OverlayController.shared.emergencyRestore()
            NSApp.terminate(nil)
        default:
            // 调试用:simulate-sleep:90 = 假装刚睡了 90 秒
            if command.hasPrefix("simulate-sleep:"),
               let secs = Double(command.dropFirst("simulate-sleep:".count)) {
                Log.info("收到模拟睡眠 \(Int(secs)) 秒")
                Scheduler.shared.simulateSleep(seconds: secs)
                return
            }
            Log.warn("收到未知命令:\(command)")
        }
        menuBar.refresh()
    }

    /// 被 launchctl 停掉或者收到 kill 时,先把 Dock 和菜单栏还回去再退出。
    /// 用 DispatchSource 而不是裸 signal 回调,因为信号回调里不能安全调用 AppKit。
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                // 遮罩期间被 kill 掉,用非零退出码走人,
                // launchd 的 KeepAlive(SuccessfulExit=false)会立刻把服务拉回来接着盖上;
                // 平时正常停服务(launchctl unload / 菜单栏退出)则是零退出码,不会被拉回。
                let duringOverlay = OverlayController.shared.isActive
                Log.info("收到退出信号,恢复桌面后退出" + (duringOverlay ? "(活动进行中,将由 launchd 拉回)" : ""))
                OverlayController.shared.emergencyRestore()
                exit(duringOverlay ? 1 : 0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    /// 黑幕期间不允许退出。Cmd+Q 在事件监听那层就被吞了,这里是第二道保险。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if OverlayController.shared.isActive {
            Log.warn("活动进行中,拒绝退出请求")
            return .terminateCancel
        }
        OverlayController.shared.emergencyRestore()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        OverlayController.shared.emergencyRestore()
    }
}
