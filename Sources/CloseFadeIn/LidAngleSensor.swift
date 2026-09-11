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
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        NSLog("CFI init: RequestAccess granted=\(granted)")

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
        NSLog("CFI probe: result=0x%08x len=%d status=%@", result, length, "\(status)")
        if result == kIOReturnSuccess { status = .ok; return true }
        if result == kIOReturnNotPermitted { status = .permissionDenied }
        else { status = .notFound }
        return false
    }

    func retryPermission() -> Bool {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        NSLog("CFI retry: RequestAccess granted=\(granted)")
        return probe()
    }

    private var lastLogged: Double = -999
    private var readCallCount = 0
    private var readFailCount = 0
    func readAngle() -> Double? {
        readCallCount += 1
        guard let device else {
            if readCallCount == 1 { NSLog("CFI readAngle: no device") }
            return nil
        }
        guard status == .ok else {
            if readCallCount % 300 == 1 { NSLog("CFI readAngle: status=\(status)") }
            return nil
        }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else {
            readFailCount += 1
            if readFailCount <= 3 || readFailCount % 300 == 0 {
                NSLog("CFI readAngle FAIL #%d: result=0x%08x len=%d", readFailCount, result, length)
            }
            if result == kIOReturnNotPermitted { status = .permissionDenied }
            return nil
        }
        let angle = Double(UInt16(report[1]) | (UInt16(report[2]) << 8))
        if abs(angle - lastLogged) >= 1 {
            NSLog("CFI angle: %.0f (raw bytes %02x %02x %02x)", angle, report[0], report[1], report[2])
            lastLogged = angle
        }
        return angle
    }
}
