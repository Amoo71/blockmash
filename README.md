# BlockMash — Hybrid Launcher

iOS game library launcher. Import, manage, and organize your games locally on your device.

## Features

- **Game Library** — Browse, search, and sort your collection
- **File Import** — Import NSP, NSZ, XCI, XCZ via the iOS Files app
- **Key Management** — Import and manage prod.keys
- **Update & DLC Tracking** — Associate updates and DLC with base games
- **Settings** — Renderer selection (Metal / MoltenVK), shader cache, auto-updates

## Build

The IPA is built automatically via GitHub Actions on every push.

**Manual build:**
```bash
brew install xcodegen
xcodegen generate
xcodebuild build \
  -project BlockMash.xcodeproj \
  -scheme BlockMash \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

## Install

1. Download `BlockMash.ipa` from [Releases](../../releases)
2. Sideload with AltStore, SideStore, LiveContainer, or your preferred tool

## Requirements

- iOS 17.0+
- arm64 device (iPhone, iPad)

## Architecture

```
BlockMash/
├── BlockMashApp.swift       # App entry point
├── ContentView.swift        # Tab navigation
├── Models/
│   ├── GameEntry.swift      # Game data model
│   └── GameLibrary.swift    # Library state management
├── Views/
│   ├── LibraryView.swift    # Game grid/list
│   ├── GameDetailView.swift # Game info & actions
│   ├── ImportView.swift     # File picker & import
│   └── SettingsView.swift   # App configuration
└── Assets.xcassets/         # Colors & app icon
```
