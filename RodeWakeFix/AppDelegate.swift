import AppKit
import SwiftUI

@main
enum RodeWakeFixMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = AppState()
    private var windowController: NSWindowController?
    private var wakeMonitor: WakeMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.start()

        wakeMonitor = WakeMonitor(
            onWillSleep: { [weak self] in self?.state.recordWillSleep() },
            onDidWake: { [weak self] in self?.state.scheduleWakeCheck() }
        )
        wakeMonitor?.start()

        if !ProcessInfo.processInfo.arguments.contains("--background") {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeMonitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }

    private func showSettings() {
        if let windowController {
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsView(state: state)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "RØDE Wake Fix"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 590))
        window.minSize = NSSize(width: 620, height: 540)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
