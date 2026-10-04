<div align="center">

# OptiScaler Aurora

**RTX 40 Multi Frame Generation · DLSS Neural Rendering · Game compatibility improvements**

[简体中文](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/README.md) | **English**

[![Aurora v1.1.2](https://img.shields.io/badge/Aurora-v1.1.2-7c3aed?style=flat-square)](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1.2)
![DLSS 310.9.1](https://img.shields.io/badge/DLSS-310.9.1-76b900?style=flat-square)
![Streamline 2.14.1](https://img.shields.io/badge/Streamline-2.14.1-2563eb?style=flat-square)

**[Download v1.1.2](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1.2) · [Getting started](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/GUIDE.en.md) · [Compatibility](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/COMPATIBILITY.en.md) · [Release notes](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/RELEASE_NOTES_AURORA_V1_1_2.en.md)**

</div>

Aurora is a free, open-source community fork based on [OptiScaler](https://github.com/optiscaler/OptiScaler) and related community work. It offers upscaler replacement, frame generation and image tuning, with additions for RTX 40 MFG, DLSS Neural Rendering and game compatibility. It is not an official OptiScaler or NVIDIA release.

## v1.1.2 maintenance update

Adopts upstream XeLL module selection fixes and removes whole-export redirection from the normal loading path. Vulkan menus no longer offer unsupported FFX/Combo and Force XeLL options. Runtime versions and existing features are retained.

## v1.1.1 maintenance update

Fixes zero-size swapchain classification and adds scoped Control Resonant policies with configurable Streamline OTA handling. Runtime versions and v1.1 features are retained. See the [maintenance release notes](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1.2).

## Features

| Feature | What it provides |
|---|---|
| RTX 40 Multi Frame Generation | Up to **6X** in tested configurations through NVIDIA DLSSG/MFG. Availability depends on the game, GPU and runtimes. |
| DLSS Neural Rendering | Adjustable model resolution and other controls to balance image quality and processing cost. Experimental. |
| Upscaling and image tuning | OptiScaler's DLSS, XeSS and FSR backends, sharpening, presets and output scaling; support differs by graphics API. |
| Runtime Sync | Checks compatible DLSS/Streamline files, creates backups, synchronizes and verifies them. Preserves newer versions, native SL1 and unidentified groups. |
| In-game overlay | Press `Insert` to configure and save settings. |
| Recovery and diagnostics | Runtime checks and uninstall restoration help handle files changed by game updates. |

## What's new in v1.1

- **Updated runtimes:** DLSS SR/RR/FG 310.9.1, Streamline 2.14.1 and companion files. Optional Neural Rendering retains its 310.8 runtime / 2.13 plugin.
- **Downgrade protection:** newer game runtimes are preserved, as is native Streamline 1.x.
- **Initialization and shutdown fixes:** better handling of partial failure, cleanup ownership, failed handle creation and repeated releases.
- **Resource access guards:** frame-state, Reflex, HUD/depth-copy and device checks, plus CPU concurrency protection for shared objects.
- **Preserved defaults:** `DualFeature=false`. The discontinued RC3 automatic multi-entry installer is not included.

The release passed a full Windows build, configured compatibility checks, runtime inventory verification and archive validation. See the [full release notes](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/RELEASE_NOTES_AURORA_V1_1_2.en.md) for scope and limitations.

## Quick start

1. Download the `.7z` from the release page. Exit the game and extract **all files** beside its actual game `.exe`. Task Manager's **Open file location** can help identify it while the game is running; exit before installing.
2. Run `setup_windows.bat` and choose a proxy when prompted. `dxgi.dll` is a common starting point; use **`winmm.dll` for Neverness to Everness**. Do not deploy multiple Aurora proxies in one directory.
3. Check both setup and Runtime Sync results, launch the game and press `Insert`. Confirm basic operation before changing MFG and Neural Rendering options one at a time.

Setup finishing does not guarantee Runtime Sync succeeded. Investigate any synchronization warning. See the [guide](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/GUIDE.en.md) for setup, updates and removal.

## Game compatibility

**A working report does not establish support for every version, GPU or runtime transition.**

| Game | Evidence and remaining limits |
|---|---|
| The Witcher 3 | User reports normal RTX 4080 Laptop / DLSSG 310.9.1 / 6X operation. Loading, dynamic MFG switching and mild flicker have not had comprehensive regression testing. Preserve SL1 where actually present; not every game version uses SL1. |
| Neverness to Everness | Overlay and 6X operation were previously confirmed; `winmm.dll` is recommended. A community workaround exists for menu stutter, but MFG restoration in every menu is unconfirmed. |
| Onimusha: Way of the Sword; The Blood of Dawnwalker | Earlier 6X/Neural Rendering reports are retained as historical evidence, not fresh full-scene v1.1 validation. |
| Zenless Zone Zero | Component error `11008`, crashes and disappearing files remain unresolved reports. |
| Genshin Impact; Honkai: Star Rail | Bridge, runtime and game-version differences remain; not all environments are validated. |

See [compatibility details](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/COMPATIBILITY.en.md). Aurora does not bypass anti-cheat. Protected games may reject loading; these reports are not permission or a guarantee of safe use.

## Documentation and feedback

- [Documentation](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/README.en.md): guides, compatibility, release notes and developer references.
- [Changelog](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/Changelog.en.md) · [Configuration reference](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/Config.md).
- [Report an issue](https://github.com/abc354402600/OptiScaler-Aurora/issues) with Aurora/game versions, GPU/driver, proxy filename, FG input/output, reproduction steps and relevant logs.

## Credits and licensing

Thanks to [OptiScaler](https://github.com/optiscaler/OptiScaler), its authors, community forks and component contributors. The [upstream README archive](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/README.upstream.md) retains the original documentation and full acknowledgments. Old fork package instructions are archived separately, not presented as current installation guidance.

This project uses [GPL-3.0](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/LICENSE). Bundled components retain their own licenses; see [Licenses](https://github.com/abc354402600/OptiScaler-Aurora/tree/aurora/Licenses).
