import Foundation
import IOKit

struct USBDeviceStatus {
    let isPresent: Bool
    let productName: String?
    let serialNumber: String?
}

struct USBDeviceService {
    func targetStatus() -> USBDeviceStatus {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOUSBHostDevice"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return USBDeviceStatus(isPresent: false, productName: nil, serialNumber: nil)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let serial = property("USB Serial Number", from: service)
            let product = property("USB Product Name", from: service)
                ?? property("Product Name", from: service)

            if serial == TargetMicrophone.serialNumber || product.map(TargetMicrophone.matches(name:)) == true {
                return USBDeviceStatus(
                    isPresent: true,
                    productName: product,
                    serialNumber: serial
                )
            }
        }

        return USBDeviceStatus(isPresent: false, productName: nil, serialNumber: nil)
    }

    private func property(_ key: String, from service: io_registry_entry_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }
}

// Watch USB arrivals and removals without repeatedly scanning the USB registry.
final class USBDeviceMonitor {
    private var notificationPort: IONotificationPortRef?
    private var arrivalIterator: io_iterator_t = 0
    private var removalIterator: io_iterator_t = 0
    private var onChange: (() -> Void)?

    func start(onChange: @escaping () -> Void) {
        guard notificationPort == nil,
              let port = IONotificationPortCreate(kIOMainPortDefault) else { return }

        self.onChange = onChange
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching("IOUSBHostDevice"),
            usbDeviceNotificationCallback,
            context,
            &arrivalIterator
        ) == KERN_SUCCESS else {
            stop()
            return
        }
        drain(arrivalIterator)

        guard IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            usbDeviceNotificationCallback,
            context,
            &removalIterator
        ) == KERN_SUCCESS else {
            stop()
            return
        }
        drain(removalIterator)
    }

    func stop() {
        if arrivalIterator != 0 {
            IOObjectRelease(arrivalIterator)
            arrivalIterator = 0
        }
        if removalIterator != 0 {
            IOObjectRelease(removalIterator)
            removalIterator = 0
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        onChange = nil
    }

    fileprivate func deviceDidChange(_ iterator: io_iterator_t) {
        drain(iterator)
        onChange?()
    }

    private func drain(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}

private func usbDeviceNotificationCallback(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let context else { return }
    Unmanaged<USBDeviceMonitor>.fromOpaque(context).takeUnretainedValue().deviceDidChange(iterator)
}
