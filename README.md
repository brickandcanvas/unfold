# Unfold

A macOS menu bar app that plays an iPhone Duo-style fade-in animation when you
open your MacBook lid. The transition is driven by the built-in lid angle
sensor: as the lid opens, a snapshot of your desktop unfolds through a 3D
perspective tilt, with a bottom-heavy blur and black gradient that recedes to
reveal the live desktop.

## Requirements

- MacBook with a supported hinge angle sensor (M1 or later, and recent Intel
  models). Verified on M4 Pro (Mac16,7).
- macOS 14 (Sonoma) or later.
- Xcode command-line tools (`xcode-select --install`).

## Install

```
git clone <your-fork-url> unfold
cd unfold
./make-app.sh
open Unfold.app
```

`make-app.sh` compiles a Swift Package release build, packages it into
`Unfold.app`, and code-signs it. If it finds an "Apple Development"
identity in your login keychain, it signs with that so macOS Privacy
permissions persist across rebuilds. Otherwise it falls back to ad-hoc
signing (permissions will need to be re-granted after each rebuild).

To pin a specific signing identity, set `UNFOLD_SIGNING_IDENTITY`:

```
UNFOLD_SIGNING_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" ./make-app.sh
```

## Permissions

The app needs two permissions on first launch:

1. **Input Monitoring** — to read the lid hinge angle from
   `AppleSPUHIDDevice` (usage page `0x20`, usage `0x8A`).
2. **Screen Recording** — to capture the desktop for the fade animation.

On launch, the app checks both and prompts with a dialog if either is
missing. Grant the app under:

- System Settings → Privacy & Security → **Input Monitoring**
- System Settings → Privacy & Security → **Screen Recording**

## Usage

The menu bar icon (laptop symbol) exposes:

- **Enabled** — toggle the animation on/off. Persisted across launches.
- **Flip direction** — flip the mask so the black gradient + blur band
  anchors at the top of the screen instead of the bottom.
- **Lid angle** — live readout of the current hinge angle in degrees.
- **Test Animation** — play the reveal animation without touching the lid.
- **Grant … permission** — appears only when a permission is missing;
  clicking opens the relevant System Settings pane.
- **Quit Unfold**.

To launch on login, add `Unfold.app` to System Settings → General →
Login Items.

## How it works

- **`LidAngleSensor`** opens the built-in HID lid angle device via
  `IOHIDManager` and reads a 3-byte feature report on every tick.
- **`FadeInController`** drives the animation from a `CADisplayLink` tick
  (60–120 Hz), interpolates the sensor reading with easing, and maps the
  angle range 18°–84° to a normalised progress.
- **`OverlayWindow`** is a borderless screen-saver-level window with:
  - An opaque black backdrop so the live desktop can't bleed through.
  - A `SnapshotView` that renders the captured desktop image with a 3D
    perspective transform (`CATransform3DRotate` + `m34`), a pre-blurred
    duplicate layer clamped to prevent edge fading (`CIAffineClamp` +
    `CIGaussianBlur`), and a bottom-heavy black gradient — the blur mask
    and gradient locations sweep with the lid angle.
- **`SCScreenshotManager`** (ScreenCaptureKit) captures the desktop each
  time the overlay is about to appear, excluding Unfold's own windows.

## Development

```
swift build -c release
./make-app.sh
```

The `probe/` directory contains a small CLI (`lid-probe.swift`) used
during initial development to verify the HID report format on this
machine.

## Notes

- Fully closing the lid puts macOS to sleep, and the lock screen blocks
  overlays on wake. The animation runs reliably for partial-close/reopen
  cycles or when your Mac is set to not require a password immediately.
- Ad-hoc code signing changes the app's `CDHash` on every rebuild, which
  causes TCC to silently deny previously-granted permissions. Signing with
  an Apple Development identity (any team) makes TCC key on the team ID +
  bundle ID instead, so permissions persist.
