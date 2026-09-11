import AppKit
import CoreGraphics
import CoreImage

final class SnapshotView: NSView {
    private let container = CALayer()
    private let imageLayer = CALayer()
    private let blurredLayer = CALayer()
    private let blurMask = CAGradientLayer()
    private let gradient = CAGradientLayer()
    private let ciContext = CIContext()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)
        container.bounds = bounds
        layer?.addSublayer(container)

        imageLayer.frame = container.bounds
        imageLayer.contentsGravity = .resize
        container.addSublayer(imageLayer)

        blurredLayer.frame = container.bounds
        blurredLayer.contentsGravity = .resize
        blurMask.frame = blurredLayer.bounds
        blurMask.startPoint = CGPoint(x: 0.5, y: 1)
        blurMask.endPoint = CGPoint(x: 0.5, y: 0)
        blurMask.colors = [
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
        ]
        blurMask.locations = [0.0, 0.0, 0.0, 1.0]
        blurredLayer.mask = blurMask
        container.addSublayer(blurredLayer)

        gradient.frame = container.bounds
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.35).cgColor,
            NSColor.black.withAlphaComponent(0.55).cgColor,
        ]
        gradient.locations = [0.0, 0.0, 0.0, 1.0]
        container.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)
        container.bounds = bounds
        imageLayer.frame = container.bounds
        blurredLayer.frame = container.bounds
        blurMask.frame = blurredLayer.bounds
        gradient.frame = container.bounds
        CATransaction.commit()
    }

    private var gradientStrength: CGFloat = 0.55

    func setGradientStrength(_ strength: CGFloat) {
        gradientStrength = max(0, min(1, strength))
        applyGradientColors()
    }

    private func applyGradientColors() {
        let mid = 0.6 * gradientStrength
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(mid).cgColor,
            NSColor.black.withAlphaComponent(gradientStrength).cgColor,
        ]
        CATransaction.commit()
    }

    func setImage(_ cgImage: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = cgImage
        blurredLayer.contents = cgImage
        CATransaction.commit()

        guard let cgImage else { return }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self, let blurred = self.makeBlurredImage(from: cgImage) else {
                NSLog("CFI blur: failed to generate blurred image")
                return
            }
            NSLog("CFI blur: generated blurred image \(blurred.width)x\(blurred.height)")
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.blurredLayer.contents = blurred
                CATransaction.commit()
            }
        }
    }

    private func makeBlurredImage(from cgImage: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: cgImage)
        let extent = ci.extent
        guard let clamp = CIFilter(name: "CIAffineClamp") else { return nil }
        clamp.setValue(ci, forKey: kCIInputImageKey)
        clamp.setValue(NSAffineTransform(), forKey: "inputTransform")
        guard let clamped = clamp.outputImage,
              let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(40.0, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage else { return nil }
        return ciContext.createCGImage(output, from: extent)
    }

    // p: 0 = fully skewed & max effects (lid closed), 1 = flat, no effects (lid open)
    func update(progress p: CGFloat) {
        let clamped = min(max(p, 0), 1)

        let tiltDeg: CGFloat = 10 * (1 - clamped)
        let tiltRad = tiltDeg * .pi / 180
        let scale: CGFloat = 0.94 + 0.06 * clamped
        var t = CATransform3DIdentity
        t.m34 = -1.0 / 1600
        t = CATransform3DRotate(t, tiltRad, 1, 0, 0)
        t = CATransform3DScale(t, scale, scale, 1)

        let band: CGFloat = 0.3
        let bandCenter = clamped * (1 + band) - band / 2
        let a = max(0, bandCenter - band / 2)
        let b = min(1, bandCenter + band / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.transform = t
        blurMask.locations = [0, NSNumber(value: Double(a)), NSNumber(value: Double(b)), 1]
        gradient.locations = [0, NSNumber(value: Double(a)), NSNumber(value: Double(b)), 1]
        CATransaction.commit()
    }
}

final class GradientView: NSView {
    private let backdrop = NSView()
    private let snapshot = SnapshotView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(backdrop)

        snapshot.frame = bounds
        snapshot.autoresizingMask = [.width, .height]
        addSubview(snapshot)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSnapshot(_ image: CGImage?) {
        snapshot.setImage(image)
    }

    func setGradientStrength(_ strength: CGFloat) {
        snapshot.setGradientStrength(strength)
    }

    // p: 0 = full strength (lid closed), 1 = fully faded (lid open)
    func update(progress p: CGFloat) {
        let clamped = min(max(p, 0), 1)
        snapshot.update(progress: clamped)
        let windowFade = pow(min(max((clamped - 0.85) / 0.15, 0), 1), 1.4)
        alphaValue = 1 - windowFade
    }
}

final class OverlayWindow: NSWindow {
    private let gradientView: GradientView

    init(screen: NSScreen) {
        gradientView = GradientView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        contentView = gradientView
    }

    func update(progress: CGFloat) {
        gradientView.update(progress: progress)
    }

    func setSnapshot(_ image: CGImage?) {
        gradientView.setSnapshot(image)
    }

    func setGradientStrength(_ strength: CGFloat) {
        gradientView.setGradientStrength(strength)
    }

    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        } ?? NSScreen.main
    }

    static func builtInDisplayID() -> CGDirectDisplayID? {
        guard let screen = builtInScreen(),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
