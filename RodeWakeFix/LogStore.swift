import Foundation

final class LogStore {
    static let shared = LogStore()

    let logURL: URL
    private let queue = DispatchQueue(label: "com.motor.RodeWakeFix.log")
    private let formatter: ISO8601DateFormatter

    private init() {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("RodeWakeFix", isDirectory: true)
        logURL = logs.appendingPathComponent("RodeWakeFix.log")

        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func append(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.sync { [logURL] in
            do {
                try FileManager.default.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = Data(line.utf8)
                if FileManager.default.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logURL, options: .atomic)
                }
            } catch {
                NSLog("RodeWakeFix could not write log: %@", error.localizedDescription)
            }
        }
    }

    func recentLines(limit: Int = 12) -> [String] {
        queue.sync {
            guard let contents = try? String(contentsOf: logURL, encoding: .utf8) else {
                return []
            }
            return contents
                .split(separator: "\n")
                .suffix(limit)
                .map(String.init)
                .reversed()
        }
    }
}
