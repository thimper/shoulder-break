import SwiftUI

// MARK: - 姿势描述

/// 一条手臂怎么摆,有三种指定方式
enum ArmPose {
    /// 直接给角度。0 度 = 垂直向下,正数朝身体外侧转;前臂角度是相对上臂的偏移
    case angles(upper: Double, fore: Double)
    /// 只说「手要够到画布上的这一点」,肘部由反向运动学反推
    /// (IK / 反向运动学:先定手的位置,再算肘该弯多少。bend 决定肘往哪边拐)
    case reach(to: CGPoint, bend: Double)
    /// 外旋专用:上臂角度固定贴身,前臂在水平面里转,
    /// 靠画面上的长度缩短来表现「转向观察者」这个立体动作
    case twist(upper: Double, rotation: Double)
}

/// 画在人旁边的参照物,帮助理解动作
enum Prop {
    case wall(x: Double)                                   // 一堵墙(相对宽度位置)
    case desk(y: Double, from: Double, to: Double)         // 一条桌沿
    case orbit(center: CGPoint, size: CGSize)              // 虚线轨迹圈
    case arcArrow(center: CGPoint, radius: Double, start: Double, end: Double)
    case vArrow(at: CGPoint, length: Double)               // 上下双向箭头
    case guideLine(y: Double, from: Double, to: Double)    // 虚线基准线
}

struct Pose {
    var lean: Double = 0             // 躯干前倾程度
    var shrug: Double = 0            // 耸肩,0...1
    var chestOut: Double = 0         // 挺胸/肩胛后缩,0...1
    var left: ArmPose = .angles(upper: 8, fore: 4)
    var right: ArmPose = .angles(upper: 8, fore: 4)
    var props: [Prop] = []
}

// MARK: - 缓动

private func easeInOut(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
}

/// 把 0...1 变成「去了再回来」
private func pingPong(_ t: Double) -> Double {
    let x = t.truncatingRemainder(dividingBy: 1)
    return x < 0.5 ? easeInOut(x * 2) : easeInOut((1 - x) * 2)
}

// MARK: - 每个动作的姿势

enum PoseBuilder {
    static func pose(for motion: ExerciseMotion, phase: Double, mirrored: Bool) -> Pose {
        var p: Pose
        switch motion {
        case .pendulum:         p = pendulum(phase)
        case .wallWalk:         p = wallWalk(phase)
        case .crossBody:        p = crossBody(phase)
        case .externalRotation: p = externalRotation(phase)
        case .scapularSqueeze:  p = scapularSqueeze(phase)
        }
        if mirrored { p = mirror(p) }
        return p
    }

    /// 患侧换到另一边:左右手对调,所有横向坐标沿画布中线翻过去
    private static func mirror(_ p: Pose) -> Pose {
        var m = p
        m.lean = -p.lean
        m.left = flip(p.right)
        m.right = flip(p.left)
        m.props = p.props.map { prop in
            switch prop {
            case .wall(let x): return .wall(x: 1 - x)
            case .desk(let y, let f, let t): return .desk(y: y, from: 1 - t, to: 1 - f)
            case .orbit(let c, let s): return .orbit(center: CGPoint(x: 1 - c.x, y: c.y), size: s)
            case .arcArrow(let c, let r, let s, let e):
                return .arcArrow(center: CGPoint(x: 1 - c.x, y: c.y), radius: r, start: 180 - e, end: 180 - s)
            case .vArrow(let at, let l): return .vArrow(at: CGPoint(x: 1 - at.x, y: at.y), length: l)
            case .guideLine(let y, let f, let t): return .guideLine(y: y, from: 1 - t, to: 1 - f)
            }
        }
        return m
    }

    private static func flip(_ a: ArmPose) -> ArmPose {
        switch a {
        case .angles(let u, let f): return .angles(upper: u, fore: f)
        case .reach(let to, let bend): return .reach(to: CGPoint(x: 1 - to.x, y: to.y), bend: -bend)
        case .twist(let u, let r): return .twist(upper: u, rotation: r)
        }
    }

    /// 身体前倾扶桌,患侧手臂完全放松垂下来,靠身体带着画圈
    private static func pendulum(_ phase: Double) -> Pose {
        // 摆动整体偏向身体外侧,别让手甩进躯干里去
        let swing = 11 + sin(phase * 2 * .pi) * 19
        return Pose(
            lean: 30,
            left: .reach(to: CGPoint(x: 0.30, y: 0.56), bend: 1),   // 健侧手撑住桌沿
            right: .angles(upper: swing, fore: 3),                  // 患侧手放松地晃
            props: [
                .desk(y: 0.575, from: 0.15, to: 0.38),
                .orbit(center: CGPoint(x: 0.632, y: 0.60), size: CGSize(width: 0.19, height: 0.072)),
            ]
        )
    }

    /// 面墙,患侧手指贴着墙一格格往上挪,肘随之慢慢弯起来
    private static func wallWalk(_ phase: Double) -> Pose {
        let up: Double
        if phase < 0.55 {
            up = easeInOut(phase / 0.55)               // 往上爬
        } else if phase < 0.78 {
            up = 1                                      // 到顶停住深呼吸
        } else {
            up = 1 - easeInOut((phase - 0.78) / 0.22)   // 慢慢放下来
        }
        let wallX = 0.84
        // 手始终贴在墙面上,只有高度在变
        let handY = 0.42 - up * 0.30
        return Pose(
            lean: 0,
            shrug: up * 0.3,
            left: .angles(upper: 9, fore: 4),
            right: .reach(to: CGPoint(x: wallX, y: handY), bend: 1),
            props: [.wall(x: wallX)]
        )
    }

    /// 患侧手臂横过胸前,健侧手托住它的肘往里压
    private static func crossBody(_ phase: Double) -> Pose {
        let t = pingPong(phase)
        // 患侧手:从垂在体侧 → 横过胸前伸到对侧。
        // 两端都让手臂接近伸直(目标点离肩约等于臂长),
        // 否则 IK 只能把肘大幅折起来,看着像叉腰而不是横拉。
        let handX = 0.615 - t * 0.285
        let handY = 0.615 - t * 0.255
        // 健侧手:从自然垂下 → 抬到胸前托住患侧肘
        let helpX = 0.385 + t * 0.085
        let helpY = 0.615 - t * 0.215
        return Pose(
            lean: 0,
            left: .reach(to: CGPoint(x: helpX, y: helpY), bend: 1),
            right: .reach(to: CGPoint(x: handX, y: handY), bend: -1),
            props: t > 0.45
                ? [.arcArrow(center: CGPoint(x: 0.47, y: 0.52), radius: 0.10, start: -30, end: -150)]
                : []
        )
    }

    /// 上臂夹紧身体不动,前臂像开门一样在水平面里向外转。
    /// 正面看过去,前臂转向观察者时会「变短」,转到外侧时又「伸长」——
    /// 这个长度变化就是旋转的视觉线索。
    private static func externalRotation(_ phase: Double) -> Pose {
        let t = pingPong(phase)
        let rotation = -32 + t * 96          // 内旋 -32° → 外旋 +64°
        return Pose(
            lean: 0,
            left: .twist(upper: 7, rotation: -20 + t * 60),
            right: .twist(upper: 7, rotation: rotation),
            props: [.arcArrow(center: CGPoint(x: 0.615, y: 0.545), radius: 0.135, start: 100, end: 8)]
        )
    }

    /// 前半段肩胛骨向中间夹紧(挺胸),后半段慢耸肩慢放下
    private static func scapularSqueeze(_ phase: Double) -> Pose {
        let squeeze = phase < 0.5 ? pingPong(phase * 2) : 0
        let shrug = phase >= 0.5 ? pingPong((phase - 0.5) * 2) : 0
        return Pose(
            lean: 0,
            shrug: shrug,
            chestOut: squeeze,
            // 肘往后拉、手搭在腰侧
            // 手臂自然垂在体侧,肩胛夹紧时略微外展,别折进躯干里
            left: .angles(upper: 11 + squeeze * 6, fore: 7),
            right: .angles(upper: 11 + squeeze * 6, fore: 7),
            props: shrug > 0.06
                ? [.guideLine(y: 0.342, from: 0.30, to: 0.70),
                   .vArrow(at: CGPoint(x: 0.82, y: 0.30), length: 0.11)]
                : []
        )
    }
}

// MARK: - 视图

/// 会动的版本:自己按屏幕刷新率推进,不惊动外层的倒计时界面
struct StickFigureView: View {
    let motion: ExerciseMotion
    let mirrored: Bool
    let bothSides: Bool
    let accent: Color
    let dim: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (t / motion.cycleSeconds).truncatingRemainder(dividingBy: 1.0)
            StickFigureCanvas(motion: motion, phase: phase, mirrored: mirrored,
                              bothSides: bothSides, accent: accent, dim: dim)
        }
    }
}

/// 定格版本:给定 phase 画一帧,离屏渲染和导 GIF 都用它
struct StickFigureCanvas: View {
    let motion: ExerciseMotion
    let phase: Double
    let mirrored: Bool
    let bothSides: Bool
    let accent: Color
    let dim: Color

    var body: some View {
        Canvas { context, size in
            let pose = PoseBuilder.pose(for: motion, phase: phase, mirrored: mirrored)
            Renderer(pose: pose, mirrored: mirrored, bothSides: bothSides,
                     accent: accent, dim: dim)
                .draw(in: &context, size: size)
        }
    }
}

// MARK: - 绘制

private struct Renderer {
    let pose: Pose
    let mirrored: Bool
    let bothSides: Bool
    let accent: Color
    let dim: Color

    // 人按 100 单位高设计,再整体缩到画布的 88%,给举高的手臂留出天花板
    private let designHeight: CGFloat = 114
    private let topPad: CGFloat = 9

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let unit = size.height / designHeight
        let cx = size.width / 2
        func U(_ v: Double) -> CGFloat { CGFloat(v) * unit }
        func Y(_ v: Double) -> CGFloat { (CGFloat(v) + topPad) * unit }

        let lineW = max(2.0, unit * 2.0)
        let limbW = max(1.7, unit * 1.7)

        let hipY = Y(62)
        let shoulderY = Y(30) - CGFloat(pose.shrug) * U(9.5)
        let leanX = CGFloat(pose.lean) / 24 * U(7)
        let shoulderCX = cx + leanX
        let shoulderHalf = U(9.5) * (1 + CGFloat(pose.chestOut) * 0.16)
        let headR = U(6.2)

        let hip = CGPoint(x: cx, y: hipY)
        let neck = CGPoint(x: shoulderCX, y: shoulderY - U(2.2))
        let head = CGPoint(x: shoulderCX + leanX * 0.4, y: neck.y - headR - U(1.6))
        let lShoulder = CGPoint(x: shoulderCX - shoulderHalf, y: shoulderY)
        let rShoulder = CGPoint(x: shoulderCX + shoulderHalf, y: shoulderY)

        let upperLen = U(15.5)
        let foreLen = U(15.0)

        let leftActive = bothSides || mirrored
        let rightActive = bothSides || !mirrored

        // 参照物先画,压在人后面
        for prop in pose.props {
            drawProp(prop, in: &ctx, size: size, unit: unit, lineW: lineW)
        }

        // 头、躯干、肩线
        ctx.stroke(Path(ellipseIn: CGRect(x: head.x - headR, y: head.y - headR,
                                          width: headR * 2, height: headR * 2)),
                   with: .color(dim), lineWidth: lineW)
        var torso = Path()
        torso.move(to: CGPoint(x: head.x, y: head.y + headR))
        torso.addLine(to: neck)
        torso.addLine(to: hip)
        ctx.stroke(torso, with: .color(dim), style: StrokeStyle(lineWidth: lineW, lineCap: .round))

        var shoulderLine = Path()
        shoulderLine.move(to: lShoulder)
        shoulderLine.addLine(to: rShoulder)
        ctx.stroke(shoulderLine, with: .color(pose.chestOut > 0.15 ? accent.opacity(0.8) : dim),
                   style: StrokeStyle(lineWidth: lineW * (1 + CGFloat(pose.chestOut) * 0.5),
                                      lineCap: .round))

        // 腿始终不动,免得抢视线
        for dir in [-1.0, 1.0] {
            let knee = CGPoint(x: hip.x + CGFloat(dir) * U(4.6), y: hipY + U(17))
            let foot = CGPoint(x: hip.x + CGFloat(dir) * U(6.4), y: hipY + U(34))
            var leg = Path()
            leg.move(to: hip); leg.addLine(to: knee); leg.addLine(to: foot)
            ctx.stroke(leg, with: .color(dim.opacity(0.7)),
                       style: StrokeStyle(lineWidth: lineW * 0.9, lineCap: .round, lineJoin: .round))
        }

        // 手臂
        drawArm(pose.left, shoulder: lShoulder, side: -1, size: size,
                upperLen: upperLen, foreLen: foreLen, unit: unit, width: limbW,
                color: leftActive ? accent : dim.opacity(0.5), active: leftActive, ctx: &ctx)
        drawArm(pose.right, shoulder: rShoulder, side: 1, size: size,
                upperLen: upperLen, foreLen: foreLen, unit: unit, width: limbW,
                color: rightActive ? accent : dim.opacity(0.5), active: rightActive, ctx: &ctx)
    }

    // MARK: 手臂

    private func drawArm(_ arm: ArmPose, shoulder: CGPoint, side: Double, size: CGSize,
                         upperLen: CGFloat, foreLen: CGFloat, unit: CGFloat, width: CGFloat,
                         color: Color, active: Bool, ctx: inout GraphicsContext) {
        var elbow: CGPoint
        var hand: CGPoint

        switch arm {
        case .angles(let upper, let fore):
            elbow = joint(from: shoulder, angle: upper, len: upperLen, side: side)
            hand = joint(from: elbow, angle: upper + fore, len: foreLen, side: side)

        case .reach(let to, let bend):
            let target = CGPoint(x: to.x * size.width, y: to.y * size.height)
            (elbow, hand) = solveIK(shoulder: shoulder, target: target,
                                    l1: upperLen, l2: foreLen, bend: bend)

        case .twist(let upper, let rotation):
            // 上臂贴身垂着
            elbow = joint(from: shoulder, angle: upper, len: upperLen, side: side)
            // 前臂在水平面里转:画面上的长度 = 真实长度 × sin(旋转角),
            // 转到正前方时几乎缩成一点,转到外侧时完全展开
            let rad = rotation * .pi / 180
            let horizontal = CGFloat(sin(rad)) * foreLen
            let depth = CGFloat(cos(rad)) * foreLen * 0.26   // 指向观察者的那部分,用略微上抬来暗示
            hand = CGPoint(x: elbow.x + side * horizontal, y: elbow.y - abs(depth))
        }

        var path = Path()
        path.move(to: shoulder)
        path.addLine(to: elbow)
        path.addLine(to: hand)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width * (active ? 1.3 : 1.0),
                                      lineCap: .round, lineJoin: .round))

        let r = unit * (active ? 2.4 : 1.8)
        ctx.fill(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: r * 2, height: r * 2)),
                 with: .color(color))
    }

    /// 角度 0 = 垂直向下,正数朝该侧外方向转。side: 1 = 画面右臂,-1 = 左臂
    private func joint(from: CGPoint, angle: Double, len: CGFloat, side: Double) -> CGPoint {
        let rad = angle * .pi / 180
        return CGPoint(x: from.x + CGFloat(side) * CGFloat(sin(rad)) * len,
                       y: from.y + CGFloat(cos(rad)) * len)
    }

    /// 反向运动学:已知肩和手要到的位置,用余弦定理反推肘在哪
    private func solveIK(shoulder: CGPoint, target: CGPoint,
                         l1: CGFloat, l2: CGFloat, bend: Double) -> (CGPoint, CGPoint) {
        let dx = target.x - shoulder.x
        let dy = target.y - shoulder.y
        let raw = sqrt(dx * dx + dy * dy)
        let reach = l1 + l2
        let d = min(raw, reach * 0.999)
        let baseAngle = atan2(dy, dx)

        // 够不到就把手臂伸直指过去,手停在够得着的最远处
        guard raw > 0.0001 else { return (shoulder, shoulder) }
        let cosA = (d * d + l1 * l1 - l2 * l2) / (2 * d * l1)
        let a = acos(min(max(cosA, -1), 1))
        let elbowAngle = baseAngle + CGFloat(bend) * a
        let elbow = CGPoint(x: shoulder.x + cos(elbowAngle) * l1,
                            y: shoulder.y + sin(elbowAngle) * l1)
        let hand = raw <= reach
            ? target
            : CGPoint(x: shoulder.x + cos(baseAngle) * reach,
                      y: shoulder.y + sin(baseAngle) * reach)
        return (elbow, hand)
    }

    // MARK: 参照物

    private func drawProp(_ prop: Prop, in ctx: inout GraphicsContext,
                          size: CGSize, unit: CGFloat, lineW: CGFloat) {
        let hint = dim.opacity(0.45)
        switch prop {
        case .wall(let x):
            var p = Path()
            p.move(to: CGPoint(x: x * size.width, y: size.height * 0.04))
            p.addLine(to: CGPoint(x: x * size.width, y: size.height * 0.96))
            ctx.stroke(p, with: .color(hint),
                       style: StrokeStyle(lineWidth: lineW * 0.85, lineCap: .round,
                                          dash: [unit * 2.6, unit * 2.6]))

        case .desk(let y, let from, let to):
            var p = Path()
            p.move(to: CGPoint(x: from * size.width, y: y * size.height))
            p.addLine(to: CGPoint(x: to * size.width, y: y * size.height))
            ctx.stroke(p, with: .color(hint),
                       style: StrokeStyle(lineWidth: lineW * 1.1, lineCap: .round))

        case .orbit(let center, let s):
            let rect = CGRect(x: (center.x - s.width / 2) * size.width,
                              y: (center.y - s.height / 2) * size.height,
                              width: s.width * size.width,
                              height: s.height * size.height)
            ctx.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(0.35)),
                       style: StrokeStyle(lineWidth: lineW * 0.7, lineCap: .round,
                                          dash: [unit * 2, unit * 2.4]))

        case .arcArrow(let center, let radius, let start, let end):
            let c = CGPoint(x: center.x * size.width, y: center.y * size.height)
            let r = radius * size.width
            var p = Path()
            p.addArc(center: c, radius: r,
                     startAngle: .degrees(start), endAngle: .degrees(end),
                     clockwise: start > end)
            ctx.stroke(p, with: .color(accent.opacity(0.55)),
                       style: StrokeStyle(lineWidth: lineW * 0.75, lineCap: .round))
            // 箭头尖
            let endRad = end * .pi / 180
            let tip = CGPoint(x: c.x + cos(endRad) * r, y: c.y + sin(endRad) * r)
            let dir = (start > end ? -1.0 : 1.0)
            let tangent = endRad + CGFloat(dir) * .pi / 2
            var head = Path()
            let hs = unit * 3.2
            head.move(to: tip)
            head.addLine(to: CGPoint(x: tip.x - cos(tangent - 0.5) * hs, y: tip.y - sin(tangent - 0.5) * hs))
            head.move(to: tip)
            head.addLine(to: CGPoint(x: tip.x - cos(tangent + 0.5) * hs, y: tip.y - sin(tangent + 0.5) * hs))
            ctx.stroke(head, with: .color(accent.opacity(0.7)),
                       style: StrokeStyle(lineWidth: lineW * 0.75, lineCap: .round))

        case .guideLine(let y, let from, let to):
            var g = Path()
            g.move(to: CGPoint(x: from * size.width, y: y * size.height))
            g.addLine(to: CGPoint(x: to * size.width, y: y * size.height))
            ctx.stroke(g, with: .color(dim.opacity(0.32)),
                       style: StrokeStyle(lineWidth: lineW * 0.6, lineCap: .round,
                                          dash: [unit * 1.8, unit * 2.2]))

        case .vArrow(let at, let length):
            let x = at.x * size.width
            let yc = at.y * size.height
            let half = length * size.height / 2
            var p = Path()
            p.move(to: CGPoint(x: x, y: yc - half))
            p.addLine(to: CGPoint(x: x, y: yc + half))
            let hs = unit * 2.6
            for (tipY, sign) in [(yc - half, 1.0), (yc + half, -1.0)] {
                p.move(to: CGPoint(x: x, y: tipY))
                p.addLine(to: CGPoint(x: x - hs * 0.7, y: tipY + CGFloat(sign) * hs))
                p.move(to: CGPoint(x: x, y: tipY))
                p.addLine(to: CGPoint(x: x + hs * 0.7, y: tipY + CGFloat(sign) * hs))
            }
            ctx.stroke(p, with: .color(accent.opacity(0.6)),
                       style: StrokeStyle(lineWidth: lineW * 0.75, lineCap: .round))
        }
    }
}
