# Aurora changelog

[简体中文](Changelog.md) | **English** · [Home](README.en.md)

## Maintenance (unreleased)

- Stop treating valid zero-size swapchain requests as overlay calls, including ordinary, DLSSG and wrapped routes.
- Add scoped Control Resonant swapchain and Streamline OTA policies while honoring explicit user settings.
- See the [October 4 maintenance record](docs/COMPATIBILITY_MAINTENANCE_20261004.md) for provenance and validation limits. These changes are not included in the published v1.1 package and do not establish in-game compatibility.

## v1.1

[Release](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1) · [Full notes and limitations](docs/RELEASE_NOTES_AURORA_V1_1.en.md)

- DLSS SR/RR/FG 310.9.1 and Streamline 2.14.1; optional Neural Rendering versions retained.
- Downgrade protection, preserving native SL1, newer versions and unidentified groups.
- Initialization failure, handle creation/release, shutdown and shared-object concurrency guards.
- Frame-state, Reflex, HUD/depth-copy and Vulkan query-result checks.
- Full Windows build, configured compatibility checks, runtime inventory and packaging passed. See notes for game-validation limits.

## v1.0

[Historical release](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.0).

Established Aurora's RTX 40 MFG, Neural Rendering, Runtime Sync and compatibility additions. Retained for history, not the current recommended release.

## Documentation refresh (2026-10-04)

Chinese default homepage with a separate English version, guides, compatibility navigation and v1.1 information. No DLL, release tag or published package changes.

## Upstream history

[Original OptiScaler changelog](docs/history/CHANGELOG.upstream.en.md). Upstream version numbers are separate from Aurora versions.
