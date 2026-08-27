import Foundation

/// 命令行子命令和常驻进程之间的通信。
/// 用系统自带的同用户进程间广播,不用自己开端口或者 socket 文件。
enum IPC {
    static let channel = Notification.Name("com.shoulderbreak.agent.command")

    static func send(_ command: String) {
        DistributedNotificationCenter.default().postNotificationName(
            channel, object: command, userInfo: nil, deliverImmediately: true)
    }

    static func listen(_ handler: @escaping (String) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: channel, object: nil, queue: .main
        ) { note in
            guard let cmd = note.object as? String else { return }
            handler(cmd)
        }
    }
}
