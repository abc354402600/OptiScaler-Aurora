# Game compatibility and known limitations

[简体中文](COMPATIBILITY.zh-CN.md) | **English** · [Home](../README.en.md)

Current for Aurora v1.1.2. Historical game reports, code validation and unresolved symptoms are distinct; older reports are not fresh full-version validation.

v1.1.1 adds zero-size swapchain and scoped Control Resonant fixes. Runtime versions and the game-validation limits below remain unchanged. [Maintenance notes](RELEASE_NOTES_AURORA_V1_1_1.en.md).

v1.1.2 adds XeLL module routing and Vulkan menu capability guards, without new game-validation claims. [Notes](RELEASE_NOTES_AURORA_V1_1_2.en.md).

## The Witcher 3

On 2026-09-30 the user reported normal RTX 4080 Laptop / DLSSG 310.9.1 / 6X operation. The screenshot identifies DLSSG and the ratio, but not the loaded Streamline version.

- Use `dxgi.dll`; the DX12 executable is typically under `bin\x64_dx12`.
- Native Streamline 1.5.6 is still protected where present in older installations. Handle newer installations by their actual files; do not classify every Witcher 3 version as SL1.
- An earlier working route used DLSS upscaling with native game FG disabled, `FG Input → OptiFG (Upscaler)`, `FG Output → DLSSG`, and `FG Nvngx Replacement → None (Real DLSSG)`. Save and fully restart, enter a scene, then enable DLSSG and choose the ratio. This is historical guidance, not a requirement to change a newer working configuration.
- High-ratio loading, dynamic/fixed 6X switching and mild flicker have not had comprehensive regression testing. v1.1 adds related guards but does not establish that every symptom is resolved.

The [older setup screenshot](../images/witcher3_mfg_6x_setup.png) illustrates the previous interface and route.

## Neverness to Everness

Use `winmm.dll`; earlier reports associated `dxgi.dll` with an illegal-module warning. Overlay and 6X operation were confirmed, not every update or menu path.

A community NVIDIA Profile Inspector per-game setting reportedly alleviates character/gacha menu stutter. That does not prove menus resume 6X. Aurora does not change global driver settings. The [original investigation (Chinese)](NTE_ZZZ_COMPATIBILITY.md) retains the evidence and instructions. `Run inside the upscaler` is not recommended here.

## Zenless Zone Zero, Genshin Impact and Honkai: Star Rail

ZZZ component error `11008` and disappearing-file reports lack matching versions/logs and remain **unconfirmed as fixed**. They do not independently establish an MFG fault or a specific blocking mechanism.

Not all bridge versions, game versions and FG routes for Genshin/Star Rail have been tested. Generic lifecycle fixes do not establish universal bridge compatibility. Reports must distinguish upscaler input, FG input and FG output.

## Other recorded configurations

| Game | Historical report | Boundary |
|---|---|---|
| Onimusha: Way of the Sword | Working 6X and Neural Rendering | Keep `DualFeature` off due to reported corruption; not a new comprehensive v1.1 test. |
| The Blood of Dawnwalker | DLSS 5 and RTX 40 6X working together | Not a guarantee across hardware, versions or scenes. |

## v1.1 validation scope

Full Windows compilation, configured compatibility checks, runtime inventory, downgrade protection and archive verification passed. No new comprehensive game test was scheduled.

HUD/depth processing is skipped for mismatched resources. Full automatic rebuilding, GPU completion/retirement and global initialization rollback remain follow-up work. Incomplete experiments were withdrawn. See the [release notes](RELEASE_NOTES_AURORA_V1_1.en.md).
