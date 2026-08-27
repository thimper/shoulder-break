import Foundation

enum HistoryEvent: String, Codable {
    case completed       // 老老实实做完了
    case snoozed         // 用了一次延迟
    case escaped         // 长按 Esc 逃跑
    case skippedIdle     = "skipped_idle"    // 人不在电脑前,自动顺延
    case skippedPaused   = "skipped_paused"  // 手动暂停期间跳过
}

struct HistoryEntry: Codable {
    var ts: Double
    var event: HistoryEvent
    var snoozeUsed: Int
}

enum History {
    static func append(_ event: HistoryEvent, snoozeUsed: Int = 0) {
        let entry = HistoryEntry(ts: Date().timeIntervalSince1970, event: event, snoozeUsed: snoozeUsed)
        guard let data = try? JSONEncoder().encode(entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        let url = Paths.historyFile
        if let fh = try? FileHandle(forWritingTo: url) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    static func all() -> [HistoryEntry] {
        guard let text = try? String(contentsOf: Paths.historyFile, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            try? dec.decode(HistoryEntry.self, from: Data(line.utf8))
        }
    }

    struct Summary {
        var completed = 0
        var snoozed = 0
        var escaped = 0
        var skipped = 0
    }

    static func summary(since: Date) -> Summary {
        let cutoff = since.timeIntervalSince1970
        var s = Summary()
        for e in all() where e.ts >= cutoff {
            switch e.event {
            case .completed: s.completed += 1
            case .snoozed: s.snoozed += 1
            case .escaped: s.escaped += 1
            case .skippedIdle, .skippedPaused: s.skipped += 1
            }
        }
        return s
    }

    static func today() -> Summary {
        summary(since: Calendar.current.startOfDay(for: Date()))
    }

    static func thisWeek() -> Summary {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? cal.startOfDay(for: Date())
        return summary(since: start)
    }

    /// 只留最近 120 天,免得 jsonl 无限长大。启动时跑一次。
    static func prune(days: Int = 120) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let kept = all().filter { $0.ts >= cutoff }
        guard kept.count != all().count else { return }
        let enc = JSONEncoder()
        let lines = kept.compactMap { e -> String? in
            guard let d = try? enc.encode(e) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        let text = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? Paths.atomicWrite(Data(text.utf8), to: Paths.historyFile)
    }
}
