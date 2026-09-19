import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var headline = "Checking…"
    @Published var detail = "Reading USB and CoreAudio state."
    @Published var usbPresent = false
    @Published var coreAudioPresent = false
    @Published var targetIsDefault = false
    @Published var defaultInputName = "Unknown"
    @Published var autoStartInstalled = false
    @Published var recentEvents: [String] = []
    @Published var isBusy = false

    private let audio = AudioDeviceService()
    private let usb = USBDeviceService()
    private let logger = LogStore.shared
    private let launchAgent = LaunchAgentManager()
    private let defaults = UserDefaults.standard

    private let armedKey = "TargetWasDefaultBeforeSleep"

    func start() {
        autoStartInstalled = launchAgent.isInstalled
        logger.append("App started\(ProcessInfo.processInfo.arguments.contains("--background") ? " in background" : "")")
        refreshStatus(logEvent: false)
    }

    func refreshStatus(logEvent: Bool = true) {
        isBusy = true
        defer {
            isBusy = false
            recentEvents = logger.recentLines()
        }

        let usbStatus = usb.targetStatus()
        usbPresent = usbStatus.isPresent

        do {
            let snapshot = try audio.snapshot()
            coreAudioPresent = snapshot.target != nil
            targetIsDefault = snapshot.targetIsDefault
            defaultInputName = snapshot.defaultInput?.name ?? "None"

            if targetIsDefault {
                headline = "RØDE is ready"
                detail = "It is connected and selected as the system input."
            } else if coreAudioPresent {
                headline = "RØDE is available"
                detail = "Current system input: \(defaultInputName)."
            } else if usbPresent {
                headline = "USB sees RØDE, CoreAudio does not"
                detail = "This is the sleep/wake failure we want to capture."
            } else {
                headline = "RØDE is not connected"
                detail = "Nothing will be changed. Other microphones are left alone."
            }
        } catch {
            coreAudioPresent = false
            targetIsDefault = false
            headline = "Could not read audio state"
            detail = error.localizedDescription
        }

        if logEvent {
            logger.append(
                "Manual check — USB: \(usbPresent), CoreAudio: \(coreAudioPresent), default: \(defaultInputName)"
            )
        }
    }

    func setTargetAsDefault() {
        do {
            try audio.setTargetAsDefault()
            logger.append("RØDE selected as system default input")
        } catch {
            logger.append("Could not select RØDE: \(error.localizedDescription)")
            headline = "Could not select RØDE"
            detail = error.localizedDescription
        }
        refreshStatus(logEvent: false)
    }

    func recordWillSleep() {
        do {
            let snapshot = try audio.snapshot()
            defaults.set(snapshot.targetIsDefault, forKey: armedKey)
            logger.append(
                "Will sleep — RØDE was default: \(snapshot.targetIsDefault), current input: \(snapshot.defaultInput?.name ?? "None")"
            )
        } catch {
            defaults.set(false, forKey: armedKey)
            logger.append("Will sleep — could not read audio state: \(error.localizedDescription)")
        }
        recentEvents = logger.recentLines()
    }

    func scheduleWakeCheck() {
        logger.append("Did wake — waiting 5 seconds before checking")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.performWakeCheck()
        }
    }

    func installBackgroundHelper() {
        isBusy = true
        do {
            try launchAgent.install()
            autoStartInstalled = true
            logger.append("Background helper installed")
            headline = "Background helper installed"
            detail = "RodeWakeFix will start automatically when you sign in."
        } catch {
            logger.append("Background helper installation failed: \(error.localizedDescription)")
            headline = "Installation failed"
            detail = error.localizedDescription
        }
        isBusy = false
        recentEvents = logger.recentLines()
    }

    func removeBackgroundHelper() {
        isBusy = true
        do {
            try launchAgent.uninstall()
            autoStartInstalled = false
            logger.append("Background helper removed from login")
            headline = "Background helper disabled"
            detail = "It will no longer start automatically."
        } catch {
            logger.append("Could not remove background helper: \(error.localizedDescription)")
            headline = "Could not disable background helper"
            detail = error.localizedDescription
        }
        isBusy = false
        recentEvents = logger.recentLines()
    }

    func openLog() {
        logger.append("Log opened from settings")
        NSWorkspace.shared.open(logger.logURL)
    }

    private func performWakeCheck() {
        let wasTargetDefault = defaults.bool(forKey: armedKey)
        guard wasTargetDefault else {
            logger.append("Wake check — RØDE was not default before sleep; no action")
            refreshStatus(logEvent: false)
            return
        }

        let usbStatus = usb.targetStatus()
        do {
            let snapshot = try audio.snapshot()
            if snapshot.target != nil {
                if snapshot.targetIsDefault {
                    logger.append("Wake check — RØDE returned normally; no repair needed")
                } else {
                    try audio.setTargetAsDefault()
                    logger.append("Wake check — restored RØDE as system default input")
                }
            } else if usbStatus.isPresent {
                logger.append("Wake check — failure captured: USB present, CoreAudio input missing")
            } else {
                logger.append("Wake check — RØDE unplugged; no action")
            }
        } catch {
            logger.append("Wake check failed: \(error.localizedDescription)")
        }
        refreshStatus(logEvent: false)
    }
}
