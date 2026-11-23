import Foundation
import IOKit.hid

/// A single battery reading.
struct BatteryReading {
    var percent: Int
    var charging: Bool
    var full: Bool
    var deviceName: String
}

/// Talks to the mouse (directly or through a Lightspeed receiver) over Logitech's HID++ 2.0 protocol.
/// Sends read-only queries, so it never changes mouse settings and can run alongside G Hub.
final class HIDPP {
    private static let logitechVendorID = 0x046D
    private static let vendorUsagePage = 0xFF00
    private static let softwareID: UInt8 = 0x0B
    private static let longReportID: UInt8 = 0x11
    private static let shortReportID: UInt8 = 0x10
    private static let longReportLength = 20

    // HID++ 2.0 feature IDs
    private static let featureDeviceName: UInt16 = 0x0005
    private static let featureBatteryStatus: UInt16 = 0x1000
    private static let featureUnifiedBattery: UInt16 = 0x1004

    private struct Target {
        let device: IOHIDDevice
        let deviceIndex: UInt8
        let batteryFeatureIndex: UInt8
        let unified: Bool
    }

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let lock = NSLock()
    private var devices: [IOHIDDevice] = []
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var matcher: (([UInt8]) -> Bool)?
    private var response: [UInt8]?
    private let responseArrived = DispatchSemaphore(value: 0)
    private var target: Target?
    private var cachedName: String?

    var verbose = false
    /// Called on the HID thread when the mouse reports a battery change by itself.
    var onBatteryEvent: (() -> Void)?

    func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: HIDPP.logitechVendorID,
            kIOHIDDeviceUsagePageKey: HIDPP.vendorUsagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<HIDPP>.fromOpaque(context!).takeUnretainedValue().deviceAdded(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<HIDPP>.fromOpaque(context!).takeUnretainedValue().deviceRemoved(device)
        }, context)

        let thread = Thread { [manager] in
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopRun()
        }
        thread.name = "hidpp"
        thread.start()
    }

    var hasDevice: Bool {
        lock.lock(); defer { lock.unlock() }
        return !devices.isEmpty
    }

    // MARK: - Device hotplug

    private func deviceAdded(_ device: IOHIDDevice) {
        let size = max(64, (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { context, _, _, _, reportID, report, length in
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            if bytes.first != UInt8(truncatingIfNeeded: reportID) {
                bytes.insert(UInt8(truncatingIfNeeded: reportID), at: 0)
            }
            Unmanaged<HIDPP>.fromOpaque(context!).takeUnretainedValue().received(bytes)
        }, context)
        lock.lock()
        devices.append(device)
        buffers.append(buffer)
        lock.unlock()
        log("Found device: \(IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) ?? "?" as CFString)")
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        lock.lock()
        devices.removeAll { $0 === device }
        if target?.device === device { target = nil }
        lock.unlock()
    }

    // MARK: - Transport

    private func received(_ bytes: [UInt8]) {
        log("<- " + hex(bytes))
        lock.lock()
        if let matcher, matcher(bytes) {
            response = bytes
            self.matcher = nil
            lock.unlock()
            responseArrived.signal()
            return
        }
        let current = target
        lock.unlock()

        // Unsolicited battery events carry software ID 0.
        if let current, bytes.count >= 4,
           bytes[0] == HIDPP.longReportID,
           bytes[1] == current.deviceIndex,
           bytes[2] == current.batteryFeatureIndex,
           bytes[3] & 0x0F == 0 {
            onBatteryEvent?()
        }
    }

    /// Sends one request and waits for the reply. Returns the reply parameters, or nil on error or timeout.
    private func request(_ device: IOHIDDevice, index: UInt8, feature: UInt8, function: UInt8,
                         params: [UInt8] = []) -> [UInt8]? {
        let functionByte = (function << 4) | HIDPP.softwareID
        var message = [HIDPP.longReportID, index, feature, functionByte] + params
        message += [UInt8](repeating: 0, count: HIDPP.longReportLength - message.count)

        lock.lock()
        response = nil
        matcher = { r in
            guard r.count >= 5, r[1] == index else { return false }
            if r[0] == HIDPP.longReportID, r[2] == feature, r[3] == functionByte { return true }
            // HID++ 2.0 error
            if r[0] == HIDPP.longReportID, r[2] == 0xFF, r[3] == feature, r[4] == functionByte { return true }
            // HID++ 1.0 error: the receiver answers for a mouse that is off or asleep
            if r[0] == HIDPP.shortReportID, r[2] == 0x8F, r[3] == feature, r[4] == functionByte { return true }
            return false
        }
        lock.unlock()

        log("-> " + hex(message))
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(HIDPP.longReportID),
                                          message, message.count)
        var reply: [UInt8]?
        if result == kIOReturnSuccess, responseArrived.wait(timeout: .now() + 0.7) == .success {
            lock.lock(); reply = response; lock.unlock()
        } else if result != kIOReturnSuccess {
            log("Send failed: \(String(format: "0x%08x", result))")
        }
        lock.lock(); matcher = nil; response = nil; lock.unlock()

        guard let reply, reply[0] == HIDPP.longReportID, reply[2] == feature else { return nil }
        return Array(reply[4...])
    }

    /// Asks the device for the index it assigned to a feature. Index 0 means unsupported.
    private func featureIndex(_ device: IOHIDDevice, index: UInt8, feature: UInt16) -> UInt8? {
        guard let r = request(device, index: index, feature: 0x00, function: 0,
                              params: [UInt8(feature >> 8), UInt8(feature & 0xFF)]),
              r[0] != 0 else { return nil }
        return r[0]
    }

    // MARK: - Battery

    /// Reads the battery once. Blocks while waiting for replies, so call it off the main thread.
    func readBattery() -> BatteryReading? {
        lock.lock()
        let known = target
        let all = devices
        lock.unlock()

        if let known, let reading = read(known) { return reading }

        // A mouse paired to a receiver is usually in slot 1; a wired mouse answers on 0xFF.
        let indexes: [UInt8] = [1, 2, 3, 4, 5, 6, 0xFF]
        for device in all {
            for index in indexes {
                var found: Target?
                if let f = featureIndex(device, index: index, feature: HIDPP.featureUnifiedBattery) {
                    found = Target(device: device, deviceIndex: index, batteryFeatureIndex: f, unified: true)
                } else if let f = featureIndex(device, index: index, feature: HIDPP.featureBatteryStatus) {
                    found = Target(device: device, deviceIndex: index, batteryFeatureIndex: f, unified: false)
                }
                guard let found, let reading = read(found) else { continue }
                lock.lock(); target = found; lock.unlock()
                return reading
            }
        }
        return nil
    }

    private func read(_ t: Target) -> BatteryReading? {
        // The status query is function 1 on Unified Battery and function 0 on the older Battery Status.
        guard let r = request(t.device, index: t.deviceIndex, feature: t.batteryFeatureIndex,
                              function: t.unified ? 1 : 0), r.count >= 3 else { return nil }
        let status = r[2]
        let charging: Bool
        let full: Bool
        if t.unified {
            charging = status == 1 || status == 2
            full = status == 3
        } else {
            charging = status == 1 || status == 2 || status == 4
            full = status == 3
        }
        return BatteryReading(percent: Int(r[0]), charging: charging, full: full, deviceName: name(t))
    }

    private func name(_ t: Target) -> String {
        if let cachedName { return cachedName }
        let fallback = "Logitech Mouse"
        guard let f = featureIndex(t.device, index: t.deviceIndex, feature: HIDPP.featureDeviceName),
              let count = request(t.device, index: t.deviceIndex, feature: f, function: 0)?.first
        else { return fallback }
        var chars: [UInt8] = []
        while chars.count < Int(count) {
            guard let chunk = request(t.device, index: t.deviceIndex, feature: f, function: 1,
                                      params: [UInt8(chars.count)]) else { return fallback }
            chars += chunk
        }
        let text = String(decoding: chars.prefix(Int(count)), as: UTF8.self)
        cachedName = text
        return text
    }

    // MARK: - Debug output

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func log(_ text: String) {
        if verbose { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
    }
}
