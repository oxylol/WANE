# Third-party licenses

CLAUDE.md rule 10: nothing enters the repo from outside it except what is listed here. Every visual and audible thing in WANE is authored from source in this repository. This file lists the only external code, tools and fonts the project uses, with their licenses. Adding a line here requires an ADR.

## Shipped with the game

| What | Version | License | Where | Why |
| --- | --- | --- | --- | --- |
| Godot Engine | 4.7.2-stable (`.godot-version`) | MIT (Expat), plus the third-party components below | not vendored; the pinned official binary and export templates | The engine (BUILD.md section 13, ADR-0001) |
| godot-cpp | `godot-4.5-stable`, commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` (`native/.godot-cpp-version`) | MIT (copyright Godot Engine contributors; includes the GDExtension interface header and API description, also MIT) | not vendored; cloned by `ci/setup_godot_cpp.sh` into the git-ignored `native/godot-cpp` and compiled into the native library `native/bin/libwane.*` | C++ bindings for the native extension (BUILD.md section 13, ADR-0021) |
| Godot's embedded default font | as embedded in Godot 4.7.2 | SIL OFL 1.1 | inside the engine binary | Used only by the F3 debug overlay and tool output (contact-sheet labels). Never player-facing; the shipped UI font gets its own row and ADR in Phase 2 |

### Components inside the Godot binary

Godot 4.7.2 bundles 102 third-party components under 19 licenses (from `Engine.get_copyright_info()` and `Engine.get_license_info()`). Every export must show them: the shipped game includes a credits and legal screen that prints `Engine.get_license_text()` and the full component list from those two calls (tracked for the Phase 2 UI work; see PROGRESS.md).

| License | Components |
| --- | --- |
| Apache-2.0 | Android Open Source Project, ProcessPhoenix, Arm ASTC Encoder, Basis Universal, Embree, DroidSans font, KTX, Manifold, Mbed TLS, metal-cpp, Minimal PCG32, OpenXR Loader, RVO2, SPIRV-Reflect, Swappy, Vulkan Headers |
| Apache-2.0 or Expat | SPIRV-Cross |
| BSD-2-Clause | mingw-std-threads, YUV2RGB |
| BSD-3-Clause | Open Dynamics Engine, ANGLE, etcpak, libbacktrace, OggVorbis, OggTheora, WebP codec, MiniUPnP, libjingle, SMAZ, PCRE2, hidapi, TinyEXR, V-HACD, Zstandard |
| BSD-3-Clause and Expat | NVidia FXAA 3.11 (simplified by Simon Rodriguez) |
| BSD-3-Clause and IJG | libjpeg-turbo |
| BSL-1.0 | Clipper2 |
| CC-BY-4.0 | Godot Engine logo |
| CC0-1.0 | Linux AppStream metadata file |
| CC0-1.0 and Apache-2.0 | glad |
| Expat (MIT) | Godot Engine, Betsy, Chipmunk2D joint constraints, Jolt Physics, JNLM denoiser, Robert Penner's easing functions, Intel ASSAO, TAA resolve, SMAA, AccessKit, AMD FSR 1 and 2, Brotli, CVTT kernels, D3D12 Memory Allocator, DirectX Headers, doctest, ENet, GamepadMotionHelpers, Graphite, meshoptimizer, bcdec, reflection-probe filtering, FastLZ, FastNoise Lite, NVAPI excerpt, OK Lab, PolyPartition, QOA, msdfgen, SPIRV-Headers, ThorVG, ufbx, volk, Vulkan Memory Allocator, Wayland core protocol and protocols, Wslay, xatlas |
| Expat and Apache-2.0 | Grisu2 float serialization |
| Expat and Zlib | Bullet |
| FTL | FreeType |
| HarfBuzz | HarfBuzz |
| MPL-2.0 | CA certificates |
| OFL-1.1 | Inter, JetBrains Mono, Noto Sans, Open Sans, Vazirmatn fonts |
| Unicode | ICU |
| Unlicense | r128 |
| Unlicense or Expat | SMOL-V, stb |
| Unlicense or MIT-0 | dr_libs |
| X11 | Mesa Wayland protocols |
| Zlib | libpng, MiniZip, tangent-space normal maps, Recast, SDL, zlib |
| glslang | glslang |

## Development only (never shipped in an export)

| What | Version | License | Where | Why |
| --- | --- | --- | --- | --- |
| gdUnit4 | 6.2.2 (tag `v6.2.2`, 2026-10-07) | MIT, copyright (c) 2023 Mike Schulze | `addons/gdUnit4/`, vendored without its own `test/` folder and without the upstream agent guidance file `src/asserts/CLAUDE.md` (it contradicts this project's rules) | Unit test framework (CLAUDE.md, ADR-0001). Must be excluded from every export preset when presets are added |
| gdtoolkit (gdlint, gdformat) | 4.5.0 | MIT | `tools/requirements.txt` | Lint and format gate |
| gdtoolkit dependencies: lark, PyYAML, docopt-ng, radon, mando, colorama, six, regex, setuptools | see `tools/requirements.txt` | MIT (lark, PyYAML, docopt-ng, radon, mando, six, setuptools), BSD-3-Clause (colorama), Apache-2.0 (regex) | `tools/requirements.txt` | Lint toolchain |
| SCons | 4.10.1 | MIT | `tools/requirements.txt` | Builds the native extension (`ci/build_native.sh`, ADR-0021) |
| numpy | 2.5.3 | BSD-3-Clause | `tools/requirements.txt` | Art and audio builds, coverage maths |
| Pillow | 12.3.0 | MIT-CMU (HPND) | `tools/requirements.txt` | Art build output, contact-sheet post-processing |
| CairoSVG and its dependencies: cairocffi, cffi, pycparser, cssselect2, tinycss2, defusedxml, webencodings | see `tools/requirements.txt` | LGPL-3.0 (CairoSVG), BSD-3-Clause (cairocffi, pycparser, cssselect2, tinycss2, webencodings), MIT (cffi), PSF-2.0 (defusedxml) | `tools/requirements.txt` | Vector rasterisation in the art build (Phase 2); never linked into the game |
| libcairo (system library used by cairocffi) | distribution package | LGPL-2.1 or MPL-1.1 | build machines only | Same as CairoSVG |

## Explicitly not used

No asset packs, no downloaded textures, no sounds or sample libraries, no raster image generators, no middleware, and no fonts beyond the rows above.
