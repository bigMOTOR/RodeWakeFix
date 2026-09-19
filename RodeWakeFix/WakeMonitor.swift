import AppKit
import Foundation

final class WakeMonitor {
    private let onWillSleep: () -> Void
    private let onDidWake: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(onWillSleep: @escaping () -> Void, onDidWake: @escaping () -> Void) {
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onWillSleep()
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onDidWake()
            }
        )
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    deinit {
        stop()
    }
}
