import CoreAudio
import Foundation

enum TargetMicrophone {
    static let displayName = "RØDE NT-USB Mini"
    static let serialNumber = "ACAAF915"

    static func matches(name: String) -> Bool {
        let normalized = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "ø", with: "o")
            .lowercased()
        return normalized.contains("rode") && normalized.contains("nt-usb mini")
    }
}

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

struct AudioSnapshot {
    let inputs: [AudioInputDevice]
    let defaultInputID: AudioDeviceID?

    var target: AudioInputDevice? {
        inputs.first { TargetMicrophone.matches(name: $0.name) }
    }

    var defaultInput: AudioInputDevice? {
        guard let defaultInputID else { return nil }
        return inputs.first { $0.id == defaultInputID }
    }

    var targetIsDefault: Bool {
        guard let target, let defaultInputID else { return false }
        return target.id == defaultInputID
    }
}
