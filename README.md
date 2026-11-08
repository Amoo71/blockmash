# SwitchMirror

An ad-free 16:9 receiver prototype and iOS capture research starter for experimenting with Nintendo Switch browser display mirroring.

## Project status

**Prototype only — live mirroring is not implemented.** The receiver page is a static layout. The sender test checks browser capture availability. The Swift file is an experimental ScreenCaptureKit capture scaffold; it does not yet encode, signal, or transmit frames.

## Web receiver

The repository root contains `index.html`, so it can be deployed as a static site (for example, Cloudflare Pages with no build command and output directory `/`). `sender-test.html` is a separate iPhone browser capability test.

## iOS capture experiment

Open `ios/SwitchMirrorApp.swift` in an Xcode iOS project on a Mac. ScreenCaptureKit APIs and availability vary by OS version and app execution environment. LiveContainer does not support all app-extension workflows; this source does not guarantee capture will work when sideloaded in LiveContainer. It has not been compiled or signed here.

## Next engineering steps

1. Validate capture on the physical target iPhone and iOS version.
2. Convert captured sample buffers into a WebRTC-compatible video track (or another transport the Switch browser actually supports).
3. Add authenticated, short-lived pairing and signalling over HTTPS/WSS.
4. Test receiver browser WebRTC support on the actual Switch firmware/DNS browser.
5. Measure latency and adapt resolution/frame rate; 1080p30 is a target, not a guarantee.

No ads, analytics, or third-party trackers are included.
