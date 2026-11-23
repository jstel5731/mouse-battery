import AppKit
import ServiceManagement

let hid = HIDPP()

// Probe mode reads the battery once, prints it and exits. Use it for troubleshooting:
//   MouseBattery --probe
if CommandLine.arguments.contains("--probe") {
    hid.verbose = true
    hid.start()
    Thread.sleep(forTimeInterval: 1.0)
    if let r = hid.readBattery() {
        print("\(r.deviceName): \(r.percent)%\(r.charging ? " (charging)" : r.full ? " (fully charged)" : "")")
        exit(0)
    }
    print(hid.hasDevice ? "Found a Logitech device, but the mouse did not answer (off or asleep?)"
                        : "No Logitech device found")
    exit(1)
}

// Icon preview mode writes sample icons as PNG files, to check the drawing without a menu bar:
//   MouseBattery --icon-preview <directory>
if let flag = CommandLine.arguments.firstIndex(of: "--icon-preview"), CommandLine.arguments.count > flag + 1 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    let samples: [(name: String, percent: Int?, charging: Bool)] = [
        ("unknown", nil, false), ("5", 5, false), ("64", 64, false),
        ("64-charging", 64, true), ("100", 100, false), ("100-charging", 100, true),
    ]
    let scale = 8
    for sample in samples {
        let icon = BatteryIcon.image(percent: sample.percent, charging: sample.charging)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(icon.size.width) * scale, pixelsHigh: Int(icon.size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = icon.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        // A white backdrop keeps the black template image visible on dark pages.
        NSColor.white.setFill()
        NSRect(origin: .zero, size: icon.size).fill()
        icon.draw(in: NSRect(origin: .zero, size: icon.size))
        NSGraphicsContext.restoreGraphicsState()
        try! bitmap.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("icon-\(sample.name).png"))
    }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = DispatchQueue(label: "battery")
    private let refreshInterval: TimeInterval = 60

    private var lastReading: BatteryReading?
    private var lastSuccess: Date?
    private var reachable = false

    private let nameItem = NSMenuItem(title: "Looking for mouse…", action: nil, keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let updatedLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(nameItem)
        menu.addItem(statusLine)
        menu.addItem(updatedLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        render()

        hid.onBatteryEvent = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        hid.start()

        // Give the system a moment to find the device before the first read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in self.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func refresh() {
        queue.async {
            let reading = hid.readBattery()
            DispatchQueue.main.async {
                self.reachable = reading != nil
                if let reading {
                    self.lastReading = reading
                    self.lastSuccess = Date()
                }
                self.render()
            }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        button.image = BatteryIcon.image(percent: lastReading?.percent, charging: lastReading?.charging ?? false)
        button.setAccessibilityLabel("Mouse battery")

        guard let reading = lastReading else {
            button.toolTip = nil
            nameItem.title = hid.hasDevice ? "Mouse not responding" : "No Logitech device found"
            statusLine.title = hid.hasDevice ? "Move the mouse or check that it is switched on"
                                             : "Check that the receiver is plugged in"
            updatedLine.isHidden = true
            return
        }

        // Keep the last value when the mouse cannot be reached, but dim it to show it is stale.
        button.appearsDisabled = !reachable
        button.toolTip = "\(reading.deviceName): \(reading.percent)%"

        nameItem.title = reading.deviceName
        let state = reading.full ? "Fully Charged" : reading.charging ? "Charging" : "On Battery"
        statusLine.title = "\(reading.percent)% · \(state)"
        updatedLine.isHidden = false
        updatedLine.title = reachable ? "Updated at \(timeText())" : "Mouse asleep or off · last read at \(timeText())"
    }

    private func timeText() -> String {
        guard let lastSuccess else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: lastSuccess)
    }

    // MARK: - Launch at login

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
