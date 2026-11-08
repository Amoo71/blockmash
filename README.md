# SwitchMirror

An experimental, ad-free iPhone-to-Nintendo-Switch browser mirroring project.

## Current implementation

- English 16:9 receiver page at `/`.
- iPhone sender page at `/sender.html`, using the browser's screen-sharing API when the iOS browser exposes it.
- A Cloudflare Durable Object WebSocket relay in `worker/` forwards JPEG frames between a sender and receiver in the same six-digit room.
- The receiver draws incoming JPEG frames to a canvas, avoiding a dependency on WebRTC in the Switch browser.

**Experimental, not yet device-validated.** iOS Safari screen-capture availability and full-device capture behavior must be tested on the exact iOS 27 build. The Switch captive browser is old and may have performance or API limitations. This prototype sends video frames only (no audio), defaults to 720p at roughly 10 fps, and offers 1080p as an experimental option. It is not native AirPlay and is not a replacement for a certified AirPlay receiver.

## Deploy the website

Create a Cloudflare Pages project connected to this repository:
- Framework preset: **None**
- Build command: **leave empty**
- Build output directory: **/** (repository root)

The website files are static. Deploying Pages does not deploy the relay.

## Deploy the WebSocket relay

From the repository root, run:

```sh
cd worker
npx wrangler deploy
```

This requires a Cloudflare account and authorization in Wrangler. After deployment, copy the worker URL, for example `wss://switchmirror-relay.<your-subdomain>.workers.dev`.

Open the receiver page on the Switch and sender page on the iPhone. Enter the same six-digit room code and the relay URL on both pages. Use HTTPS for Pages and WSS for the relay.

## iOS app / IPA status

The `ios/` folder and unsigned IPA workflow remain an experimental native-capture investigation. The IPA workflow does not produce a signed installable app, and the native app is not yet connected to the JPEG relay. The browser sender is a separate proof-of-concept path. No successful physical-device or LiveContainer test is claimed.

## Known limitations

- Browser screen capture depends on iOS Safari exposing `getDisplayMedia`; if it is unavailable, the sender page cannot capture the screen.
- The browser may require the user to explicitly select what to share and may stop capture when backgrounded.
- No audio, touch-back/control channel, encryption beyond HTTPS/WSS transport, or user accounts.
- Six-digit room codes are for convenience, not strong authentication. Use a random code and do not share it publicly.
- No relay deployment, Switch compatibility test, or 1080p performance test has been completed.
