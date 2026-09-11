import Foundation
import IOKit.hid

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDPrimaryUsagePageKey: 0x20,
    kIOHIDPrimaryUsageKey: 0x8A,
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else {
    print("No lid angle sensor found")
    exit(1)
}

let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
print("Device open result: \(openResult == kIOReturnSuccess ? "success" : String(format: "0x%08x", openResult))")

for _ in 0..<20 {
    var report = [UInt8](repeating: 0, count: 8)
    var reportLength = report.count
    let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &reportLength)
    if result == kIOReturnSuccess {
        let angle = UInt16(report[1]) | (UInt16(report[2]) << 8)
        let hex = report.prefix(reportLength).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("raw: [\(hex)] len=\(reportLength) angle=\(angle)°")
    } else {
        print(String(format: "GetReport failed: 0x%08x", result))
    }
    Thread.sleep(forTimeInterval: 0.25)
}
