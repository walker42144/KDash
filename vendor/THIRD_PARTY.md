# Third-party components

KDash bundles generic ARM runtime binaries and a CJK font. It does **not**
load KOReader code or require a KOReader installation at runtime. The binaries
below were taken from the public KOReader v2026.07.1 `kindlepw2` release and
are used as standalone executables.

## LuaJIT 2.1 (ARM EABI5, soft-float ABI)

- File: `vendor/luajit`
- SHA-256: `b830a60c2d0b0e64de37f20d18595990d5e408f945d2af4c0ea3181a13ed7f1c`
- License: MIT. See `vendor/LuaJIT-COPYING`.
- Source: https://github.com/LuaJIT/LuaJIT
- Upstream bundle: https://github.com/koreader/koreader/releases

LuaJIT is used only as the Lua 5.1 runtime. Any compatible LuaJIT/Lua 5.1
compatible ARM EABI build can replace it in `runtime/luajit`.

## FBInk 1.25.0 (ARM EABI5, soft-float ABI)

- File: `vendor/fbink`
- SHA-256: `f6f70557d351657f7e4900b61dfc89d7068e72a9fc0710e6a8ff6e8223bfbe56`
- License: GPLv3+. See `vendor/FBInk-LICENSE`.
- Source: https://github.com/NiLuJe/FBInk
- Upstream bundle: https://github.com/koreader/koreader/releases

FBInk is invoked as a subprocess for framebuffer text, clearing, images and
e-ink refresh. KDash does not link against FBInk and does not depend on
KOReader. The complete corresponding source is available at the URL above;
the binary is unmodified. To rebuild it, use
https://github.com/koreader/koxtoolchain with `make kindle` (or
`make KINDLE=1 OPENTYPE=1`), then place the result in `vendor/fbink`.

## Droid Sans Fallback Full

- File: `assets/fonts/DroidSansFallbackFull.ttf`
- License: Apache License 2.0. See `assets/fonts/LICENSE-Apache-2.0.txt`.
- Source: https://github.com/aosp-mirror/platform_frameworks_base/tree/main/data/fonts

The font is used by FBInk's OpenType renderer for Chinese/Latin text.

## Services

- Open-Meteo: https://open-meteo.com/ (data license CC BY 4.0; attribution
  appears in the API response and this notice).
- Dida365 Open API: https://developer.dida365.com/ (terms and rate limits
  apply to the user's own application credentials).

## Noto Sans SC Regular

Candidate default CJK/Latin font. SIL Open Font License 1.1, see assets/fonts/NotoSansSC-LICENSE.txt.
Source: https://github.com/notofonts/noto-cjk/tree/main/Sans/SubsetOTF/SC
The original Droid Sans Fallback font is kept for provenance; it lacks the Latin glyphs used in the UI.

## r12 native canvas libraries and fonts

The unmodified FreeType and zlib libraries below match those on the inspected KPW3 KOReader installation (ELF32 ARM EABI5 soft-float, GLIBC_2.4 imports). KDash bundles its own copies, copied to the executable session directory; no running KOReader instance is required.

- `libfreetype.so.6` SHA256 `5b2d001dbb15c69b93a1ec776954f15c7b89a3d572ca3f3235fc0aeb7ed30ec2`; license `FreeType-FTL.txt`; source https://github.com/freetype/freetype.
- `libz.so.1` SHA256 `5f34b46fdf855d13e2e7183dae75cf83cbe76f830a41b1707fcf9365d5301e77`; license `zlib-LICENSE.txt`; source https://github.com/madler/zlib.

This software uses the FreeType Project (https://freetype.org). All rights reserved. Fonts: Source Han Sans CN Medium and Kumbh Sans fixed 500/600 instances generated from official variable fonts; OFL notices are in assets/fonts. Fixed instances retain the upstream families without outline redesign. Original variable files are build inputs; axes and source URLs are documented in scripts/prepare_fonts.py.
