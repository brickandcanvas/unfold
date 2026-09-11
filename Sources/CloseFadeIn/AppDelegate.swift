import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = FadeInController()
    private let angleItem = NSMenuItem(title: "Lid angle: —", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(
        title: "Grant Input Monitoring permission…", action: nil, keyEquivalent: "")
    private let defaultsKey = "CFI_Enabled"
    private let gradientKey = "CFI_GradientStrength"
    private var permissionTimer: Timer?
    private var gradientSlider: NSSlider?
    private var gradientValueLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [defaultsKey: true, gradientKey: 0.55])
        controller.isEnabled = UserDefaults.standard.bool(forKey: defaultsKey)
        controller.gradientStrength = CGFloat(UserDefaults.standard.double(forKey: gradientKey))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        let menu = NSMenu()

        enabledItem.action = #selector(toggleEnabled)
        enabledItem.target = self
        enabledItem.state = controller.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        permissionItem.action = #selector(openInputMonitoringSettings)
        permissionItem.target = self
        permissionItem.isHidden = true
        menu.addItem(permissionItem)

        menu.addItem(angleItem)

        let testItem = NSMenuItem(title: "Test Animation", action: #selector(runTest), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(.separator())
        menu.addItem(makeGradientStrengthItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit CloseFadeIn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        controller.onAngleUpdate = { [weak self] angle in
            self?.angleItem.title = String(format: "Lid angle: %.0f°", angle)
        }
        controller.start()
        refreshSensorState()

        if CommandLine.arguments.contains("--test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.controller.playTestAnimation()
            }
        }
    }

    private func refreshSensorState() {
        switch controller.sensorStatus {
        case .ok:
            permissionItem.isHidden = true
            permissionTimer?.invalidate()
            permissionTimer = nil
        case .permissionDenied:
            angleItem.title = "Permission needed"
            permissionItem.isHidden = false
            startPermissionPolling()
        case .notFound:
            angleItem.title = "Lid angle sensor not found"
            permissionItem.isHidden = true
        }
    }

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.controller.retrySensorPermission() { self.refreshSensorState() }
        }
    }

    private var menuRefreshTimer: Timer?

    func menuWillOpen(_ menu: NSMenu) {
        menuRefreshTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let angle = self.controller.currentAngle else { return }
            self.angleItem.title = String(format: "Lid angle: %.0f°", angle)
        }
        if let t = menuRefreshTimer {
            RunLoop.main.add(t, forMode: .eventTracking)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    private func makeGradientStrengthItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 46))

        let label = NSTextField(labelWithString: "Gradient strength")
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 14, y: 25, width: 160, height: 18)
        container.addSubview(label)

        let value = NSTextField(labelWithString: String(format: "%.0f%%", controller.gradientStrength * 100))
        value.font = NSFont.menuFont(ofSize: 0)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.frame = NSRect(x: 174, y: 25, width: 52, height: 18)
        container.addSubview(value)
        gradientValueLabel = value

        let slider = NSSlider(
            value: Double(controller.gradientStrength), minValue: 0, maxValue: 1,
            target: self, action: #selector(gradientSliderChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 14, y: 3, width: 212, height: 20)
        container.addSubview(slider)
        gradientSlider = slider

        let item = NSMenuItem()
        item.view = container
        return item
    }

    @objc private func gradientSliderChanged(_ sender: NSSlider) {
        let v = CGFloat(sender.doubleValue)
        controller.gradientStrength = v
        UserDefaults.standard.set(Double(v), forKey: gradientKey)
        gradientValueLabel?.stringValue = String(format: "%.0f%%", v * 100)
    }

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
        enabledItem.state = controller.isEnabled ? .on : .off
        UserDefaults.standard.set(controller.isEnabled, forKey: defaultsKey)
        updateStatusIcon()
    }

    @objc private func runTest() {
        controller.playTestAnimation()
    }

    @objc private func openInputMonitoringSettings() {
        _ = controller.retrySensorPermission()
        refreshSensorState()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateStatusIcon() {
        let name = controller.isEnabled ? "laptopcomputer" : "laptopcomputer.slash"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "CloseFadeIn")
    }
}
