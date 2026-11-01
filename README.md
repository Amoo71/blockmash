# BlockMash

Game library, import and touch-controller layout editor for iOS.

**BlockMash does not run games. It has no emulation core.**

## Features

- Import NSP, NSZ, XCI, XCZ via the file picker, the clipboard, or the app's `Games` folder in the Files app (auto-scanned when the app becomes active)
- Reads container metadata: title ID (file name tag or ticket), version tag, NCA count
- Groups updates and DLC under the base game by title ID
- Keeps prod.keys on-device
- Touch controller layout editor: position, size and opacity per button
- Shows connected physical controllers, A/B swap

In LiveContainer, if the file picker's Open button does nothing, long-press the app → Settings → enable **Fix File Picker**.

## Install

1. Download `BlockMash.ipa` from [Releases](../../releases)
2. Sideload with LiveContainer, SideStore, AltStore or similar

## Build

The IPA is built by GitHub Actions on every push that touches the app.

```bash
brew install xcodegen
xcodegen generate
xcodebuild build -project BlockMash.xcodeproj -scheme BlockMash -configuration Release -sdk iphoneos \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
