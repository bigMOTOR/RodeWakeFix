import AppKit
import CoreAudio
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var headline = "Checking…"
    @Published var detail = "Reading USB and CoreAudio state."
    @Published var usbPresent = false
    @Published var coreAudioPresent = false
    @Published var targetIsDefault = false
    @Published var defaultInputName = "Unknown"
    @Published var defaultInputID: AudioDeviceID?
    @Published var inputDevices: [AudioInputDevice] = []
    @Published var autoStartInstalled = false
    @Published var lastWakeSummary = "No wake check yet"
    @Published var recentEvents: [String] = []
    @Published var isBusy = false
    @Published var preferTarget = false

    private let audio = AudioDeviceService()
    private let audioMonitor = AudioInputMonitor()
    private let usb = USBDeviceService()
    private let usbMonitor = USBDeviceMonitor()
    private let logger = LogStore.shared
    private let launchAgent = LaunchAgentManager()
    private let defaults = UserDefaults.standard

    private let armedKey = "TargetWasDefaultBeforeSleep"
    private let lastWakeSummaryKey = "LastWakeSummary"
    private let preferTargetKey = "PreferTargetWhileAvailable"
    private var audioChangeTask: Task<Void, Never>?
    private var lastUSBPresence: Bool?
    private var lastCoreAudioPresence: Bool?

    func start() {
        autoStartInstalled = launchAgent.isInstalled
        lastWakeSummary = defaults.string(forKey: lastWakeSummaryKey) ?? "No wake check yet"
        preferTarget = defaults.bool(forKey: preferTargetKey)
        logger.append("App started\(ProcessInfo.processInfo.arguments.contains("--background") ? " in background" : "")")
        refreshStatus(logEvent: false)
        audioMonitor.start { [weak self] in
            Task { @MainActor in
                self?.audioHardwareDidChange()
            }
        }
        usbMonitor.start { [weak self] in
            Task { @MainActor in
                self?.audioHardwareDidChange()
            }
        }
        enforceTargetPreference(reason: "app launch")
    }

    func stop() {
        audioChangeTask?.cancel()
        usbMonitor.stop()
        audioMonitor.stop()
    }

    func refreshStatus(logEvent: Bool = true) {
        isBusy = true
        defer {
            isBusy = false
            recentEvents = logger.recentLines()
        }

        let usbStatus = usb.targetStatus()
        usbPresent = usbStatus.isPresent

        if let previous = lastUSBPresence, previous != usbPresent {
            logger.append(usbPresent ? "Physical RØDE returned to USB" : "Physical RØDE disappeared from USB")
        } else if lastUSBPresence == nil {
            logger.append(usbPresent ? "Initial USB state — physical RØDE present" : "Initial USB state — physical RØDE not detected")
        }
        lastUSBPresence = usbPresent

        do {
            let snapshot = try audio.snapshot()
            inputDevices = snapshot.inputs
            defaultInputID = snapshot.defaultInputID
            coreAudioPresent = snapshot.target != nil
            targetIsDefault = snapshot.targetIsDefault
            defaultInputName = snapshot.defaultInput?.name ?? "None"

            if let previous = lastCoreAudioPresence, previous != coreAudioPresent {
                logger.append(coreAudioPresent ? "RØDE input returned to CoreAudio" : "RØDE input disappeared from CoreAudio")
            } else if lastCoreAudioPresence == nil {
                logger.append(coreAudioPresent ? "Initial CoreAudio state — RØDE input available" : "Initial CoreAudio state — RØDE input not found")
            }
            lastCoreAudioPresence = coreAudioPresent

            if targetIsDefault {
                headline = "RØDE is ready"
                detail = "It is connected and selected as the system input."
            } else if coreAudioPresent {
                headline = "RØDE connected — \(defaultInputName) is active"
                detail = preferTarget
                    ? "RØDE preference is enabled; waiting for the audio change to settle."
                    : "RØDE is available but is not the current system input."
            } else if usbPresent {
                headline = "USB sees RØDE, CoreAudio does not"
                detail = "The microphone is on USB but unavailable as an audio input."
            } else {
                headline = "Physical RØDE not detected on USB"
                detail = "The power light does not confirm a USB data connection. Other microphones are left alone."
            }
        } catch {
            inputDevices = []
            defaultInputID = nil
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

    func selectInputDevice(_ deviceID: AudioDeviceID) {
        guard let device = inputDevices.first(where: { $0.id == deviceID }) else {
            refreshStatus(logEvent: false)
            return
        }
        do {
            if !TargetMicrophone.matches(name: device.name), preferTarget {
                setPreferTarget(false, logReason: "manual selection of \(device.name)")
            }
            try audio.setDefaultInput(deviceID)
            logger.append("Input selected from menu bar: \(device.name)")
        } catch {
            logger.append("Could not select \(device.name): \(error.localizedDescription)")
            headline = "Could not select microphone"
            detail = error.localizedDescription
        }
        refreshStatus(logEvent: false)
    }

    func setPreferTarget(_ enabled: Bool) {
        setPreferTarget(enabled, logReason: "menu setting")
        if enabled {
            enforceTargetPreference(reason: "preference enabled")
        } else {
            refreshStatus(logEvent: false)
        }
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
            recordWakeOutcome("Skipped — another microphone was selected", log: "Wake check — RØDE was not default before sleep; no action")
            refreshStatus(logEvent: false)
            return
        }

        let usbStatus = usb.targetStatus()
        do {
            let snapshot = try audio.snapshot()
            if snapshot.target != nil {
                if snapshot.targetIsDefault {
                    recordWakeOutcome("OK — RØDE returned normally", log: "Wake check — RØDE returned normally; no repair needed")
                } else {
                    try audio.setTargetAsDefault()
                    recordWakeOutcome("Fixed — RØDE restored", log: "Wake check — restored RØDE as system default input")
                }
            } else if usbStatus.isPresent {
                recordWakeOutcome("Needs repair — missing from CoreAudio", log: "Wake check — failure captured: USB present, CoreAudio input missing")
            } else {
                recordWakeOutcome("USB missing — automatic repair unavailable", log: "Wake check — physical RØDE not detected on USB; cannot restore a device macOS cannot see")
            }
        } catch {
            recordWakeOutcome("Check failed", log: "Wake check failed: \(error.localizedDescription)")
        }
        refreshStatus(logEvent: false)
    }

    private func setPreferTarget(_ enabled: Bool, logReason: String) {
        guard preferTarget != enabled else { return }
        preferTarget = enabled
        defaults.set(enabled, forKey: preferTargetKey)
        logger.append("Always prefer RØDE \(enabled ? "enabled" : "disabled") — \(logReason)")
        recentEvents = logger.recentLines()
    }

    private func audioHardwareDidChange() {
        audioChangeTask?.cancel()
        audioChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.refreshStatus(logEvent: false)
            self.enforceTargetPreference(reason: "system input changed")
        }
    }

    private func enforceTargetPreference(reason: String) {
        guard preferTarget else { return }

        do {
            let snapshot = try audio.snapshot()
            guard snapshot.target != nil, !snapshot.targetIsDefault else { return }
            try audio.setTargetAsDefault()
            logger.append("RØDE restored as system input — \(reason)")
            refreshStatus(logEvent: false)
        } catch {
            logger.append("Could not apply RØDE preference — \(error.localizedDescription)")
            recentEvents = logger.recentLines()
        }
    }

    private func recordWakeOutcome(_ summary: String, log message: String) {
        let time = Date.now.formatted(date: .omitted, time: .shortened)
        lastWakeSummary = "\(summary) · \(time)"
        defaults.set(lastWakeSummary, forKey: lastWakeSummaryKey)
        logger.append(message)
    }
}
