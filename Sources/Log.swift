import Foundation

/// 日志直接打到标准输出,由 launchd 的 StandardOutPath 落到
/// ~/.local/state/shoulder-break/logs/service.log。手动前台跑时就直接看终端。
enum Log {
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    static func info(_ msg: String)  { emit("INFO ", msg) }
    static func warn(_ msg: String)  { emit("WARN ", msg) }
    static func error(_ msg: String) { emit("ERROR", msg) }

    private static func emit(_ level: String, _ msg: String) {
        print("[\(fmt.string(from: Date()))] \(level) \(msg)")
        fflush(stdout)
    }
}
