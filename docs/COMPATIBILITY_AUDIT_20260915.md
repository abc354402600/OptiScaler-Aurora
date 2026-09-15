# Compatibility audit — 2026-09-15

Scope: compatibility branch based on Aurora `e1673a16`. No RC3 installer changes, no bundled runtime replacement, no game installation changes.

## Adopted

| Change | Evidence and scope |
| --- | --- |
| Typed DXGI export forwarding | Official [42dc02af](https://github.com/optiscaler/OptiScaler/commit/42dc02af3718b510c86a815eed8c9793cb6d95ca): replaces argument/return-losing wrappers and includes missing exports. Prerequisite for the next fix. |
| Remove DXGI export logging during startup | Official [b0dd6b02](https://github.com/optiscaler/OptiScaler/commit/b0dd6b02ce00cd2197493f358b127ec61579ee84), reported Windows 11 startup crashes. |
| Clear consumed GPU timing sample | Official [7168655f](https://github.com/optiscaler/OptiScaler/commit/7168655f75076c1493af0ba544a6e2832be51f5c). Corrects stale displayed costs; not an FPS improvement claim. |
| Older UE runtime path search | Official [bd6407da](https://github.com/optiscaler/OptiScaler/commit/bd6407daecf9fb93cba15a92cd6fc5c358c6f7a2). Correct Binaries ancestor handling; previously audited candidate now adopted. |
| Witcher-oriented captured-frame guard | Selective port of local experiment `9a7b0394`, restricted to Upscaler FG input. Match capture/dispatch/present epochs; explicitly suspend interpolation on invalid inputs while retaining resources and allowing capture to recover. Resume only after Reflex/constants succeed. Inactive/uninitialized paths are guarded. Does not change native SL1, the 6X unlock, or DualFeature policy. |
| NVNGX provider handle lifetime | Existing Release deleted the wrapper while its embedded mutex was still locked, through the public handle type. Registry ownership now retains entries before locking, retires them once, and unlocks before destruction. Queued evaluations/releases cannot dereference freed entries. Failed Create remains unpublished; failed Release stays recoverable. Applies to D3D12 and Vulkan provider handles. |
| Mixed DX11/DX12 GPU timing guards | [Issue 1124](https://github.com/optiscaler/OptiScaler/issues/1124) and source review identify a DX11 context being passed to a native DX12 timing implementation through void*. Guard timing calls by feature API/interop type. |
| Depth-plane SRV format | Narrow port from [PR 1157](https://github.com/optiscaler/OptiScaler/pull/1157), head `7543d143`: preserve `R32_FLOAT_X8X24_TYPELESS` for the depth-plane SRV instead of translating it into a DSV-only format. Other parts of the PR are not imported. |

## Mihoyo findings and deferred changes

- **Genshin:** [issue 1122](https://github.com/optiscaler/OptiScaler/issues/1122) and the bridge author's [comparison report](https://github.com/AizawaHikaru233/genshin_fsr_brigde/blob/main/assets/optiscaler-fg-regression/REPORT.md) describe AMD 9070 XT + Genshin 7.0 + FSR Bridge 2.1: August 15 works; August 25 onward fails. The report counts 4302 vs 11 DLSSG evaluations, followed by E_ABORT, with matching configuration/runtime. `882536fb` remains a bisect candidate, not a proven cause. The handle repair addresses an independently demonstrable lifetime bug; it does not establish that this report is fixed. Bridge HEAD reviewed: `bc2044285bfcdf3b51b89e03762af4982d9151c1`. No bridge installer or anti-cheat modification imported.
- **ZZZ:** [issue 1084](https://github.com/optiscaler/OptiScaler/issues/1084) reports an SL-input/FSR-FG visual regression subsequently confirmed fixed in a development build. Aurora already includes the ZZZ `IgnoreTagsWithoutHudlessForFG` quirk; no duplicate patch or speculative game-specific override added.
- **Star Rail:** [issue 994](https://github.com/optiscaler/OptiScaler/issues/994) describes short battle splash-art freezes, not an established new crash fix. No unsupported claim of resolution.
- **Active Streamline binding (PR 1157):** deferred. Aurora uses private bundled runtimes and disables OTA; delayed device initialization and plugin-function resolution ordering require separate validation. Its Vulkan framebuffer condition fix is already in Aurora.
- **DLSSG resource-transition rewrite ([PR 1089](https://github.com/optiscaler/OptiScaler/pull/1089)):** deferred. Large lifecycle/configuration change, incomplete author testing, and maintainer concerns. Not suitable for blind cherry-pick.
- **OptiInput loader-lock deadlock ([issue 1162](https://github.com/optiscaler/OptiScaler/issues/1162)):** plausible independent defect; the reported integration-lock rewrite is not a reviewed public patch. Remains follow-up work.
- Upstream high-MFG freeze-threshold fix `04bf0b08` is already represented by Aurora `a8d308b0`; do not duplicate it. New Vulkan interop hook changes and unrelated game quirks were reviewed but not imported as universal fixes.

## Verification and limits

- Local Windows C++ builds run the 22 captured-frame assertions and 14 provider-lifetime checks against production headers. These exercise frame epochs, invalidation, recovery eligibility, unknown handles, failed release/create, evaluation/release overlap, and concurrent repeated release.
- Full MSVC DLL compilation and both C++ tests run in `Build Aurora (No Signing)` for `Compatibility-fixes`. Artifact names include the commit prefix. Build status is reported separately after the actual run.
- clang-format is pinned to 20.1.8 and checks changed applicable C/C++ lines, with selector unit tests. Historical unrelated formatting debt is not rewritten. No old installer suites are rerun.
- No real GPU/game compatibility validation in this batch. Required: Witcher saved Dynamic MFG loading, Dynamic/manual 6X/FG toggles, sustained play and flicker comparison; Genshin bridge repro with unchanged runtimes; separate Star Rail/ZZZ logs if still failing.
- Handle registry does not redesign provider-global shutdown/concurrent provider selection or make arbitrary reuse of an already-freed public pointer valid. The outer NVNGX input router still reads public handle IDs before reaching the provider registry; stale-pointer rejection tests cover the registry/provider boundary, not every exported entry point. Those are separate lifetime boundaries requiring follow-up.
- The Witcher CPU crash signature at `+0x1f1f4ea` is not yet explained; builds and CPU guards cannot prove it resolved.

## Completed validation

Code checkpoint: `e2934a1e1675ca7a288bef2ddbf736aef1abf8f2`.

- [Windows MSVC build, 22 frame assertions, 14 handle checks, packaging and artifact upload](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34971712577): **success**.
- [Incremental clang-format CI and six selector tests](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34971712536): **success**.
- Local cumulative formatting review from `e1673a16`: 15 changed C/C++ files, zero edited-line violations. The local selector integration test initially lacked clang-format on PATH; adding the existing pinned tool to that process's PATH resolved the environment failure; all six passed.
- Artifact: `OptiScaler_Aurora_v1.0_20260915_compat_e2934a1e.7z`, 234771252 bytes as reported by the GitHub artifact API. The API reports the artifact archive digest `b6daee3b348a1624a760936d49662c5ae6d8919355ce28dfef9b0e5a2c38728f`; this is not a separately measured inner 7z/DLL hash.
- Subsequent documentation-only checkpoint records these results without rebuilding unchanged C++ code. No in-game validation result has been inferred from CI.
