import CoreAudio
import Foundation

enum AudioDeviceError: LocalizedError {
    case coreAudio(OSStatus, String)
    case targetUnavailable

    var errorDescription: String? {
        switch self {
        case let .coreAudio(status, operation):
            return "\(operation) failed (CoreAudio \(status))."
        case .targetUnavailable:
            return "RØDE is not available as a CoreAudio input."
        }
    }
}

struct AudioDeviceService {
    func snapshot() throws -> AudioSnapshot {
        let ids = try audioDeviceIDs()
        let inputs = ids.compactMap { id -> AudioInputDevice? in
            guard inputChannelCount(for: id) > 0 else { return nil }
            let name = stringProperty(
                selector: kAudioObjectPropertyName,
                objectID: id
            ) ?? "Unknown input"
            let uid = stringProperty(
                selector: kAudioDevicePropertyDeviceUID,
                objectID: id
            ) ?? "device-\(id)"
            return AudioInputDevice(id: id, name: name, uid: uid)
        }

        return AudioSnapshot(inputs: inputs, defaultInputID: defaultInputDeviceID())
    }

    func setTargetAsDefault() throws {
        let current = try snapshot()
        guard let target = current.target else {
            throw AudioDeviceError.targetUnavailable
        }

        var targetID = target.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &targetID
        )
        guard status == noErr else {
            throw AudioDeviceError.coreAudio(status, "Selecting RØDE")
        }
    }

    private func audioDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else {
            throw AudioDeviceError.coreAudio(status, "Reading audio device list size")
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        )
        guard status == noErr else {
            throw AudioDeviceError.coreAudio(status, "Reading audio device list")
        }
        return ids
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        )
        return status == noErr && id != 0 ? id : nil
    }

    private func stringProperty(selector: AudioObjectPropertySelector, objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else {
            return 0
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, list) == noErr else {
            return 0
        }

        return UnsafeMutableAudioBufferListPointer(list).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }
}
