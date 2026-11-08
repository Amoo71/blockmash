# Known limitations

- This repository is a starter, not a working mirroring product.
- iOS Safari webpages cannot normally capture the entire iPhone display. The included web sender is only a feature test.
- The Swift ScreenCaptureKit experiment is not proven to work inside LiveContainer on the user's exact iOS build. Physical-device testing is required.
- No ReplayKit Broadcast Upload Extension is included.
- No video encoder, WebRTC sender track, signalling server, pairing flow, receiver offer/answer handling, or ICE configuration is implemented.
- The Nintendo Switch's DNS-triggered browser is an old/constrained browser environment. WebRTC APIs/codecs may be absent or incomplete.
- A 1080p30 capture request does not mean 1080p30 will arrive. The Switch's viewport and decode capability may require 720p or lower.
- This code has not been built, signed, deployed, or tested on hardware.
