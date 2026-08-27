import Foundation

struct ActiveHours {
    var start: String = "09:00"
    var end: String = "22:00"
}

extension ActiveHours: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? "09:00"
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? "22:00"
    }
}

struct Config {
    /// "interval" = 每隔 N 分钟;"fixed" = 每天固定几个钟点
    var mode: String = "interval"
    var intervalMinutes: Int = 45
    var fixedTimes: [String] = ["10:00", "11:30", "14:30", "16:00", "17:30", "20:00"]
    var activeHours: ActiveHours = ActiveHours()
    var exerciseSeconds: Int = 180
    var snoozeMinutes: Int = 5
    var maxSnoozes: Int = 3
    var preWarnSeconds: Int = 20
    /// 超过这么多秒没碰键鼠就认为人已经离开,本次跳过(等于已经在休息了)
    var idleSkipSeconds: Int = 180
    var escapeHoldSeconds: Int = 10
    var soundEnabled: Bool = true
    /// 患侧:"right" / "left" / "both"。示意图里这一侧的手臂会高亮
    var affectedSide: String = "right"
    /// 休眠/合盖超过这么多分钟,就认为你已经离开过、肩膀歇过了,
    /// 醒来重新开始完整计时;不到这个数就只是把错过的时间补回去
    var sleepResetMinutes: Int = 10

    /// 黑幕期间的背景音。风格:
    /// bowl 颂钵(默认,音符卡在呼吸节拍上)/ rain 雨声 /
    /// pad-warm 温暖和弦 / pad-low 低音和弦 / off 关掉
    var ambientStyle: String = "bowl"
    var ambientEnabled: Bool = true
    /// ambientStyle 设成 "file" 时,放这个路径的音频循环播放。
    /// 支持 mp3 / m4a / wav / aiff / flac,写 ~ 开头的路径也行
    var ambientFile: String = ""
    var ambientVolume: Double = 0.28
    /// 动作切换时响一声,不用盯着屏幕也知道该换了
    var stepChimeEnabled: Bool = true
    var chimeVolume: Double = 0.75
    /// 呼吸引导:背景音跟着涨落,黑幕上配一个张缩的圆环。
    /// 拉伸时呼气能让肌肉放松、活动度更大
    var breathingGuide: Bool = true
    var breathInSeconds: Int = 4
    var breathOutSeconds: Int = 6
}

// 放在 extension 里实现 Codable,这样 Swift 仍会自动生成带默认值的逐成员构造器,
// 让 Config() 可以直接拿到全套默认值。
extension Config: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? d.mode
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes
        fixedTimes = try c.decodeIfPresent([String].self, forKey: .fixedTimes) ?? d.fixedTimes
        activeHours = try c.decodeIfPresent(ActiveHours.self, forKey: .activeHours) ?? d.activeHours
        exerciseSeconds = try c.decodeIfPresent(Int.self, forKey: .exerciseSeconds) ?? d.exerciseSeconds
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        maxSnoozes = try c.decodeIfPresent(Int.self, forKey: .maxSnoozes) ?? d.maxSnoozes
        preWarnSeconds = try c.decodeIfPresent(Int.self, forKey: .preWarnSeconds) ?? d.preWarnSeconds
        idleSkipSeconds = try c.decodeIfPresent(Int.self, forKey: .idleSkipSeconds) ?? d.idleSkipSeconds
        escapeHoldSeconds = try c.decodeIfPresent(Int.self, forKey: .escapeHoldSeconds) ?? d.escapeHoldSeconds
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? d.soundEnabled
        affectedSide = try c.decodeIfPresent(String.self, forKey: .affectedSide) ?? d.affectedSide
        sleepResetMinutes = try c.decodeIfPresent(Int.self, forKey: .sleepResetMinutes) ?? d.sleepResetMinutes
        ambientStyle = try c.decodeIfPresent(String.self, forKey: .ambientStyle) ?? d.ambientStyle
        ambientEnabled = try c.decodeIfPresent(Bool.self, forKey: .ambientEnabled) ?? d.ambientEnabled
        ambientFile = try c.decodeIfPresent(String.self, forKey: .ambientFile) ?? d.ambientFile
        ambientVolume = try c.decodeIfPresent(Double.self, forKey: .ambientVolume) ?? d.ambientVolume
        stepChimeEnabled = try c.decodeIfPresent(Bool.self, forKey: .stepChimeEnabled) ?? d.stepChimeEnabled
        chimeVolume = try c.decodeIfPresent(Double.self, forKey: .chimeVolume) ?? d.chimeVolume
        breathingGuide = try c.decodeIfPresent(Bool.self, forKey: .breathingGuide) ?? d.breathingGuide
        breathInSeconds = try c.decodeIfPresent(Int.self, forKey: .breathInSeconds) ?? d.breathInSeconds
        breathOutSeconds = try c.decodeIfPresent(Int.self, forKey: .breathOutSeconds) ?? d.breathOutSeconds
        clampToSaneRanges()
    }

    /// 手改配置写出离谱数字时兜一下底,避免把自己锁死或者变成永不触发。
    mutating func clampToSaneRanges() {
        intervalMinutes = min(max(intervalMinutes, 1), 480)
        exerciseSeconds = min(max(exerciseSeconds, 20), 900)
        snoozeMinutes = min(max(snoozeMinutes, 1), 60)
        maxSnoozes = min(max(maxSnoozes, 0), 20)
        preWarnSeconds = min(max(preWarnSeconds, 0), 120)
        idleSkipSeconds = max(idleSkipSeconds, 0)
        escapeHoldSeconds = min(max(escapeHoldSeconds, 1), 60)
        if mode != "interval" && mode != "fixed" { mode = "interval" }
        if !["right", "left", "both"].contains(affectedSide) { affectedSide = "right" }
        sleepResetMinutes = min(max(sleepResetMinutes, 1), 240)
        if !["bowl", "rain", "pad-warm", "pad-low", "file", "off"].contains(ambientStyle) {
            ambientStyle = "bowl"
        }
        if ambientStyle == "off" { ambientEnabled = false }
        ambientVolume = min(max(ambientVolume, 0), 1)
        chimeVolume = min(max(chimeVolume, 0), 1)
        breathInSeconds = min(max(breathInSeconds, 2), 20)
        breathOutSeconds = min(max(breathOutSeconds, 2), 20)
    }
}

extension Config {
    static func load() -> Config {
        guard let data = try? Data(contentsOf: Paths.configFile) else {
            let d = Config()
            d.saveIfAbsent()
            return d
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            Log.error("配置文件解析失败,改用默认值:\(error.localizedDescription)")
            return Config()
        }
    }

    func saveIfAbsent() {
        guard !FileManager.default.fileExists(atPath: Paths.configFile.path) else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? Paths.atomicWrite(data, to: Paths.configFile)
            Log.info("已生成默认配置:\(Paths.configFile.path)")
        }
    }

    /// "HH:mm" -> 当天从 0 点起算的分钟数
    static func minutesOfDay(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// 支持跨午夜的时段,比如 start=21:00 end=02:00
    func isWithinActiveHours(_ date: Date = Date()) -> Bool {
        guard let s = Config.minutesOfDay(activeHours.start),
              let e = Config.minutesOfDay(activeHours.end) else { return true }
        if s == e { return true }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return s < e ? (now >= s && now < e) : (now >= s || now < e)
    }

    /// 下一个生效时段的开始时刻(用于时段外时把闹钟排到时段开头)
    func nextActiveWindowStart(after date: Date = Date()) -> Date {
        guard let s = Config.minutesOfDay(activeHours.start) else { return date }
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        let todayStart = today.addingTimeInterval(TimeInterval(s * 60))
        if todayStart > date { return todayStart }
        return todayStart.addingTimeInterval(86400)
    }
}
