# Incremental compatibility audit — 2026-09-25

## Scope and reproducible cutoffs

The official comparison is `a4890db5b3c7c6918f4b35d0fd3318b42e2ccc66..20d9d147a4334a49a99d67d235ad7915e0d6d846`, 51 commits including merges. Source: https://github.com/optiscaler/OptiScaler/compare/a4890db5b3c7c6918f4b35d0fd3318b42e2ccc66...20d9d147a4334a49a99d67d235ad7915e0d6d846 . The `official-audit/master` local ref preserves this snapshot. The remote called `upstream` is a fork, not the official repository.

This is an inventory cutoff with selected source-reviewed ports, **not a claim that every intervening redesign has been accepted or fully audited**. Deferred groups below remain work items. User requests no real-game tests; CPU tests and build success must not be presented as game verification. Work stays on Compatibility-fixes; no installer revival, release or replacement archive.

## Adopted changes and adaptations

All abbreviated source hashes below refer to the official repository.

| Source | Change | Aurora decision |
| --- | --- | --- |
| `f08115a5` | UpscaleEnd missing output resource | Return before querying a null output, including successful parameter lookup returning null. |
| `08880f88` | HUD format groups | Two unclassified formats no longer compare equal through group -1. Also reject DXGI_FORMAT_UNKNOWN even against itself. |
| `ce9ab02f` | HUD copy rectangle | Bound each axis independently; prevent unsigned subtraction underflow and copies outside the destination on mixed-size axes. |
| `b9b0bec9` | HUD copy barriers | Use the caller-supplied current state for both transition and restoration instead of cached resource state. |
| `07d360b8` | Resource candidate filtering | Reject array/depth, MSAA, depth/stencil, video, deny-SRV and acceleration-structure resources early. Also guard null before GetDesc. |
| `71199dcb` | sora_2nd.exe | Add official FSR2 DX11 input / no DXGI spoof quirk. |
| `6ec6681d` | fbcfirebreak.exe | Add official no DXGI spoof quirk. |
| `20d9d147` | controlresonant.exe | Add official no DXGI spoof quirk. |
| `f4e314aa` | Generated build headers | Replace fixed 1.5-second sleep with bounded IO retry; explicit repo path and ASCII output. |
| `877e658b` | BuildInfo translation unit | Isolate changing timestamp/commit metadata from ordinary resource.h consumers. Preserve Aurora product name/version/fork suffix and compile metadata into the Windows resource. |
| `1560d55d`, `aa0119fc` | setup-msbuild v3 | Apply to all five existing build workflows; retain incremental clang-format 20 policy. |

The BuildInfo change reduces dependency-driven recompilation; no build-time or game-FPS improvement is measured here. The game quirks are upstream policies, not locally verified behavior in those games. Native SL1 protection, DualFeature and 6X implementation are unchanged.

## Deliberately deferred official changes

- `4c682650` / `26aca741`: skipping repeated FG ResizeBuffers was evaluated, then **removed from the proposed port**. Zero width/height means current window client size, not existing buffer size. Also a fullscreen transition can require ResizeBuffers even when explicit dimensions match. The upstream IsSame dimensions/format/count/flags helper does not prove that no transition is pending. Keep existing behavior until transition-aware tests/design exist. Contract: https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiswapchain-resizebuffers . No resize optimization remains in this checkpoint.
- HUD/resource-tracker chain (`9282dde1` through `93fbf1b2`, including intermediate/remedial changes): per-command-list bindings, descriptor heap caches, destruction notifications, DX11 HUD tracking and lock changes are interdependent. Aurora does not even have all upstream DX11 HUD files expected by `95a3f584`. Do not transplant an intermediate lock removal or cache patch as a standalone performance fix. This group was inventoried and selected diffs inspected, not completely migrated.
- XeFG present/resize locking (`3bc197c2`, `34917612`, `9df3ed0c`): coordinate with Aurora's existing interop queue and device lifecycle work before porting a second overlapping synchronization scheme.
- `d794b18d` / `b52cf663`: upstream input-hook transaction redesign differs from Aurora's existing out-of-state-lock module/export discovery. It needs a trampoline-publication/lock-order review; it is not evidence the previous Aurora fix should be overwritten.
- `3bae8a59`: moving UpscaleEnd under ScopedSkipHeapCapture affects capture ordering and belongs with the tracker migration.
- `6ded74bf`: source review found commonization of already-duplicated preserved-swapchain handling across the three FG outputs, including a release-until-zero pattern. Refactoring it alone is not a demonstrated crash fix.
- `2e5a8770`: do not import upstream provider defaults and GPU/Streamline policy wholesale. Other shader/API changes, Vulkan extensions, reprojection and cosmetics are outside this bounded repair batch.
- `e968ce8c`: do not move clang-format to 22 or reformat historical Aurora code merely to track upstream formatting.

## Branch and fork checks

Public unauthenticated REST became rate-limited partway through fork inspection; affected queries were retried using the authenticated connector. Failures are not interpreted as no changes. Default-branch snapshots plus relevant PR branches were checked; this is not an exhaustive search of every GitHub fork.

| Repository / branch | Snapshot / finding |
| --- | --- |
| Official release-0.9 | `121a87a9f2a0f63a497fd9e0dc19bfb998c7f46e`; includes the same game quirks, no duplicate port. |
| Official unify-upscaler-inputs | `97a18c36331418f74dc4b60dde178ade32e2820a`; latest commit 2024-10-31, no new work in this interval. |
| Official reprojection | `4ad338f95432fa193456075539dfa66e229e05d2`; active separate feature development, not merged into stability work. |
| grim-susemi/OptiScaler-Susemi | `8f387acad612e7ce8ea0b4811823d08f31e204db`; default branch last changed Sep 7. |
| wilsjo2/OptiScaler_DLSSNR | `973761621353b99bee3dc7d4bb27b117fef2644f`; default Sep 3; no repeat of old PR1157 work. |
| y4my4my4m/OptiScaler_DLSSNR_Multipass_MFG | `7b7220bbb4994a9c8ae60cfc75a44cb67995efb8`; default Sep 5. |
| gprocunier/OptiScaler | `7233fc0cc8e96281572fc873fbea01d615508d1d`; default behind official, prior PR1089 overhaul remains deferred. |
| Rygtx/OptiScaler, Gnatzelle/OptiScaler | Same default HEAD as official `20d9d147`. |
| gengar-maker/OptiScaler | Latest default `6ded74bf`, official sync. |
| IppearPeng/MultiScaler | Latest default `aa0119fc`, official sync. |
| deYangar/OptiScaler_chs | `6e1f2d6d564aea305d2f93f7434bea67e2431969`, upstream-sync commits. Different-history compare unavailable; commit inventory is not a full semantic audit. |

Relevant PRs were checked independently of old default branches:

- https://github.com/optiscaler/OptiScaler/pull/1163 (jackra1n, `9bfe5bf70ff0e8512d29cc34ca0d3094f0adc462`): DXVK/vkd3d/Proton overlay route, discussion still requires backend-specific testing; not a Windows Mihoyo crash fix.
- https://github.com/optiscaler/OptiScaler/pull/1161 (Astyyyyy, `fe6ac5d73be014ac460828d775ebd8de0603e03d`): large Vulkan extension/RADV functionality, deferred.
- https://github.com/optiscaler/OptiScaler/pull/1174 (krispy1337, `9e6b39e4b061ac2e6e72cc4bf538de0f2e82c961`): large overlapping closed/superseded fix bundle; use individually reviewed official changes instead of duplicating it.
- https://github.com/optiscaler/OptiScaler/pull/1178 (hammadxcm, `1e354a1c53b46b2f689f04965f6d95f086a4ea5a`): redundant null checks around delete, no needed behavioral change.

Genshin bridge (`AizawaHikaru233/genshin_fsr_brigde`) has 100 commits from the prior `bc2044285bfcdf3b51b89e03762af4982d9151c1` to `b31bf20b31724f149a4bef47b867be296491dead`. Inventory identifies bridge-owned shutdown/teardown work (`bc989234`, `04d0273d`, `e0d3d355`, `108e17d4`), readback/state-tracking optimization and layout support. These are candidates for a separate source-level bridge audit, not code automatically portable into Aurora. No bridge source is imported this round. Issue1122 had no new comments; ZZZ issue1084 supplies no new evidence that the user's RTX40 error11008 is fixed.

## Validation and remaining scope

- `tests/test_upstream_resource_guards.py`: 110 executable CPU checks. Complete production format helper, actual resource-classification/output-lookup prefixes and actual rectangle/barrier statements are compiled; later graphics work is represented by stand-ins. Covers unknown/unlisted formats, null/shutdown resources, unsupported texture types, 81 mixed-axis sizes, current versus cached state, and missing/typed/fallback output parameters.
- Negative controls use temporary copied sources: removing UNKNOWN-format rejection fails check1; replacing the current barrier state with the old cached state fails check105. Production sources were not corrupted.
- BuildInfo: ordinary resource.h consumer compiled without generated headers; Release BuildInfo compiled with test headers and confirmed `OptiScaler Aurora v1.0` and Aurora version/fork/commit/date fields. No FPS benchmark claim.
- Focused incremental formatting and the full Windows DLL/RC/package/MSVC test build are required before the validation section is closed. Build result will be appended after Actions completes.
- Previous unfinished provider device/generation ownership, outstanding FFX/Combo feature cleanup and native Init transaction boundaries remain documented in PROVIDER_TRANSITIONS_20260924.md. This audit does not close that work or justify merging the unfinished branch into aurora.
