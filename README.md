# SwitchMirror

An ad-free 16:9 receiver prototype and iOS capture research starter for experimenting with Nintendo Switch browser display mirroring.

## Project status

**Prototype only — live mirroring is not implemented.** The receiver page is a static layout. The sender test checks browser capture availability. The Swift file is an experimental capture scaffold; it does not yet encode, signal, or transmit frames.

## Web receiver — Cloudflare Pages

This is a static site. In Cloudflare, create a **Workers & Pages → Create → Pages → Connect to Git** project and select `Amoo71/blockmash` on branch `main`.

Use these settings:
- Framework preset: **None**
- Build command: **Leave empty**
- Build output directory: **/** (repository root)

The root `index.html` is the receiver page. No ads, analytics, or third-party trackers are included. The repository includes `wrangler.toml` and `_headers` for static hosting configuration. A Cloudflare account connection and project creation are still required; this repository change does not deploy the site by itself.

## iOS build — unsigned IPA artifact

The XcodeGen project definition is `ios/project.yml`. A GitHub Actions workflow at `.github/workflows/ios-unsigned-ipa.yml` builds an **unsigned** device IPA when manually dispatched or when iOS source files change.

To run it, open the repository's **Actions** tab, select **Build unsigned iOS IPA**, and choose **Run workflow**. Download the `SwitchMirror-unsigned-IPA` artifact from the completed run.

An unsigned IPA is a build artifact, not a signed App Store/ad-hoc package. Whether LiveContainer accepts and can run it depends on its import/signing behavior and the target iOS version. No successful physical-device build or LiveContainer test is claimed yet.

## iOS capture experiment and LiveContainer

The current Swift source is experimental. Screen-capture API availability varies by iOS version and execution environment. LiveContainer does not support all app-extension workflows; this source does not guarantee full-device capture inside LiveContainer. No ReplayKit Broadcast Upload Extension is included.

## Remaining engineering work

1. Compile the project and fix any SDK/API availability errors surfaced by the macOS build runner.
2. Validate capture on the physical target iPhone and exact iOS build.
3. Convert captured sample buffers into a video track and implement transport.
4. Add authenticated, short-lived pairing and signalling over HTTPS/WSS.
5. Implement receiver offer/answer and ICE handling, then test actual WebRTC/codec support in the Switch DNS browser.
6. Measure latency and adapt resolution/frame rate; 1080p30 is a target, not a guarantee.

The current receiver is not yet capable of showing a live iPhone screen.