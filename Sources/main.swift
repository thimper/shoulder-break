import AppKit
import Foundation

let version = "1.0.0"

func printHelp() {
    print("""
    ShoulderBreak \(version) — 定时强制肩周活动提醒

    用法:
      shoulder-break run       启动常驻服务(launchd 用这个)
      shoulder-break now       立刻触发一次活动
      shoulder-break panic     强制解除当前黑幕
      shoulder-break pause     暂停 1 小时
      shoulder-break resume    取消暂停
      shoulder-break reload    重新载入配置文件
      shoulder-break status    查看下次时间和统计
      shoulder-break quit      让常驻服务退出

    配置文件:\(Paths.configFile.path)
    运行状态:\(Paths.stateFile.path)
    日志:    \(Paths.logFile.path)
    """)
}

func printStatus() {
    let cfg = Config.load()
    let st = AppState.load()
    let now = Date().timeIntervalSince1970

    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"

    print("ShoulderBreak \(version)")
    print("模式:        \(cfg.mode == "fixed" ? "固定钟点" : "每 \(cfg.intervalMinutes) 分钟")")
    print("活动时长:    \(cfg.exerciseSeconds) 秒")
    print("生效时段:    \(cfg.activeHours.start) – \(cfg.activeHours.end)" +
          (cfg.isWithinActiveHours() ? "(当前生效中)" : "(当前不在时段内)"))
    print("延迟规则:    每次 \(cfg.snoozeMinutes) 分钟,最多 \(cfg.maxSnoozes) 次")
    print("本轮已延迟:  \(st.snoozeUsed)/\(cfg.maxSnoozes)" +
          (st.snoozeUsed >= cfg.maxSnoozes ? "(下一次无法延迟)" : ""))

    if st.isPaused {
        let mins = Int((st.pausedUntil - now) / 60)
        print("状态:        已暂停,\(mins) 分钟后恢复")
    } else if st.overlayActive {
        print("状态:        正在进行肩部活动")
    } else if st.nextFireAt > 0 {
        let mins = Int((st.nextFireAt - now) / 60)
        print("下次提醒:    \(f.string(from: Date(timeIntervalSince1970: st.nextFireAt)))(约 \(mins) 分钟后)")
    } else {
        print("下次提醒:    未排程(服务可能没在运行)")
    }

    let today = History.today()
    let week = History.thisWeek()
    print("")
    print("今天:  完成 \(today.completed) · 延迟 \(today.snoozed) · 跳过 \(today.skipped) · 强制跳过 \(today.escaped)")
    print("本周:  完成 \(week.completed) · 延迟 \(week.snoozed) · 跳过 \(week.skipped) · 强制跳过 \(week.escaped)")
}

// MARK: - 入口

Paths.ensureDirs()

let subcommand = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "run"

switch subcommand {
case "run":
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // .accessory = 后台附件身份:不占 Dock、不进 Cmd+Tab,只留菜单栏图标
    app.setActivationPolicy(.accessory)
    app.run()

case "simulate-sleep":
    do {
        let secs = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 60) : 60
        IPC.send("simulate-sleep:\(secs)")
        print("已请求模拟睡眠 \(Int(secs)) 秒")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

case "now", "panic", "pause", "resume", "reload", "quit":
    IPC.send(subcommand)
    let labels = ["now": "已请求立刻触发一次活动",
                  "panic": "已请求解除黑幕",
                  "pause": "已请求暂停 1 小时",
                  "resume": "已请求取消暂停",
                  "reload": "已请求重新载入配置",
                  "quit": "已请求退出服务"]
    print(labels[subcommand] ?? "已发送")
    // 广播是异步的,给一点时间送达再退出
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))

case "audition":
    do {
        let args = CommandLine.arguments
        let dir = args.count > 2 ? args[2] : "/tmp"
        let secs = args.count > 3 ? (Double(args[3]) ?? 22) : 22
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for style in AmbientStyle.allCases {
            let path = "\(dir)/sb-\(style.rawValue).caf"
            let ok = AmbientAudio.shared.exportStyle(style, to: path,
                                                    seconds: secs, volume: 0.42)
            print(ok ? "  \(style.rawValue) → \(path)" : "  \(style.rawValue) 导出失败")
        }
    }

case "export-audio":
    do {
        let args = CommandLine.arguments
        let path = args.count > 2 ? args[2] : "ambient-sample.caf"
        let secs = args.count > 3 ? (Double(args[3]) ?? 14) : 14
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let cfg = Config.load()
        let ok = AmbientAudio.shared.exportSample(
            to: path, seconds: secs, volume: cfg.ambientVolume,
            breathing: cfg.breathingGuide,
            breathInSeconds: Double(cfg.breathInSeconds),
            breathOutSeconds: Double(cfg.breathOutSeconds))
        print(ok ? "已导出试听文件:\(path)" : "导出失败")
        if !ok { exit(1) }
    }

case "figure":
    do {
        let args = CommandLine.arguments
        let name = args.count > 2 ? args[2] : "pendulum"
        let path = args.count > 3 ? args[3] : "figure.gif"
        let mirrored = args.contains("--left")
        let sheet = args.contains("--sheet")
        guard let m = FigureExport.motion(named: name) else {
            print("动作名要是 pendulum / wallwalk / crossbody / rotation / squeeze")
            exit(1)
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if sheet {
            FigureExport.contactSheet(m, to: path, mirrored: mirrored)
        } else {
            FigureExport.gif(m, to: path, mirrored: mirrored)
        }
    }

case "preview":
    do {
        let args = CommandLine.arguments
        let path = args.count > 2 ? args[2] : "preview.png"
        let forced = args.contains("--forced")
        let elapsed = Int(args.first(where: { $0.hasPrefix("--at=") })?.dropFirst(5) ?? "0") ?? 0
        let esc = Double(args.first(where: { $0.hasPrefix("--esc=") })?.dropFirst(6) ?? "0") ?? 0
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Preview.render(to: path, forced: forced, elapsed: elapsed, escProgress: esc)
    }

case "status":
    printStatus()

case "version", "-v", "--version":
    print(version)

case "help", "-h", "--help":
    printHelp()

default:
    print("未知命令:\(subcommand)\n")
    printHelp()
    exit(1)
}
