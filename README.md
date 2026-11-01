# BlockMash / NXLauncher

This repository builds two iOS apps:

| App | What it is | Runs games? |
|-----|------------|-------------|
| **NXLauncher** | The MeloNX Switch emulator (Ryujinx core), built from upstream source with its own name, bundle ID and two build fixes | Yes, with JIT, prod.keys and firmware |
| **BlockMash** | Game library, import and touch-controller layout editor | **No.** It has no emulation core. |

Both are released as unsigned IPAs via GitHub Actions ([Releases](../../releases)).

## NXLauncher

Built by `.github/workflows/build-nxlauncher.yml` from the official MeloNX repository (`https://git.ryujinx.app/projects/MeloNX`). The UI is MeloNX's own for now.

Changes from upstream, both needed to build with Xcode 26.6:
- `EmulationView.swift`: `private` removed from stored properties, otherwise its initializer is inaccessible from `ContentView.swift`
- The Swift layer is built with `-Onone`, because the Swift 6.3.3 optimizer crashes on it. The Ryujinx core that does the emulation is still fully optimized.

Requirements on the device:
- **JIT.** The core generates code at runtime and cannot run without it. On iOS 26 and later, StikDebug is required.
- **prod.keys and firmware** dumped from your own Switch.
- **Increased Memory Limit** entitlement. Inside LiveContainer, apps run with LiveContainer's own entitlements, so LiveContainer needs it.
- **LiveContainer.** The executable is patched to MH_DYLIB, so the IPA can't be installed as a standalone app.

**License:** MeloNX is GNU AGPL v3 or later (© Rhajune Park and contributors), so NXLauncher is too. Each release ships the exact source tree as `NXLauncher-source.tar.gz`.

## BlockMash

- Import NSP, NSZ, XCI, XCZ via the file picker, the clipboard, or the app's `Games` folder in the Files app (auto-scanned when the app becomes active)
- Reads container metadata: title ID (file name tag or ticket), version tag, NCA count
- Groups updates and DLC under the base game by title ID
- Keeps prod.keys on-device
- Touch controller layout editor: position, size and opacity per button
- Shows connected physical controllers, A/B swap

In LiveContainer, if the file picker's Open button does nothing, long-press the app → Settings → enable **Fix File Picker**.

### Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild build -project BlockMash.xcodeproj -scheme BlockMash -configuration Release -sdk iphoneos \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
