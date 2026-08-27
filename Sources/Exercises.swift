import Foundation

/// 每个动作对应一段简笔小人循环动画的画法
enum ExerciseMotion {
    case pendulum          // 钟摆:身体前倾,患侧手臂放松画圈
    case wallWalk          // 爬墙:手指沿墙一格格往上
    case crossBody         // 体前交叉:手臂横过胸前,对侧手托肘
    case externalRotation  // 外旋:肘贴身体,前臂像开门一样打开
    case scapularSqueeze   // 肩胛后缩 + 耸肩

    /// 动画转一圈要几秒
    var cycleSeconds: Double {
        switch self {
        case .pendulum: return 2.4
        case .wallWalk: return 5.0
        case .crossBody: return 4.5
        case .externalRotation: return 3.2
        case .scapularSqueeze: return 3.6
        }
    }
}

struct Exercise {
    let name: String
    let seconds: Int
    let detail: String
    let hint: String
    /// SF Symbol 名,全部选用 macOS 11 就存在的基础符号,避免系统上找不到显示成空白
    let symbol: String
    let motion: ExerciseMotion
}

enum ExerciseLibrary {

    /// 一轮标准 180 秒的肩周活动。顺序有讲究:先放松(钟摆)再拉伸,最后回到姿势控制。
    static let base: [Exercise] = [
        Exercise(
            name: "钟摆摆动",
            seconds: 40,
            detail: "身体前倾,健侧手扶住桌沿,患侧手臂完全放松自然垂下,靠身体带动画小圈。",
            hint: "顺时针 20 秒,逆时针 20 秒。手臂不要主动使劲,是被身体晃起来的。",
            symbol: "arrow.clockwise.circle",
            motion: .pendulum
        ),
        Exercise(
            name: "手指爬墙(向上)",
            seconds: 35,
            detail: "面对墙站立,患侧手指贴墙,像蜘蛛一样一格一格往上爬到有牵拉感的位置。",
            hint: "爬到有明显牵拉但不刺痛的高度,停住,深呼吸 3 次再慢慢爬回来。",
            symbol: "arrow.up.circle",
            motion: .wallWalk
        ),
        Exercise(
            name: "体前交叉拉伸",
            seconds: 35,
            detail: "患侧手臂伸直横过胸前,用对侧手托住肘部往身体方向轻压。",
            hint: "保持不弹动,肩膀别耸起来。感觉在肩后侧,不该在关节里面痛。",
            symbol: "arrow.left.circle",
            motion: .crossBody
        ),
        Exercise(
            name: "外旋拉伸",
            seconds: 40,
            detail: "上臂贴紧身体侧面,肘屈 90 度,前臂像开门一样向外打开。可以扶门框辅助。",
            hint: "肘部全程夹住身体不要外飘。这是肩周炎最容易受限的方向,慢一点。",
            symbol: "arrow.uturn.right.circle",
            motion: .externalRotation
        ),
        Exercise(
            name: "肩胛后缩 + 耸肩",
            seconds: 30,
            detail: "挺胸,两侧肩胛骨向中间夹紧保持 3 秒放松;再慢慢耸肩到最高,慢慢落下。",
            hint: "各做 5 次。这一步是把刚才拉开的活动度用姿势固定住。",
            symbol: "arrow.left.and.right.circle",
            motion: .scapularSqueeze
        ),
    ]

    static let disclaimer = "以上为常见的居家保守活动,不能替代医生或理疗师为你制定的方案。请只在「轻微牵拉、不引起尖锐疼痛」的范围内活动;若疼痛加剧、夜间痛明显或活动度突然下降,请及时就医。"

    /// 按配置的总时长等比缩放每一步,并保证各步之和精确等于总时长。
    static func plan(totalSeconds: Int) -> [Exercise] {
        let baseTotal = base.reduce(0) { $0 + $1.seconds }
        guard totalSeconds > 0, baseTotal > 0 else { return base }
        if totalSeconds == baseTotal { return base }

        let ratio = Double(totalSeconds) / Double(baseTotal)
        var scaled: [Exercise] = []
        var accumulated = 0
        for (i, ex) in base.enumerated() {
            let secs: Int
            if i == base.count - 1 {
                secs = max(5, totalSeconds - accumulated)   // 最后一步吃掉舍入误差
            } else {
                secs = max(5, Int((Double(ex.seconds) * ratio).rounded()))
            }
            accumulated += secs
            scaled.append(Exercise(name: ex.name, seconds: secs, detail: ex.detail,
                                   hint: ex.hint, symbol: ex.symbol, motion: ex.motion))
        }
        return scaled
    }
}
