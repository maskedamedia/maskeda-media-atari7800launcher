# AGENTS.md

## Project
Build a native Apple Silicon macOS launcher/frontend for the libretro Atari 7800 core:

- Core URL:
  https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/prosystem_libretro.dylib.zip

- Upstream source reference:
  https://github.com/libretro/prosystem-libretro

This project is not RetroArch.
This project is not a general-purpose multi-core frontend.
This project is a focused, minimal, native macOS app for launching Atari 7800 games with `prosystem_libretro.dylib`.

## My Environment
I use:
- VS Code
- terminal
- Swift Package Manager

Do not assume I use Xcode as my primary workflow.
Do not make Xcode the required build path.
Do not structure the project around manual Xcode editing.

If a macOS app bundle is needed, make it buildable from the terminal.

## Primary Goal
Create a native Apple Silicon macOS app that:

1. Loads `prosystem_libretro.dylib`
2. Loads `.a78` and compatible `.bin` Atari 7800 ROMs
3. Renders video with Metal
4. Outputs audio through native macOS audio APIs
5. Supports keyboard input first
6. Optionally supports GameController.framework later
7. Exposes a clean simple launcher UI
8. Does not require RetroArch
9. Runs natively on Apple Silicon with no Rosetta

## Non-Goals
Do not:
- build a full RetroArch replacement
- add playlist scanning across dozens of systems
- add shader pipelines in v1
- add netplay
- add rewind
- add achievements
- add dozens of libretro features unless required for this core
- add emulators other than `prosystem_libretro.dylib`
- use Electron
- use Qt unless absolutely necessary
- use SDL for the app shell unless no better native option exists

## Platform Requirements
- Swift latest stable
- Swift Package Manager
- SwiftUI for app UI if practical
- Metal / MetalKit for rendering
- Native macOS app bundle or runnable macOS executable
- Target Apple Silicon first
- macOS 14+ acceptable unless a lower version is easy
- No Rosetta dependency

## Build Requirements
This project must build from terminal.

Preferred commands:
- `swift build`
- `swift run`

If app bundling is needed, provide a terminal-based packaging step.
Do not require opening Xcode to build or run.

Provide:
- `Makefile` or simple shell scripts if helpful
- clear CLI steps in README
- optional VS Code tasks in `.vscode/tasks.json`

## Architecture Requirements
Build this as a minimal libretro frontend.

### Required pieces
- Swift package as the main project structure
- Small C bridge for libretro API interop
- Dynamic loading of the core via `dlopen`
- Symbol binding for libretro entry points
- Metal-backed renderer
- Audio output layer
- Keyboard input mapping
- ROM picker or CLI ROM path support
- Optional BIOS directory support
- Save RAM / save state directory support if feasible

### Required libretro entry points
The implementation must correctly load and use the standard libretro exports, including at minimum:

- `retro_init`
- `retro_deinit`
- `retro_api_version`
- `retro_get_system_info`
- `retro_get_system_av_info`
- `retro_set_environment`
- `retro_set_video_refresh`
- `retro_set_audio_sample`
- `retro_set_audio_sample_batch`
- `retro_set_input_poll`
- `retro_set_input_state`
- `retro_load_game`
- `retro_unload_game`
- `retro_run`
- `retro_reset`
- `retro_serialize_size`
- `retro_serialize`
- `retro_unserialize`

Do not guess symbol names. Validate against libretro headers.

## UI Requirements
Two stages are acceptable.

### Stage 1
A terminal-launchable app with:
- ROM path argument or file picker
- core path argument or config
- basic game window
- keyboard controls

### Stage 2
A simple native macOS launcher UI with:
- Open ROM button
- Recent ROMs list
- Core status section
- BIOS status section
- Launch button
- Reset button
- Pause/Resume button
- Screenshot button if practical
- Scale options: 1x, 2x, 3x, Fit
- Fullscreen toggle
- Basic input mapping UI if practical

Keep the UI simple and native-looking.

## Rendering Requirements
- Use Metal or MetalKit
- Accept frame buffer data from libretro callbacks
- Convert/upload frames efficiently to a Metal texture
- Maintain aspect ratio options
- Keep frame presentation simple and stable first
- Correctness over fancy effects

## Audio Requirements
- Use native macOS audio output
- Keep latency reasonable
- Avoid crackling and underruns
- Prefer a simple reliable implementation before optimization

## Input Requirements
Default keyboard mapping should be easy for testing:

- Arrow keys = D-pad
- Z = button 1
- X = button 2
- Enter = Start/Pause if appropriate

Make bindings configurable later.
First priority is just making gameplay work.

## BIOS Requirements
Support a configurable system directory.
Detect and report whether these files exist:

- `7800 BIOS (U).rom`
- `7800 BIOS (E).rom`

Do not block launch if BIOS is missing unless the core requires it for a given title.
Show a warning instead.

## Project Layout
Use a Swift Package Manager layout that works well in VS Code and terminal.

Suggested structure:

- `Package.swift`
- `Sources/AppMain/`
- `Sources/CoreHost/`
- `Sources/Renderer/`
- `Sources/Audio/`
- `Sources/Input/`
- `Sources/UI/`
- `Sources/CLibretroBridge/`
- `Resources/`
- `Docs/`
- `.vscode/tasks.json`
- `Makefile`

Example files:

- `Sources/CLibretroBridge/include/LibretroBridge.h`
- `Sources/CLibretroBridge/LibretroBridge.c`
- `Sources/CoreHost/LibretroCoreHost.swift`
- `Sources/Renderer/MetalRenderer.swift`
- `Sources/Audio/AudioOutput.swift`
- `Sources/Input/InputManager.swift`
- `Sources/UI/ContentView.swift`

## Coding Rules
- Keep code small and readable
- Prefer clarity over abstraction
- Avoid speculative architecture
- Avoid unnecessary dependencies
- Comment the boundary between Swift and C clearly
- Separate frontend concerns from emulator-core loading concerns
- Fail with useful error messages

## Download/Core Handling
Support one of these approaches:

### Preferred
User provides a local path to `prosystem_libretro.dylib`

### Secondary
App can download:
`https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/prosystem_libretro.dylib.zip`

If download support is implemented:
- unzip safely
- validate the dylib exists
- store it in app support
- report version/date if available

Do not silently overwrite user files.

## Debugging/Validation
Must provide a way to log:

- core loading success/failure
- symbol resolution success/failure
- ROM load success/failure
- environment callback requests
- video size reported by core
- audio callback activity
- BIOS detection results

Use concise logs.

## Deliverables
Produce:

1. Working Swift package
2. Terminal build and run workflow
3. Native macOS app or runnable executable that launches Atari 7800 ROMs via `prosystem_libretro.dylib`
4. README with setup and usage
5. Clear notes on known limitations
6. Small test checklist
7. Optional VS Code tasks for build/run

## Development Order
Implement in this order:

1. C bridge + core loading
2. Environment callback
3. ROM loading
4. Headless `retro_run()` loop
5. Video callback to Metal
6. Audio callback
7. Keyboard input
8. Simple launcher flow
9. BIOS detection
10. Packaging and cleanup

## Acceptance Criteria
The project is successful when:

- it builds from terminal on Apple Silicon
- `prosystem_libretro.dylib` loads successfully
- user can pass or pick a 7800 ROM
- game video displays correctly in a Metal view
- keyboard input works in-game
- audio plays
- app can reset and relaunch content reliably
- no RetroArch is required

## Important Constraints
Do not claim the dylib is directly executable.
Do not treat this as a standalone emulator binary.
It is a libretro core and must be hosted correctly.

If uncertain about libretro frontend behavior, inspect the libretro API and the upstream ProSystem core code rather than guessing.
