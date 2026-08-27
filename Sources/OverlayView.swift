import SwiftUI

private enum Palette {
    static let bg1 = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let bg2 = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let accent = Color(red: 0.42, green: 0.78, blue: 0.72)
    static let warn = Color(red: 0.93, green: 0.53, blue: 0.36)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.96)
    static let dim = Color(red: 0.58, green: 0.62, blue: 0.67)
    static let faint = Color(red: 0.38, green: 0.41, blue: 0.45)
}

/// 主屏上的完整界面
struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    /// 按屏幕高度缩放,让 13 寸和 5K 上看起来差不多
    let scale: CGFloat

    var body: some View {
        ZStack {
            background
            if model.finished {
                finishedView
            } else {
                content
            }
            VStack {
                Spacer()
                escapeBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Palette.bg1, Palette.bg2],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.accent.opacity(0.10), .clear],
                           center: .center, startRadius: 0, endRadius: 620 * scale)
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                Spacer(minLength: 24 * scale)
                centerStage
                Spacer(minLength: 24 * scale)
                stepBar
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, max(48, geo.size.width * 0.055))
            .padding(.vertical, max(36, geo.size.height * 0.05))
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text("该活动肩膀了")
                    .font(.system(size: 34 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.text)
                Text(model.forced ? "延迟次数已用完,这一次必须做完"
                                  : "跟着下面的动作做,做完自动放行")
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundColor(model.forced ? Palette.warn : Palette.dim)
            }
            Spacer()
            HStack(alignment: .top, spacing: 18 * scale) {
                if model.ambientAvailable { muteButton }
                VStack(alignment: .trailing, spacing: 2 * scale) {
                    Text(mmss(model.remaining))
                        .font(.system(size: 60 * scale, weight: .thin, design: .rounded)
                            .monospacedDigit())
                        .foregroundColor(Palette.text)
                    Text("剩余总时长")
                        .font(.system(size: 12 * scale))
                        .foregroundColor(Palette.faint)
                }
            }
        }
    }

    // MARK: 中央当前动作

    private var centerStage: some View {
        HStack(spacing: 44 * scale) {
            stepRing
            VStack(alignment: .leading, spacing: 14 * scale) {
                Text("第 \(model.stepIndex + 1) / \(max(model.exercises.count, 1)) 步")
                    .font(.system(size: 13 * scale, weight: .medium))
                    .foregroundColor(Palette.accent)
                    .tracking(1.5)

                Text(model.currentExercise?.name ?? "")
                    .font(.system(size: 46 * scale, weight: .bold, design: .rounded))
                    .foregroundColor(Palette.text)

                Text(model.currentExercise?.detail ?? "")
                    .font(.system(size: 20 * scale, weight: .regular))
                    .foregroundColor(Palette.text.opacity(0.86))
                    .lineSpacing(6 * scale)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 8 * scale) {
                    Text("要点")
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundColor(Palette.bg1)
                        .padding(.horizontal, 7 * scale).padding(.vertical, 3 * scale)
                        .background(RoundedRectangle(cornerRadius: 4 * scale).fill(Palette.accent))
                    Text(model.currentExercise?.hint ?? "")
                        .font(.system(size: 15 * scale))
                        .foregroundColor(Palette.dim)
                        .lineSpacing(4 * scale)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4 * scale)
            }
            .frame(maxWidth: 560 * scale, alignment: .leading)

            figurePanel
        }
        .frame(maxWidth: .infinity)
    }

    /// 动作示意图:一个循环动画的简笔小人,患侧手臂高亮
    private var figurePanel: some View {
        VStack(spacing: 10 * scale) {
            if let ex = model.currentExercise {
                StickFigureView(motion: ex.motion,
                                mirrored: model.mirrored,
                                bothSides: model.bothSides,
                                accent: Palette.accent,
                                dim: Palette.dim)
                    .frame(width: 250 * scale, height: 250 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 18 * scale)
                            .fill(Color.white.opacity(0.03))
                    )
                Text(model.bothSides ? "双侧都做" : (model.mirrored ? "高亮的是左肩" : "高亮的是右肩"))
                    .font(.system(size: 11 * scale))
                    .foregroundColor(Palette.faint)

                if model.breathingOn {
                    BreathingRing(startedAt: model.startedAt, scale: scale,
                                  accent: Palette.accent, dim: Palette.dim,
                                  faint: Palette.faint)
                        .padding(.top, 8 * scale)
                }
            }
        }
    }

    /// 只静音背景音,提示音保留 —— 提示音是「该换动作了」的功能信息,不该一起关掉
    private var muteButton: some View {
        Button(action: { model.onToggleMute?() }) {
            Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15 * scale))
                .foregroundColor(model.muted ? Palette.faint : Palette.accent)
                .frame(width: 38 * scale, height: 38 * scale)
                .background(
                    Circle().fill(Color.white.opacity(model.muted ? 0.04 : 0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.muted ? "打开背景音" : "静音背景音(提示音保留)")
        .padding(.top, 8 * scale)
    }

    private var stepRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 14 * scale)
            Circle()
                .trim(from: 0, to: stepProgress)
                .stroke(Palette.accent,
                        style: StrokeStyle(lineWidth: 14 * scale, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: stepProgress)
            VStack(spacing: 2 * scale) {
                Image(systemName: model.currentExercise?.symbol ?? "circle")
                    .font(.system(size: 34 * scale, weight: .light))
                    .foregroundColor(Palette.accent)
                Text("\(max(0, model.stepRemaining))")
                    .font(.system(size: 52 * scale, weight: .thin, design: .rounded)
                        .monospacedDigit())
                    .foregroundColor(Palette.text)
                Text("秒")
                    .font(.system(size: 12 * scale))
                    .foregroundColor(Palette.faint)
            }
        }
        .frame(width: 230 * scale, height: 230 * scale)
    }

    private var stepProgress: CGFloat {
        guard model.stepTotal > 0 else { return 0 }
        let done = Double(model.stepTotal - model.stepRemaining) / Double(model.stepTotal)
        return CGFloat(min(max(done, 0), 1))
    }

    // MARK: 步骤进度条

    private var stepBar: some View {
        HStack(spacing: 8 * scale) {
            ForEach(Array(model.exercises.enumerated()), id: \.offset) { idx, ex in
                VStack(spacing: 6 * scale) {
                    RoundedRectangle(cornerRadius: 2 * scale)
                        .fill(idx < model.stepIndex ? Palette.accent.opacity(0.75)
                              : idx == model.stepIndex ? Palette.accent
                              : Color.white.opacity(0.12))
                        .frame(height: 4 * scale)
                    Text(ex.name)
                        .font(.system(size: 11 * scale))
                        .foregroundColor(idx == model.stepIndex ? Palette.text : Palette.faint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 26 * scale)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 24 * scale) {
            Text(ExerciseLibrary.disclaimer)
                .font(.system(size: 11 * scale))
                .foregroundColor(Palette.faint)
                .lineSpacing(3 * scale)
                .frame(maxWidth: 760 * scale, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            snoozeArea
        }
        .padding(.top, 26 * scale)
    }

    @ViewBuilder
    private var snoozeArea: some View {
        if model.forced {
            HStack(spacing: 8 * scale) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13 * scale))
                Text("本次不可延迟")
                    .font(.system(size: 15 * scale, weight: .semibold))
            }
            .foregroundColor(Palette.warn)
            .padding(.horizontal, 20 * scale).padding(.vertical, 12 * scale)
            .background(
                RoundedRectangle(cornerRadius: 10 * scale)
                    .stroke(Palette.warn.opacity(0.45), lineWidth: 1)
            )
        } else {
            Button(action: { model.onSnooze?() }) {
                HStack(spacing: 8 * scale) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14 * scale))
                    Text("延迟 5 分钟")
                        .font(.system(size: 16 * scale, weight: .semibold))
                    Text("还剩 \(model.snoozeRemaining) 次 · 或按 S")
                        .font(.system(size: 12 * scale))
                        .foregroundColor(Palette.bg1.opacity(0.65))
                }
                .foregroundColor(Palette.bg1)
                .padding(.horizontal, 22 * scale).padding(.vertical, 13 * scale)
                .background(RoundedRectangle(cornerRadius: 10 * scale).fill(Palette.accent))
                // 没有这一行,plain 样式的按钮只有文字本身可点,点边缘会落空
                .contentShape(RoundedRectangle(cornerRadius: 10 * scale))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Esc 逃生进度

    @ViewBuilder
    private var escapeBar: some View {
        if model.escProgress > 0.001 {
            VStack(spacing: 8 * scale) {
                Text("松开 Esc 即可取消 · 继续按住 \(String(format: "%.1f", remainingHold)) 秒将强制解除并记录一次跳过")
                    .font(.system(size: 13 * scale, weight: .medium))
                    .foregroundColor(Palette.warn)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                        .frame(width: 380 * scale, height: 6 * scale)
                    Capsule().fill(Palette.warn)
                        .frame(width: 380 * scale * CGFloat(model.escProgress), height: 6 * scale)
                }
            }
            // 独立浮层,免得和底部的免责声明糊在一起
            .padding(.horizontal, 30 * scale)
            .padding(.vertical, 18 * scale)
            .background(
                RoundedRectangle(cornerRadius: 14 * scale)
                    .fill(Color.black.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14 * scale)
                            .stroke(Palette.warn.opacity(0.4), lineWidth: 1)
                    )
            )
            .padding(.bottom, 130 * scale)
        }
    }

    private var remainingHold: Double {
        max(0, Double(model.escapeHoldSeconds) * (1 - model.escProgress))
    }

    // MARK: 完成画面

    private var finishedView: some View {
        VStack(spacing: 18 * scale) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 78 * scale, weight: .thin))
                .foregroundColor(Palette.accent)
            Text("完成,肩膀谢谢你")
                .font(.system(size: 30 * scale, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.text)
        }
    }
}

/// 副屏上的简版:同样盖死,但只显示必要信息,免得多块屏幕上一堆倒计时晃眼
struct OverlaySecondaryView: View {
    @ObservedObject var model: OverlayModel
    let scale: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bg1, Palette.bg2],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16 * scale) {
                Image(systemName: model.currentExercise?.symbol ?? "circle")
                    .font(.system(size: 46 * scale, weight: .ultraLight))
                    .foregroundColor(Palette.accent)
                Text(model.finished ? "完成" : (model.currentExercise?.name ?? ""))
                    .font(.system(size: 34 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.text)
                Text(mmss(model.remaining))
                    .font(.system(size: 66 * scale, weight: .thin, design: .rounded)
                        .monospacedDigit())
                    .foregroundColor(Palette.dim)
                Text("请看主屏幕操作")
                    .font(.system(size: 13 * scale))
                    .foregroundColor(Palette.faint)
            }
        }
    }
}

/// 跟着呼吸张缩的圆环。和背景音共用同一套公式、同一个起点,
/// 所以圆环张到最大时声音也最饱满,看到的和听到的是一回事。
/// 拉伸时跟着呼气能让肌肉放松、活动度更大。
struct BreathingRing: View {
    let startedAt: Date
    let scale: CGFloat
    let accent: Color
    let dim: Color
    let faint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let level = AmbientAudio.shared.breathLevel(at: elapsed)
            let inhaling = AmbientAudio.shared.isInhaling(at: elapsed)
            let size = (22 + 24 * level) * scale

            VStack(spacing: 5 * scale) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1.5 * scale)
                        .frame(width: 50 * scale, height: 50 * scale)
                    Circle()
                        .fill(accent.opacity(0.08 + 0.20 * level))
                        .frame(width: size, height: size)
                    Circle()
                        .stroke(accent.opacity(0.40 + 0.45 * level), lineWidth: 2.0 * scale)
                        .frame(width: size, height: size)
                }
                .frame(width: 52 * scale, height: 52 * scale)

                Text(inhaling ? "吸气" : "呼气")
                    .font(.system(size: 11 * scale, weight: .medium))
                    .foregroundColor(inhaling ? accent.opacity(0.9) : faint)
            }
        }
    }
}
