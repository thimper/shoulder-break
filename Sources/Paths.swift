import Foundation

/// 所有落盘位置集中在这里,沿用 ~/.config + ~/.local/state 的习惯。
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var configDir: URL { home.appendingPathComponent(".config/shoulder-break") }
    static var configFile: URL { configDir.appendingPathComponent("config.json") }

    static var stateDir: URL { home.appendingPathComponent(".local/state/shoulder-break") }
    static var stateFile: URL { stateDir.appendingPathComponent("state.json") }
    static var historyFile: URL { stateDir.appendingPathComponent("history.jsonl") }

    static var logDir: URL { stateDir.appendingPathComponent("logs") }
    static var logFile: URL { logDir.appendingPathComponent("service.log") }

    static func ensureDirs() {
        let fm = FileManager.default
        for dir in [configDir, stateDir, logDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// 先写临时文件再原子替换,避免断电/崩溃时留下半截 JSON。
    static func atomicWrite(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}
