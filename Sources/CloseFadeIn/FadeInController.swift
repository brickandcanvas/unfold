import AppKit
import QuartzCore

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

    var isEnabled: Bool = true {
        didSet { if !isEnabled { hideOverlay() } }
    }

    var gradientStrength: CGFloat = 0.55 {
        didSet { overlay?.setGradientStrength(gradientStrength) }
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

    private var tickCount = 0
    private func tick() {
        tickCount += 1
        if tickCount % 120 == 1 {
            NSLog("CFI tick: count=\(tickCount) enabled=\(isEnabled) status=\(sensor.status)")
        }
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
            overlay = OverlayWindow(screen: screen)
            overlay?.setGradientStrength(gradientStrength)
        }
        guard let overlay, !overlayVisible else { return }
        captureDesktopSnapshot()
        overlay.orderFrontRegardless()
        overlayVisible = true
    }

    private func captureDesktopSnapshot() {
        guard let displayID = OverlayWindow.builtInDisplayID() else { return }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let image = CGDisplayCreateImage(displayID)
            DispatchQueue.main.async {
                self?.overlay?.setSnapshot(image)
            }
        }
    }

    private func hideOverlay() {
        guard overlayVisible else { return }
        overlay?.orderOut(nil)
        overlayVisible = false
    }
}
