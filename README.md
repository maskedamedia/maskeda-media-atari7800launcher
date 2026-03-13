# prosystem-macos-launcher

Native Apple Silicon macOS frontend for `prosystem_libretro.dylib`.

This project hosts a libretro core. It does not execute the dylib directly, and it does not require RetroArch.

## Current Status

- Swift Package Manager project
- Native SwiftUI macOS app entry point
- `dlopen`-based libretro core loading
- required libretro symbol binding for the Atari 7800 ProSystem core host path
- Metal-backed video presentation
- native audio output via `AVAudioEngine`
- keyboard input for basic testing
- release packaging into a `.app` bundle and `.zip`

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- latest stable Swift toolchain available through Xcode command line tools or Xcode

## Build

Debug build:

```bash
swift build
```

Release build:

```bash
swift build -c release
```

## Run

Run from SwiftPM with an explicit core and ROM path:

```bash
swift run Atari7800Launcher --core /path/to/prosystem_libretro.dylib --rom /path/to/game.a78
```

You can also launch the app with no arguments and choose the core and ROM from the UI.

Core source:

- `prosystem_libretro.dylib` download: <https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/prosystem_libretro.dylib.zip>

Supported CLI flags:

- `--core /path/to/prosystem_libretro.dylib`
- `--rom /path/to/game.a78`
- `--system-dir /path/to/system`
- `--save-dir /path/to/save`

## Package For Distribution

Build a release app bundle and zip archive from the terminal:

```bash
make package
```

That produces:

- `dist/Atari7800Launcher.app`
- `dist/Atari7800Launcher.zip`

The packaged app includes:

- the frontend executable
- the app bundle metadata
- the bundled app icon
- `README.md`
- `Docs/THIRD_PARTY_NOTICES.md`

Packaging notes:

- `make package` stamps the app bundle version and short version with the build timestamp in `YYYYMMDDHHMMSS` format.

The packaged app does not currently include:

- `prosystem_libretro.dylib`
- BIOS ROMs
- game ROMs

ROM note:

- Use ROMs you own or otherwise have the rights to use.
- This project does not provide ROM files or point users to ROM download sources.

## Keyboard Mapping

- Arrow keys: D-pad
- `Z`: button 1
- `X`: button 2
- `Enter`: start

## BIOS Support

The frontend checks the configured system directory for:

- `7800 BIOS (U).rom`
- `7800 BIOS (E).rom`

Missing BIOS files are reported in the UI and log, but they are not bundled with this project.

## VS Code

Included tasks:

- `swift build`
- `swift build release`
- `swift run Atari7800Launcher`
- `package app`

## Logs

Runtime log output is written to:

- `~/Library/Logs/prosystem-macos-launcher/app.log`

This file is useful when the UI hangs or the app exits before you can read the on-screen log.

## Support

- Email: `info@maskedamedia.com`
- Website: <https://retrogaming.maskedamedia.com>
- GitHub repository: <https://github.com/mpro-maskeda/maskeda-media-atari7800launcher>

## Redistribution Notes

- This repository currently expects the user to provide a local `prosystem_libretro.dylib`.
- The recommended public source for the core binary is: <https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/prosystem_libretro.dylib.zip>
- Do not commit or redistribute Atari 7800 BIOS ROMs in this repository.
- Do not distribute or recommend third-party ROM downloads. Users should supply only ROMs they are entitled to use.
- See `Docs/THIRD_PARTY_NOTICES.md` before publishing releases or bundling external binaries.

## Known Limitations

- The renderer currently uses a straightforward CPU-side pixel conversion path before presenting with Metal.
- Audio is intentionally simple and may need buffering work for long play sessions.
- The app is not signed or notarized yet.
- The release bundle is intended for direct sharing and local execution, not App Store distribution.
- The frontend targets one core only: `prosystem_libretro.dylib`.

## Quick Checklist

- `swift build` succeeds
- app launches from `swift run`
- core loads successfully
- ROM loads successfully
- video appears in the Metal view
- keyboard input is recognized
- audio plays without obvious underruns
- `make package` creates the `.app` and `.zip`
