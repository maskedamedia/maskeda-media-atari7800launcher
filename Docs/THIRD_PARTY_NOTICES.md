# Third-Party Notices

This project currently uses or references the following external components.

## 1. `libretro.h`

- Source: `libretro-common`
- Upstream: <https://github.com/libretro/libretro-common>
- Local copy: `Sources/CLibretroBridge/include/libretro.h`
- License: permissive MIT-style license stated in the file header

Compliance notes:
- Keep the copyright and permission notice intact in the vendored header.
- If the header is modified, retain the upstream notice and mark local changes.

## 2. `prosystem_libretro.dylib`

- Upstream source: <https://github.com/libretro/prosystem-libretro>
- Upstream license file: `License.txt`
- License observed upstream: GNU General Public License, version 2

Compliance notes:
- This repository does not currently vendor or bundle the core binary.
- If you redistribute the compiled core binary with this frontend, you should also distribute the corresponding source code and preserve the GPLv2 license text and notices.
- If you modify the core and redistribute it, mark your changes and dates in the modified files.
- If you distribute a release that bundles this frontend with the GPL core, treat the overall licensing posture as GPL-sensitive and choose a project license that is compatible with that distribution model.

## 3. BIOS ROMs

Typical Atari 7800 BIOS filenames:

- `7800 BIOS (U).rom`
- `7800 BIOS (E).rom`

Compliance notes:
- BIOS ROMs are not included in this repository.
- Users should supply their own BIOS files only if they have the rights to do so.
- Do not commit BIOS files, game ROMs, or other copyrighted console assets into this repository.

## Practical Release Guidance

Safer GitHub redistribution model:

- Keep this repository limited to the frontend source code plus the vendored `libretro.h`.
- Require users to point the app at a local `prosystem_libretro.dylib`.
- Do not commit BIOS ROMs or commercial game ROMs.

If you later decide to ship releases with a bundled core binary:

- Include the upstream GPLv2 license text from `prosystem-libretro/License.txt`.
- Provide the corresponding source code for the bundled core, including your modifications if any.
- Preserve upstream notices.
- Revisit the license for this frontend so the combined distribution is not license-incompatible.

This file is operational guidance for the repository and is not legal advice.
