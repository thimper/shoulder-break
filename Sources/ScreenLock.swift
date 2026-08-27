import CoreGraphics
import Foundation

/// 判断屏幕是不是锁着的(含锁屏、屏保、切换用户)。
/// 锁屏就说明人不在座位上,这时候盖黑幕毫无意义——
/// 而且锁屏期间系统会开启安全输入模式,我们的窗口连前台都拿不到,
/// 硬弹只会留下一堆「做过了」的假记录。
enum ScreenLock {
    static var isLocked: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Bool { return locked }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Int { return locked != 0 }
        return false
    }

    /// 当前会话是不是在前台(快速用户切换后,后台会话不该弹东西)
    static var isOnConsole: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        if let on = dict["kCGSSessionOnConsoleKey"] as? Bool { return on }
        if let on = dict["kCGSSessionOnConsoleKey"] as? Int { return on != 0 }
        return true
    }
}
