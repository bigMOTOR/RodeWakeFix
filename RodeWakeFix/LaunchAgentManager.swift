import Foundation

enum LaunchAgentError: LocalizedError {
    case missingExecutable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Could not find the app executable."
        case let .commandFailed(message):
            return message
        }
    }
}

struct LaunchAgentManager {
    static let label = "com.motor.RodeWakeFix.agent"

    private var userID: uid_t { getuid() }

    var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }

    var installedAppURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("RodeWakeFix.app", isDirectory: true)
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
            && FileManager.default.fileExists(atPath: installedAppURL.path)
    }

    func install() throws {
        let fileManager = FileManager.default
        let currentBundle = Bundle.main.bundleURL.standardizedFileURL
        let destination = installedAppURL.standardizedFileURL

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if currentBundle != destination {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: currentBundle, to: destination)
        }

        let executable = destination
            .appendingPathComponent("Contents/MacOS/RodeWakeFix")
            .path
        guard fileManager.isExecutableFile(atPath: executable) else {
            throw LaunchAgentError.missingExecutable
        }

        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let logDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/RodeWakeFix", isDirectory: true)
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executable, "--background"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": logDirectory.appendingPathComponent("agent.stdout.log").path,
            "StandardErrorPath": logDirectory.appendingPathComponent("agent.stderr.log").path
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        _ = try? launchctl(["bootout", "gui/\(userID)/\(Self.label)"])
        try launchctl(["bootstrap", "gui/\(userID)", plistURL.path])
    }

    func uninstall() throws {
        _ = try? launchctl(["bootout", "gui/\(userID)/\(Self.label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    @discardableResult
    private func launchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw LaunchAgentError.commandFailed(
                message.isEmpty ? "launchctl failed (\(process.terminationStatus))." : message
            )
        }
        return message
    }
}
