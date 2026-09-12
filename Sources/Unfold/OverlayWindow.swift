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

    private let gradientStrength: CGFloat = 1.0
    private let blurRadius: Double = 80
    private let blurLocationOffset: CGFloat = -0.4
    private let maxTiltDegrees: CGFloat = 30

    private var currentSharpImage: CGImage?
    private var blurGeneration: UInt64 = 0
    private var directionFlipped = false

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

        let mid = 0.6 * gradientStrength
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
            NSColor.black.withAlphaComponent(mid).cgColor,
            NSColor.black.withAlphaComponent(gradientStrength).cgColor,
        ]
        gradient.locations = [0.0, 0.0, 0.0, 1.0]
        container.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setFlipped(_ f: Bool) {
        guard directionFlipped != f else { return }
        directionFlipped = f
        let start = directionFlipped ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0.5, y: 1)
        let end = directionFlipped ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 0.5, y: 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blurMask.startPoint = start
        blurMask.endPoint = end
        gradient.startPoint = start
        gradient.endPoint = end
        CATransaction.commit()
    }

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

    func setImage(_ cgImage: CGImage?) {
        currentSharpImage = cgImage
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = cgImage
        blurredLayer.contents = cgImage
        CATransaction.commit()
        regenerateBlurredImage()
    }

    private func regenerateBlurredImage() {
        guard let cgImage = currentSharpImage else { return }
        blurGeneration &+= 1
        let gen = blurGeneration
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self, let blurred = self.makeBlurredImage(from: cgImage) else { return }
            DispatchQueue.main.async {
                guard self.blurGeneration == gen else { return }
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
        if blurRadius <= 0.01 { return cgImage }
        guard let clamp = CIFilter(name: "CIAffineClamp") else { return nil }
        clamp.setValue(ci, forKey: kCIInputImageKey)
        clamp.setValue(NSAffineTransform(), forKey: "inputTransform")
        guard let clamped = clamp.outputImage,
              let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(blurRadius, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage else { return nil }
        return ciContext.createCGImage(output, from: extent)
    }

    // p: 0 = fully skewed & max effects (lid closed), 1 = flat, no effects (lid open)
    func update(progress p: CGFloat) {
        let clamped = min(max(p, 0), 1)

        let tiltDeg = maxTiltDegrees * (1 - clamped)
        let tiltRad = tiltDeg * .pi / 180
        let scale: CGFloat = 0.94 + 0.06 * clamped
        var t = CATransform3DIdentity
        t.m34 = -1.0 / 1600
        t = CATransform3DRotate(t, tiltRad, 1, 0, 0)
        t = CATransform3DScale(t, scale, scale, 1)

        let band: CGFloat = 0.3
        let bandCenter = clamped * (1 + band) - band / 2 + blurLocationOffset
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

    func setFlipped(_ flipped: Bool) {
        snapshot.setFlipped(flipped)
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

    func setFlipped(_ flipped: Bool) {
        gradientView.setFlipped(flipped)
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
