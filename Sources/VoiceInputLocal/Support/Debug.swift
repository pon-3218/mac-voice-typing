import Foundation

enum Dbg {
    private static let url = URL(fileURLWithPath: "/tmp/voice-log-local-debug.txt")
    private static let lock = NSLock()

    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["VLL_DEBUG_LOG"] == "1"
        #endif
    }

    static func log(_ message: String) {
        guard isEnabled, let data = "\(Date().timeIntervalSince1970) \(message)\n".data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
