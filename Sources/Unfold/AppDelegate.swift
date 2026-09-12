import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = FadeInController()
    private let angleItem = NSMenuItem(title: "Lid angle: —", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: nil, keyEquivalent: "")
    private let flipItem = NSMenuItem(title: "Flip direction", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(
        title: "Grant Input Monitoring permission…", action: nil, keyEquivalent: "")
    private let screenRecordingItem = NSMenuItem(
        title: "Grant Screen Recording permission…", action: nil, keyEquivalent: "")

    private let enabledKey = "UF_Enabled"
    private let flipKey = "UF_Flipped"

    private var permissionTimer: Timer?
    private var menuRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [enabledKey: true, flipKey: false])
        controller.isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        controller.flipped = UserDefaults.standard.bool(forKey: flipKey)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        let menu = NSMenu()

        enabledItem.action = #selector(toggleEnabled)
        enabledItem.target = self
        enabledItem.state = controller.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        flipItem.action = #selector(toggleFlipped)
        flipItem.target = self
        flipItem.state = controller.flipped ? .on : .off
        menu.addItem(flipItem)

        menu.addItem(.separator())

        permissionItem.action = #selector(openInputMonitoringSettings)
        permissionItem.target = self
        permissionItem.isHidden = true
        menu.addItem(permissionItem)

        screenRecordingItem.action = #selector(openScreenRecordingSettings)
        screenRecordingItem.target = self
        screenRecordingItem.isHidden = controller.hasScreenRecordingPermission
        menu.addItem(screenRecordingItem)

        menu.addItem(angleItem)

        let testItem = NSMenuItem(title: "Test Animation", action: #selector(runTest), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Unfold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        controller.onAngleUpdate = { [weak self] angle in
            self?.angleItem.title = String(format: "Lid angle: %.0f°", angle)
        }
        controller.start()
        refreshSensorState()

        _ = controller.requestScreenRecordingPermission()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.presentMissingPermissionAlerts()
        }

        if CommandLine.arguments.contains("--test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.controller.playTestAnimation()
            }
        }
    }

    private func presentMissingPermissionAlerts() {
        if controller.sensorStatus == .permissionDenied {
            let alert = NSAlert()
            alert.messageText = "Unfold needs Input Monitoring permission"
            alert.informativeText = "To detect when the MacBook lid opens or closes, allow Unfold under Privacy & Security → Input Monitoring."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            alert.alertStyle = .informational
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                openInputMonitoringSettings()
            }
        }

        if !controller.hasScreenRecordingPermission {
            let alert = NSAlert()
            alert.messageText = "Unfold needs Screen Recording permission"
            alert.informativeText = "To capture your desktop for the fade animation, allow Unfold under Privacy & Security → Screen Recording."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            alert.alertStyle = .informational
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                openScreenRecordingSettings()
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

    func menuWillOpen(_ menu: NSMenu) {
        screenRecordingItem.isHidden = controller.hasScreenRecordingPermission
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

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
        enabledItem.state = controller.isEnabled ? .on : .off
        UserDefaults.standard.set(controller.isEnabled, forKey: enabledKey)
        updateStatusIcon()
    }

    @objc private func toggleFlipped() {
        controller.flipped.toggle()
        flipItem.state = controller.flipped ? .on : .off
        UserDefaults.standard.set(controller.flipped, forKey: flipKey)
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

    @objc private func openScreenRecordingSettings() {
        _ = controller.requestScreenRecordingPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateStatusIcon() {
        let name = controller.isEnabled ? "laptopcomputer" : "laptopcomputer.slash"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Unfold")
    }
}
