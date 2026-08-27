import CoreGraphics
import Foundation

/// 查系统「多久没碰键鼠了」。用来判断人是不是已经离开电脑——
/// 离开本身就等于在休息,这时候不该等你一回座位就黑屏。
enum Idle {
    private static let watched: [CGEventType] = [
        .keyDown, .flagsChanged,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .mouseMoved, .scrollWheel,
    ]

    static func seconds() -> Double {
        let values = watched.map {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0)
        }
        return values.min() ?? 0
    }
}
