# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Added

- Native macOS app packaging into `Atari7800Launcher.app` and `Atari7800Launcher.zip`
- App icon generation and bundling
- Persistent log file at `~/Library/Logs/prosystem-macos-launcher/app.log`
- Settings UI with saved paths for core, ROM library, system directory, and save directory
- `General`, `Input`, `Video`, and `Debug` settings tabs
- In-app reset settings action
- Editable, persisted keyboard mappings
- Recursive ROM library scanning with relative subfolder display
- Launcher guidance for obtaining the libretro core binary
- ROM sourcing guidance that avoids directing users to ROM download sites

### Changed

- Renamed the internal executable from `AppMain` to `Atari7800Launcher`
- Moved the main launcher/settings panel from a left sidebar to a bottom dock
- Default directories now live under `~/Documents/Atari7800Launcher`
- First launch now creates the default directory structure automatically
- The app remembers the last selected ROM but no longer auto-launches it on startup
- Main launcher controls were simplified and the old notes box was replaced with clearer control guidance
- The renderer now uses sharper nearest-neighbor sampling when `Sharp Pixels` is enabled
- The ROM picker now shows relative paths instead of just bare filenames

### Fixed

- Prevented repeated launch/reload behavior when console controls were being interpreted by the UI
- Reduced environment callback spam that was slowing emulation
- Fixed layout collapse issues that caused the game view to render as a tiny box
- Improved aspect-fit video presentation in the Metal view
- Fixed libretro content loading when the core expects in-memory ROM data

### Notes

- `Audio` settings are only shown when the core exposes audio-specific options
- The app does not bundle `prosystem_libretro.dylib`, BIOS ROMs, or game ROMs
