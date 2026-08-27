import Foundation

/// 运行状态。写盘的目的有两个:
/// 1) 进程被 kill 掉后 launchd 拉起来能接着算,而不是白捡一次休息;
/// 2) 遮罩期间被杀,重启后立刻把黑幕重新盖回去,只能换来几秒钟。
struct AppState {
    /// 本轮已经用掉几次延迟,做完一次动作后清零
    var snoozeUsed: Int = 0
    /// 下次触发的绝对时刻(Unix 秒)。用绝对时刻而不是倒数,合盖睡眠再打开也不会算错
    var nextFireAt: Double = 0

    /// 遮罩是否正在进行中(用于被杀后恢复)
    var overlayActive: Bool = false
    /// 当时那次遮罩是不是「已经不能延迟」的强制场次
    var overlayForced: Bool = false
    /// 那次遮罩应该结束的绝对时刻
    var overlayEndsAt: Double = 0

    /// 手动暂停的到期时刻,0 表示没暂停
    var pausedUntil: Double = 0
    var lastCompletedAt: Double = 0

    /// 在黑幕上点过静音。记下来是为了下次黑幕沿用,
    /// 临时想安静一下不用去翻配置文件
    var ambientMuted: Bool = false
}

extension AppState: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppState()
        snoozeUsed = try c.decodeIfPresent(Int.self, forKey: .snoozeUsed) ?? d.snoozeUsed
        nextFireAt = try c.decodeIfPresent(Double.self, forKey: .nextFireAt) ?? d.nextFireAt
        overlayActive = try c.decodeIfPresent(Bool.self, forKey: .overlayActive) ?? d.overlayActive
        overlayForced = try c.decodeIfPresent(Bool.self, forKey: .overlayForced) ?? d.overlayForced
        overlayEndsAt = try c.decodeIfPresent(Double.self, forKey: .overlayEndsAt) ?? d.overlayEndsAt
        pausedUntil = try c.decodeIfPresent(Double.self, forKey: .pausedUntil) ?? d.pausedUntil
        lastCompletedAt = try c.decodeIfPresent(Double.self, forKey: .lastCompletedAt) ?? d.lastCompletedAt
        ambientMuted = try c.decodeIfPresent(Bool.self, forKey: .ambientMuted) ?? d.ambientMuted
    }
}

extension AppState {
    static func load() -> AppState {
        guard let data = try? Data(contentsOf: Paths.stateFile),
              let s = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState()
        }
        return s
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return }
        try? Paths.atomicWrite(data, to: Paths.stateFile)
    }

    var isPaused: Bool { pausedUntil > Date().timeIntervalSince1970 }
}
