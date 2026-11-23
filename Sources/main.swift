import AppKit
import ServiceManagement

let hid = HIDPP()

// 命令行探测模式：读一次电量，打印后退出。用于排查问题。
//   MouseBattery --probe
if CommandLine.arguments.contains("--probe") {
    hid.verbose = true
    hid.start()
    Thread.sleep(forTimeInterval: 1.0)
    if let r = hid.readBattery() {
        print("\(r.deviceName): \(r.percent)%\(r.charging ? "（充电中）" : r.full ? "（已充满）" : "")")
        exit(0)
    }
    print(hid.hasDevice ? "找到了 Logitech 设备，但鼠标没有回应（可能关机或休眠）" : "没有找到 Logitech 设备")
    exit(1)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = DispatchQueue(label: "battery")
    private let refreshInterval: TimeInterval = 60

    private var lastReading: BatteryReading?
    private var lastSuccess: Date?
    private var reachable = false

    private let nameItem = NSMenuItem(title: "正在查找鼠标…", action: nil, keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let updatedLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(nameItem)
        menu.addItem(statusLine)
        menu.addItem(updatedLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        render()

        hid.onBatteryEvent = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        hid.start()

        // 给系统一点时间找到设备，然后开始定时读取。
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
        let symbol = lastReading?.charging == true ? "bolt.fill" : "computermouse.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "鼠标电量")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading

        guard let reading = lastReading else {
            button.title = " --"
            nameItem.title = hid.hasDevice ? "鼠标没有回应" : "没有找到 Logitech 设备"
            statusLine.title = hid.hasDevice ? "请动一下鼠标，或检查鼠标是否开机" : "请检查接收器是否插好"
            updatedLine.isHidden = true
            return
        }

        button.title = " \(reading.percent)%"
        // 读不到时保留上次的数字，但调淡，表示不是最新的。
        button.appearsDisabled = !reachable

        nameItem.title = reading.deviceName
        let state = reading.full ? "已充满" : reading.charging ? "充电中" : "使用电池"
        statusLine.title = "电量 \(reading.percent)% · \(state)"
        updatedLine.isHidden = false
        updatedLine.title = reachable ? "更新于 \(timeText())" : "鼠标休眠或关机，显示的是 \(timeText()) 的读数"
    }

    private func timeText() -> String {
        guard let lastSuccess else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: lastSuccess)
    }

    // MARK: - 开机自动启动

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
            alert.messageText = "无法更改开机自动启动"
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
