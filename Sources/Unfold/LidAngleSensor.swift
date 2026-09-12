import Foundation
import IOKit.hid

enum LidSensorStatus {
    case ok
    case permissionDenied
    case notFound
}

final class LidAngleSensor {
    private var device: IOHIDDevice?
    private var manager: IOHIDManager?
    private(set) var status: LidSensorStatus = .notFound

    init() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey: 0x20,
            kIOHIDPrimaryUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let candidate = devices.first,
              IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        else {
            status = .notFound
            return
        }
        device = candidate
        _ = probe()
    }

    var isAvailable: Bool { status == .ok }

    @discardableResult
    private func probe() -> Bool {
        guard let device else { status = .notFound; return false }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        if result == kIOReturnSuccess { status = .ok; return true }
        if result == kIOReturnNotPermitted { status = .permissionDenied }
        else { status = .notFound }
        return false
    }

    func retryPermission() -> Bool {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        return probe()
    }

    func readAngle() -> Double? {
        guard let device, status == .ok else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else {
            if result == kIOReturnNotPermitted { status = .permissionDenied }
            return nil
        }
        return Double(UInt16(report[1]) | (UInt16(report[2]) << 8))
    }
}
