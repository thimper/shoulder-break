import AVFoundation
import Foundation

/// 黑幕期间的声音。两层:
/// - 背景层:几个低音正弦波叠成一个安静的和弦,音量跟着呼吸节奏缓慢涨落
/// - 提示层:动作切换、全部完成时响一下的柔和钟声
///
/// 全部由代码实时算出来,不打包任何音频文件——没有版权问题,
/// 也能让提示音和背景音落在同一个调上,听起来是一体的。
final class AmbientAudio {
    static let shared = AmbientAudio()
    private init() {}

    // MARK: 音高(C 调,只用根音/五度/八度,不加三度)
    //  加了三度就有明确的大调或小调情绪,垫在底下三分钟会喧宾夺主。

    struct Voice {
        let frequency: Double
        let gain: Double
        /// 失谐量:同一个音用两个频率极接近的正弦波叠加,
        /// 会产生缓慢的「拍频」——音量自己轻微起伏,听着温暖、不像电子音那样死板
        let detune: Double
    }

    /// 颂钵:每次呼吸敲一到两个音,让它自己衰减完,音符之间留白。
    ///
    /// 音符不是随机撒的,而是卡在呼吸节拍上——吸气起头敲一个高音、
    /// 呼气起头敲一个低音。这样声音本身就是呼吸节拍器,
    /// 比单纯让音量涨落的暗示强得多。
    ///
    /// 音阶用五声音阶(C D F G A C),这几个音随便怎么撞都不会出难听的和声。
    /// 同实时和弦一样,这里面不能分配内存、不能加锁,所以活跃音符用定长数组装。
    struct BowlSynth {
        struct Note {
            var freq: Double = 0
            var startSample: Double = 0
            var decay: Double = 4
            var amp: Double = 0
            var active: Bool = false
        }

        let sampleRate: Double
        var notes: [Note]
        var elapsedSamples: Double = 0
        var nextFreeTrigger: Double = 0
        var lastBreathKey: Int = -1
        var seed: UInt64 = 0x2545F4914F6CDD1D

        /// 吸气用的高音、呼气用的低音,一听就知道该吸还是该呼
        let highNotes: [Double] = [523.25, 587.33, 659.25]              // C5 D5 E5
        let lowNotes: [Double] = [261.63, 293.66, 349.23, 392.00]       // C4 D4 F4 G4

        init(sampleRate: Double) {
            self.sampleRate = sampleRate
            self.notes = Array(repeating: Note(), count: 6)
        }

        private mutating func rand() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 10_000) / 10_000.0
        }

        private mutating func spawn(_ freq: Double, amp: Double, decay: Double) {
            for i in 0..<notes.count where !notes[i].active {
                notes[i] = Note(freq: freq, startSample: elapsedSamples,
                                decay: decay, amp: amp, active: true)
                return
            }
            // 都占满了就顶掉最老的那个
            var oldest = 0
            for i in 1..<notes.count where notes[i].startSample < notes[oldest].startSample {
                oldest = i
            }
            notes[oldest] = Note(freq: freq, startSample: elapsedSamples,
                                 decay: decay, amp: amp, active: true)
        }

        mutating func nextSample(breathing: Bool, breathIn: Double, breathOut: Double) -> Double {
            let t = elapsedSamples / sampleRate

            if breathing {
                let cycle = breathIn + breathOut
                let phase = t.truncatingRemainder(dividingBy: cycle)
                let segment = phase < breathIn ? 0 : 1
                let key = Int(t / cycle) * 2 + segment
                if key != lastBreathKey {
                    lastBreathKey = key
                    if segment == 0 {
                        let n = highNotes[Int(rand() * Double(highNotes.count)) % highNotes.count]
                        spawn(n, amp: 0.60, decay: 3.4)      // 吸气:亮一点
                    } else {
                        let n = lowNotes[Int(rand() * Double(lowNotes.count)) % lowNotes.count]
                        spawn(n, amp: 0.52, decay: 4.8)      // 呼气:沉一点、留得久一点
                    }
                }
            } else if elapsedSamples >= nextFreeTrigger {
                let pool = lowNotes + highNotes
                let n = pool[Int(rand() * Double(pool.count)) % pool.count]
                spawn(n, amp: 0.55, decay: 4.0)
                nextFreeTrigger = elapsedSamples + (3.0 + rand() * 3.0) * sampleRate
            }

            var out = 0.0
            for i in 0..<notes.count {
                guard notes[i].active else { continue }
                let tt = (elapsedSamples - notes[i].startSample) / sampleRate
                if tt > notes[i].decay * 2.4 {
                    notes[i].active = false
                    continue
                }
                let env = min(1.0, tt / 0.012) * exp(-tt * (4.2 / notes[i].decay))
                let f = notes[i].freq
                // 钟和钵的泛音不是整数倍,这正是它区别于普通乐音的地方
                let v = sin(2 * .pi * f * tt)
                      + 0.32 * sin(2 * .pi * f * 2.76 * tt) * exp(-tt * 1.6)
                      + 0.14 * sin(2 * .pi * f * 5.40 * tt) * exp(-tt * 2.6)
                out += v * env * notes[i].amp * 0.30
            }
            elapsedSamples += 1
            return out
        }
    }

    /// 雨声:噪音过两级低通,强弱缓慢变化
    struct RainSynth {
        let sampleRate: Double
        var seed: UInt32 = 22222
        var lp1 = 0.0, lp2 = 0.0
        var elapsedSamples: Double = 0

        mutating func nextSample() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Double(Int32(bitPattern: seed)) / Double(Int32.max)
            let cut = 1400.0 + 500.0 * sin(2 * .pi * elapsedSamples / sampleRate / 11.0)
            let coef = exp(-2.0 * Double.pi * cut / sampleRate)
            lp1 = white * (1 - coef) + lp1 * coef
            lp2 = lp1 * (1 - coef) + lp2 * coef
            elapsedSamples += 1
            return lp2 * 2.6
        }
    }

    /// 逐采样算出和弦的那段算法。抽成独立结构是为了让实时播放和离线导出
    /// 共用同一份代码——否则导出来验证的就不是真正在播的东西了。
    /// 注意:实时回调在音频线程上跑,这里面不能分配内存、不能加锁。
    struct ChordSynth {
        let voices: [Voice]
        let sampleRate: Double
        var phases: [Double]
        var phasesDetuned: [Double]
        var elapsedSamples: Double = 0

        init(voices: [Voice], sampleRate: Double) {
            self.voices = voices
            self.sampleRate = sampleRate
            self.phases = Array(repeating: 0, count: voices.count)
            self.phasesDetuned = Array(repeating: 0, count: voices.count)
        }

        mutating func nextSample(breathing: Bool, breathIn: Double, breathOut: Double) -> Double {
            let twoPi = 2.0 * Double.pi
            let elapsed = elapsedSamples / sampleRate
            // 呼吸起伏:吸气时饱满、呼气时退下去,但不会掉到听不见
            let breath = breathing
                ? 0.58 + 0.42 * AmbientAudio.breathCurve(elapsed: elapsed,
                                                         inhale: breathIn, exhale: breathOut)
                : 1.0
            var sample = 0.0
            for i in 0..<voices.count {
                let v = voices[i]
                phases[i] += twoPi * v.frequency / sampleRate
                phasesDetuned[i] += twoPi * (v.frequency + v.detune) / sampleRate
                if phases[i] > twoPi { phases[i] -= twoPi }
                if phasesDetuned[i] > twoPi { phasesDetuned[i] -= twoPi }
                let a = sin(phases[i])
                let b = sin(phasesDetuned[i])
                // 主音占绝大部分、失谐音只掺一点点:
                // 两路等幅叠加会让振幅在 0 到满值之间大幅摆动,那种起伏会盖过呼吸节奏,
                // 听起来是「哇哇」的抖动而不是呼吸。压到 6% 后只剩温暖的音色感。
                let harmonic = 0.10 * sin(phases[i] * 2)
                sample += v.gain * (a * 0.94 + b * 0.06 + harmonic)
            }
            elapsedSamples += 1
            return sample * 0.34 * breath
        }
    }

    let voices: [Voice] = [
        Voice(frequency: 130.81, gain: 0.50, detune: 0.15),  // C3 根音
        Voice(frequency: 196.00, gain: 0.34, detune: 0.19),  // G3 五度
        Voice(frequency: 261.63, gain: 0.26, detune: 0.23),  // C4 八度
        Voice(frequency: 392.00, gain: 0.10, detune: 0.27),  // G4 一点空气感
    ]

    private let chimeStep: Double = 783.99      // G5,动作切换
    private let chimeDoneLow: Double = 523.25   // C5 ┐ 全部完成时的上行双音
    private let chimeDoneHigh: Double = 783.99  // G5 ┘

    // MARK: 引擎

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var chimePlayer: AVAudioPlayerNode?
    private var configObserver: NSObjectProtocol?
    private var sampleRate: Double = 44100

    /// 下面这几个值由主线程写、音频线程读。
    /// 音频回调跑在实时线程上,不能加锁,所以只用简单的标量,
    /// 偶尔读到过渡中的值对音量渐变来说没有影响。
    private var targetLevel: Double = 0        // 淡入淡出的目标
    private var currentLevel: Double = 0       // 实际音量,每个采样点朝目标靠拢
    private var fadeStep: Double = 0           // 每个采样点移动多少
    private var baseVolume: Double = 0.28
    private var muted: Bool = false
    private var breathingOn: Bool = true
    private var breathIn: Double = 4
    private var breathOut: Double = 6

    /// 合成器状态。音频线程独占,别的地方不要碰。
    private var synth = ChordSynth(voices: [], sampleRate: 44100)
    private var bowl = BowlSynth(sampleRate: 44100)
    private var rain = RainSynth(sampleRate: 44100)
    private var style: AmbientStyle = .bowl

    private(set) var isRunning = false

    // MARK: - 对外接口

    /// 开始播放背景音,带淡入。重复调用是安全的。
    func start(style: AmbientStyle, volume: Double, muted: Bool, breathing: Bool,
               breathInSeconds: Double, breathOutSeconds: Double,
               fadeInSeconds: Double = 2.0) {
        self.style = style
        self.baseVolume = min(max(volume, 0), 1)
        self.muted = muted
        self.breathingOn = breathing
        self.breathIn = max(1, breathInSeconds)
        self.breathOut = max(1, breathOutSeconds)

        if isRunning {
            setMuted(muted)
            return
        }
        guard buildEngine() else { return }
        isRunning = true
        currentLevel = 0
        fadeTo(muted ? 0 : 1, over: fadeInSeconds)
    }

    /// 淡出并停止。淡出走完才真正拆掉引擎,避免尾部爆音。
    func stop(fadeOutSeconds: Double = 0.8) {
        guard isRunning else { return }
        fadeTo(0, over: fadeOutSeconds)
        let delay = fadeOutSeconds + 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.teardownEngine()
        }
    }

    func setMuted(_ on: Bool) {
        muted = on
        guard isRunning else { return }
        fadeTo(on ? 0 : 1, over: 0.45)
    }

    /// 动作切换的提示音
    func playStepChime(volume: Double) {
        playChime(frequencies: [(chimeStep, 0.0)], volume: volume)
    }

    /// 全部做完的上行双音
    func playCompletionChime(volume: Double) {
        playChime(frequencies: [(chimeDoneLow, 0.0), (chimeDoneHigh, 0.15)], volume: volume)
    }

    /// 界面上的呼吸圆环用这个算张缩,和背景音共用同一套公式,保证看到的和听到的一致。
    /// 返回 0(呼到底)到 1(吸满)。
    func breathLevel(at elapsed: TimeInterval) -> Double {
        Self.breathCurve(elapsed: elapsed, inhale: breathIn, exhale: breathOut)
    }

    func isInhaling(at elapsed: TimeInterval) -> Bool {
        let cycle = breathIn + breathOut
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        return t < breathIn
    }

    var breathCycleSeconds: Double { breathIn + breathOut }

    // MARK: - 呼吸曲线

    /// 吸气段 0 → 1,呼气段 1 → 0,两段都用余弦过渡。
    /// 直线过渡在转折点会有明显的「咔」的感觉,余弦才像真实呼吸。
    static func breathCurve(elapsed: TimeInterval, inhale: Double, exhale: Double) -> Double {
        let cycle = inhale + exhale
        guard cycle > 0 else { return 1 }
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        if t < inhale {
            let p = t / inhale
            return 0.5 - 0.5 * cos(p * .pi)
        } else {
            let p = (t - inhale) / exhale
            return 0.5 + 0.5 * cos(p * .pi)
        }
    }

    // MARK: - 引擎搭建

    private func buildEngine() -> Bool {
        let engine = AVAudioEngine()
        let output = engine.outputNode
        let outputFormat = output.inputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44100

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            Log.warn("音频格式创建失败,本次不播放背景音")
            return false
        }

        synth = ChordSynth(voices: style == .padWarm ? warmVoices : voices, sampleRate: sampleRate)
        bowl = BowlSynth(sampleRate: sampleRate)
        rain = RainSynth(sampleRate: sampleRate)

        // 这个回调跑在实时音频线程上:不能分配内存、不能加锁、不能打日志,
        // 否则会掉采样、听到爆音。下面只有浮点运算。
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                // 音量朝目标平滑靠拢(淡入淡出)
                if self.currentLevel < self.targetLevel {
                    self.currentLevel = min(self.targetLevel, self.currentLevel + self.fadeStep)
                } else if self.currentLevel > self.targetLevel {
                    self.currentLevel = max(self.targetLevel, self.currentLevel - self.fadeStep)
                }

                var raw: Double
                switch self.style {
                case .bowl:
                    // 颂钵的音符卡在呼吸节拍上,它自己就是引导,不再叠音量起伏
                    raw = self.bowl.nextSample(breathing: self.breathingOn,
                                               breathIn: self.breathIn,
                                               breathOut: self.breathOut)
                case .rain:
                    raw = self.rain.nextSample()
                    if self.breathingOn {
                        let t = self.rain.elapsedSamples / self.sampleRate
                        raw *= 0.58 + 0.42 * AmbientAudio.breathCurve(
                            elapsed: t, inhale: self.breathIn, exhale: self.breathOut)
                    }
                case .padLow, .padWarm:
                    raw = self.synth.nextSample(breathing: self.breathingOn,
                                                breathIn: self.breathIn,
                                                breathOut: self.breathOut)
                }
                let value = Float(raw * self.baseVolume * self.currentLevel)

                for buffer in buffers {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = value
                }
            }
            return noErr
        }

        let player = AVAudioPlayerNode()

        engine.attach(node)
        engine.attach(player)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            engine.prepare()
            try engine.start()
            player.play()
        } catch {
            Log.warn("音频引擎起不来,本次静默运行:\(error.localizedDescription)")
            return false
        }

        self.engine = engine
        self.sourceNode = node
        self.chimePlayer = player

        // 拔耳机、切外放、蓝牙断连都会走到这里。不重建的话声音会哑掉且不自己恢复。
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
        return true
    }

    private func handleConfigurationChange() {
        guard isRunning else { return }
        Log.info("音频输出设备变了,重建引擎")
        let keepLevel = targetLevel
        teardownEngine(keepRunningFlag: true)
        guard buildEngine() else {
            isRunning = false
            return
        }
        currentLevel = 0
        fadeTo(keepLevel, over: 0.4)
    }

    private func teardownEngine(keepRunningFlag: Bool = false) {
        if let o = configObserver {
            NotificationCenter.default.removeObserver(o)
            configObserver = nil
        }
        chimePlayer?.stop()
        engine?.stop()
        if let node = sourceNode { engine?.detach(node) }
        if let player = chimePlayer { engine?.detach(player) }
        sourceNode = nil
        chimePlayer = nil
        engine = nil
        if !keepRunningFlag {
            isRunning = false
            currentLevel = 0
            targetLevel = 0
        }
    }

    private func fadeTo(_ level: Double, over seconds: Double) {
        targetLevel = min(max(level, 0), 1)
        let frames = max(1.0, seconds * sampleRate)
        fadeStep = 1.0 / frames
    }

    // MARK: - 离线导出(调试/试听用)

    /// 把真正在播的那套声音离线渲染成一个音频文件。
    /// 用的是和实时播放同一份合成代码,所以听到的就是黑幕里会响的东西。
    /// 时间轴:全程背景和弦,第 4 秒插一次动作切换提示音,第 10 秒插完成双音。
    func exportSample(to path: String, seconds: Double = 14, volume: Double = 0.28,
                      breathing: Bool = true,
                      breathInSeconds: Double = 4, breathOutSeconds: Double = 6) -> Bool {
        let sr = 44100.0
        let total = Int(sr * seconds)
        guard total > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(total)),
              let data = buffer.floatChannelData?[0] else { return false }
        buffer.frameLength = AVAudioFrameCount(total)

        var synth = ChordSynth(voices: voices, sampleRate: sr)
        let fadeIn = 2.0
        let fadeOut = 0.8

        for i in 0..<total {
            let t = Double(i) / sr
            // 首尾的渐变,和实时播放一致
            var level = 1.0
            if t < fadeIn { level = t / fadeIn }
            if t > seconds - fadeOut { level = max(0, (seconds - t) / fadeOut) }
            let raw = synth.nextSample(breathing: breathing,
                                       breathIn: breathInSeconds,
                                       breathOut: breathOutSeconds)
            data[i] = Float(raw * volume * level)
        }

        // 把两处提示音混进去
        mixChime(into: data, total: total, sampleRate: sr,
                 at: 4.0, frequencies: [(chimeStep, 0.0)], volume: 0.45)
        mixChime(into: data, total: total, sampleRate: sr,
                 at: 10.0, frequencies: [(chimeDoneLow, 0.0), (chimeDoneHigh, 0.15)], volume: 0.45)

        do {
            let url = URL(fileURLWithPath: path)
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return true
        } catch {
            Log.error("导出音频失败:\(error.localizedDescription)")
            return false
        }
    }

    private func mixChime(into data: UnsafeMutablePointer<Float>, total: Int, sampleRate: Double,
                          at start: Double, frequencies: [(Double, Double)], volume: Double) {
        let decay = 1.25
        for (freq, delay) in frequencies {
            let offset = Int((start + delay) * sampleRate)
            guard offset < total else { continue }
            let length = Int(decay * 2 * sampleRate)
            for k in 0..<length {
                let idx = offset + k
                guard idx < total else { break }
                let t = Double(k) / sampleRate
                let attack = min(1.0, t / 0.005)
                let env = attack * exp(-t * (5.0 / decay))
                let base = sin(2 * .pi * freq * t)
                let h2 = 0.22 * sin(2 * .pi * freq * 2 * t) * exp(-t * 7)
                let h3 = 0.08 * sin(2 * .pi * freq * 3 * t) * exp(-t * 11)
                data[idx] += Float((base + h2 + h3) * env * 0.20 * volume)
            }
        }
    }

    // MARK: - 钟声

    /// 提示音走独立的播放节点,播的是事先算好的一段波形。
    /// 这样就不用在实时线程里维护事件队列,省掉一堆无锁编程的麻烦。
    private func playChime(frequencies: [(Double, Double)], volume: Double) {
        guard let player = chimePlayer, isRunning else { return }
        let decay = 1.25
        let tail = (frequencies.map { $0.1 }.max() ?? 0) + decay
        let frames = AVAudioFrameCount(sampleRate * tail)
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames

        let vol = min(max(volume, 0), 1)
        let channels = Int(format.channelCount)
        for ch in 0..<channels {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            for i in 0..<Int(frames) { data[i] = 0 }
            for (freq, delay) in frequencies {
                let offset = Int(delay * sampleRate)
                for i in offset..<Int(frames) {
                    let t = Double(i - offset) / sampleRate
                    // 起音 5 毫秒推上去,之后指数衰减,像木琴或钟
                    let attack = min(1.0, t / 0.005)
                    let env = attack * exp(-t * (5.0 / decay))
                    let base = sin(2 * .pi * freq * t)
                    let h2 = 0.22 * sin(2 * .pi * freq * 2 * t) * exp(-t * 7)
                    let h3 = 0.08 * sin(2 * .pi * freq * 3 * t) * exp(-t * 11)
                    data[i] += Float((base + h2 + h3) * env * 0.20 * vol)
                }
            }
        }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}

// MARK: - 候选音色(试听用)

/// 背景音的风格。第一版用的是低音区的和弦长音,
/// 但笔记本扬声器基本发不出 130Hz,那个根音只会变成一团嗡嗡声,
/// 所以另外备了几种放在高一点的音区、或者干脆不用乐音的方案。
enum AmbientStyle: String, CaseIterable {
    case padLow   = "pad-low"    // 初版:低音区和弦长音
    case padWarm  = "pad-warm"   // 改良:音区抬高 + 削掉高频毛刺
    case bowl     = "bowl"       // 颂钵:音符缓慢飘落,之间留白
    case rain     = "rain"       // 雨声:柔和噪音,没有旋律
}

extension AmbientAudio {

    /// 把某种风格离线渲染成音频文件,纯粹为了试听对比
    func exportStyle(_ style: AmbientStyle, to path: String,
                     seconds: Double, volume: Double,
                     breathIn: Double = 4, breathOut: Double = 6) -> Bool {
        let sr = 44100.0
        let total = Int(sr * seconds)
        guard total > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(total)),
              let data = buffer.floatChannelData?[0] else { return false }
        buffer.frameLength = AVAudioFrameCount(total)

        // 用的是实时播放同一批合成器,所以试听到的就是黑幕里会响的东西
        var chord = ChordSynth(voices: style == .padWarm ? warmVoices : voices, sampleRate: sr)
        var bowlSynth = BowlSynth(sampleRate: sr)
        var rainSynth = RainSynth(sampleRate: sr)

        for i in 0..<total {
            let t = Double(i) / sr
            var raw: Double
            switch style {
            case .bowl:
                // 颂钵的音符本身就卡在呼吸节拍上,不再另外叠音量起伏
                raw = bowlSynth.nextSample(breathing: true, breathIn: breathIn, breathOut: breathOut)
            case .rain:
                raw = rainSynth.nextSample()
                raw *= 0.58 + 0.42 * AmbientAudio.breathCurve(elapsed: t,
                                                              inhale: breathIn, exhale: breathOut)
            case .padLow, .padWarm:
                raw = chord.nextSample(breathing: true, breathIn: breathIn, breathOut: breathOut)
            }
            var level = 1.0
            if t < 2.0 { level = t / 2.0 }
            if t > seconds - 0.8 { level = max(0, (seconds - t) / 0.8) }
            data[i] = Float(raw * volume * level)
        }
        // 第 6 秒插一次动作切换提示音,听听和背景搭不搭
        mixChimeForPreview(data, total, sr, at: 6.0)

        do {
            let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path),
                                       settings: format.settings)
            try file.write(from: buffer)
            return true
        } catch {
            Log.error("导出失败:\(error.localizedDescription)")
            return false
        }
    }

    /// 抬高一个八度的温暖版:避开笔记本扬声器发不出的低频区
    var warmVoices: [Voice] {
        [
            Voice(frequency: 261.63, gain: 0.42, detune: 0.13),  // C4
            Voice(frequency: 392.00, gain: 0.30, detune: 0.17),  // G4
            Voice(frequency: 523.25, gain: 0.18, detune: 0.21),  // C5
            Voice(frequency: 196.00, gain: 0.16, detune: 0.11),  // G3 垫一点厚度
        ]
    }

    /// 颂钵:每隔几秒轻轻敲一个音,让它自己衰减完,音符之间留白。
    /// 用五声音阶——这几个音随便怎么组合都不会撞出难听的和声。
    /// 雨声:噪音过一层低通,再让强弱缓慢变化,像窗外的雨
    private func mixChimeForPreview(_ data: UnsafeMutablePointer<Float>, _ total: Int,
                                    _ sr: Double, at start: Double) {
        let freq = 783.99, decay = 1.25
        let offset = Int(start * sr)
        for k in 0..<Int(decay * 2 * sr) {
            let idx = offset + k
            if idx >= total { break }
            let t = Double(k) / sr
            let env = min(1.0, t / 0.005) * exp(-t * (5.0 / decay))
            let v = sin(2 * .pi * freq * t)
                  + 0.22 * sin(2 * .pi * freq * 2 * t) * exp(-t * 7)
            data[idx] += Float(v * env * 0.20 * 0.45)
        }
    }
}
