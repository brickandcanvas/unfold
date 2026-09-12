import AppKit
import CoreGraphics
import QuartzCore
import ScreenCaptureKit

final class FadeInController: NSObject {
    var onAngleUpdate: ((Double) -> Void)?

    private let sensor = LidAngleSensor()
    private var overlay: OverlayWindow?
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var overlayVisible = false
    private var testStart: CFTimeInterval?

    private let openStart = 18.0
    private let fullyOpen = 84.0
    private var displayAngle: Double = 0

    var sensorStatus: LidSensorStatus { sensor.status }
    var sensorAvailable: Bool { sensor.isAvailable }
    var currentAngle: Double? { sensor.readAngle() }

    func retrySensorPermission() -> Bool { sensor.retryPermission() }

    var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool { CGRequestScreenCaptureAccess() }

    var isEnabled: Bool = true {
        didSet { if !isEnabled { hideOverlay() } }
    }

    var flipped: Bool = false {
        didSet { overlay?.setFlipped(flipped) }
    }


    func start() {
        if #available(macOS 14.0, *), let screen = OverlayWindow.builtInScreen() {
            let link = screen.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            fallbackTimer = t
        }
    }

    func playTestAnimation() {
        testStart = CACurrentMediaTime()
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        tick()
    }

    private func tick() {
        guard isEnabled else { return }
        let target: Double
        if let start = testStart {
            let elapsed = CACurrentMediaTime() - start
            let t = min(elapsed / 2.5, 1.0)
            target = openStart + t * (fullyOpen + 5 - openStart)
            if t >= 1.0 { testStart = nil }
        } else {
            guard let a = sensor.readAngle() else { return }
            target = a
        }
        onAngleUpdate?(target)

        if !overlayVisible { displayAngle = target }
        else { displayAngle += (target - displayAngle) * 0.22 }

        let p = progress(for: displayAngle)
        if p >= 1.0 || displayAngle < openStart - 3 {
            hideOverlay()
        } else {
            showOverlay()
            overlay?.update(progress: p)
        }
    }

    private func progress(for angle: Double) -> CGFloat {
        CGFloat(min(max((angle - openStart) / (fullyOpen - openStart), 0), 1))
    }

    private func showOverlay() {
        if overlay == nil, let screen = OverlayWindow.builtInScreen() {
            let w = OverlayWindow(screen: screen)
            w.setFlipped(flipped)
            overlay = w
        }
        guard let overlay, !overlayVisible else { return }
        captureDesktopSnapshot()
        overlay.orderFrontRegardless()
        overlayVisible = true
    }

    private func captureDesktopSnapshot() {
        guard let displayID = OverlayWindow.builtInDisplayID() else { return }
        Task { [weak self] in
            guard let image = await Self.captureDisplay(displayID: displayID) else { return }
            await MainActor.run { [weak self] in
                self?.overlay?.setSnapshot(image)
            }
        }
    }

    private static func captureDisplay(displayID: CGDirectDisplayID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { return nil }
            let ourApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: ourApp.map { [$0] } ?? [],
                exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width * 2
            config.height = display.height * 2
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    private func hideOverlay() {
        guard overlayVisible else { return }
        overlay?.orderOut(nil)
        overlayVisible = false
    }
}
