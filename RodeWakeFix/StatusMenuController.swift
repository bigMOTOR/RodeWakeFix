import AppKit
import Combine
import CoreAudio

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let state: AppState
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []

    init(state: AppState, openSettings: @escaping () -> Void) {
        self.state = state
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly

        Publishers.CombineLatest3(
            state.$usbPresent,
            state.$coreAudioPresent,
            state.$targetIsDefault
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            self?.updateIcon()
        }
        .store(in: &cancellables)

        updateIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        state.refreshStatus(logEvent: false)
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = NSMenuItem(title: state.headline, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let wake = NSMenuItem(title: "Last wake: \(state.lastWakeSummary)", action: nil, keyEquivalent: "")
        wake.isEnabled = false
        menu.addItem(wake)
        menu.addItem(.separator())

        let heading = NSMenuItem(title: "Input microphone", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        if state.inputDevices.isEmpty {
            let empty = NSMenuItem(title: "No inputs available", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for device in state.inputDevices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(selectInput(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: device.id)
                item.state = device.id == state.defaultInputID ? .on : .off
                if TargetMicrophone.matches(name: device.name) {
                    item.image = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: nil)
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let check = NSMenuItem(title: "Check now", action: #selector(checkNow), keyEquivalent: "r")
        check.keyEquivalentModifierMask = [.command]
        check.target = self
        menu.addItem(check)

        let loginStatus = NSMenuItem(
            title: state.autoStartInstalled ? "✓ Starts automatically at login" : "Does not start automatically",
            action: nil,
            keyEquivalent: ""
        )
        loginStatus.isEnabled = false
        menu.addItem(loginStatus)

        let settings = NSMenuItem(title: "Open RØDE Wake Fix…", action: #selector(showSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit until next login", action: #selector(quitApp), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
    }

    private func updateIcon() {
        let symbol: String
        let tooltip: String

        if state.usbPresent && !state.coreAudioPresent {
            symbol = "mic.badge.xmark"
            tooltip = "RØDE needs attention"
        } else if state.targetIsDefault {
            symbol = "mic.fill"
            tooltip = "RØDE is the system input"
        } else {
            symbol = "mic"
            tooltip = "Choose an input microphone"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = tooltip
    }

    @objc private func selectInput(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        state.selectInputDevice(AudioDeviceID(number.uint32Value))
        updateIcon()
    }

    @objc private func checkNow() {
        state.refreshStatus()
        updateIcon()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
