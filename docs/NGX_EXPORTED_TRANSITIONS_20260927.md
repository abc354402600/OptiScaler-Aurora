# Exported NGX transition admission — 2026-09-27

## Defect and repair

The old thread-local `_skipInit` flag propagated delegated Init state to any SDK callback reentering a public Init on the same thread. Such a callback could skip native Init/path publication as if it were an intended internal delegation. Independently, exported Init wrappers could interleave global metadata/device updates across APIs, and exported Shutdown could enter during an exported Init before provider-level admission was acquired.

All 19 public D3D11/D3D12/Vulkan Init and Shutdown variants now enter one shared, nonwaiting transition gate before their private core executes. Callback reentry and overlapping exported transitions return NotInitialized without entering the core. Lease destruction releases admission after normal returns, failures and exceptions; no mutex is held across SDK calls. An inline shared gate also excludes calls across translation units.

Internal delegation is now explicit through file-local NgxCore functions with a `delegated` parameter. SDK callers can only reach the original public ABI, which always enters the gate and starts with `delegated=false`. The thread-local skip flags and scope objects are removed. The original native/provider return policy, argument overrides, and cleanup order are preserved in this structural step.

## Focused checks

- 590 checks execute all 19 actual public wrappers, including every pair of nested Init/Shutdown calls, cross-thread rejection, cross-translation-unit sharing, error return and exception unwind. SDK/core bodies in this fixture are counted stand-ins.
- 388 checks execute all 13 complete production Init chains (private cores plus public wrappers), with fake SDK, provider and state services. Each normal fresh chain calls native Init once and publishes paths once. Reentry from native and delegated provider phases cannot add path/metadata writes or native/provider calls. Exceptions release outer admission.
- Updated existing path ownership suite: 32 checks, now passing explicit internal delegation rather than a thread-local flag.
- Actual shutdown-body regression: 56 checks with the new gate and private entry functions.
- Metadata ownership regression: 39 checks.
- Two in-memory negative controls are rejected: returning success on busy admission, and incorrectly starting another native Init on an internal delegated call. No production files were mutated for negative controls.

The new complete-chain suite is part of the full Windows build workflow. The 590-wrapper suite replaces the old 24 checks of the removed thread-local scopes; do not count both as current coverage. No unrelated installer suites were run.

## Remaining transaction boundary

This gate serializes exported transitions only. Ordinary Evaluate, direct native/provider calls and independent metadata consumers retain their existing admission. Therefore a provider/native busy result discovered later in an already-admitted Init can still follow earlier path/metadata publication. Direct proxy readers still acquire paths and metadata separately. An admitted partial failure is not automatically rolled back by this patch, and global early-success flags are not a substitute for per-device readiness.

Next: join the outer transaction to native/provider admission without thread-local bypass or locking across SDK callbacks, and publish an owned combined configuration only at the appropriate commit point. Preserve cleanup ownership after partial native success rather than pretending failure erased SDK state. Then address shared HUD/depth buffers and concurrent ordinary Evaluate. These are explicit outstanding items; this checkpoint does not meet the aurora synchronization gate or prove a Witcher/ZZZ crash fixed in-game.

No installed game, runtime deployment, driver profile, SL1 protection, MFG multiplier policy or installer was modified. Real-game testing remains deferred as requested.

## Additional transaction consumers reviewed

`inputs/NVNGX.cpp::NVSDK_NGX_UpdateFeature` separately writes application/project identity. It is not covered by this Init/Shutdown gate. A later combined-configuration design must account for this writer instead of silently rolling back its newer update. `NVNGX_Proxy.h` direct InitDx11/InitDx12/InitVulkan and `dlssnr/DlssNr_Proxy.cpp` read paths and application metadata separately. Logger and other upscaler inputs also consume metadata; a global mutex held across SDK callbacks would therefore be inappropriate.

The later failure matrix must distinguish rejected admission (no new side effects, fixed here for exported transitions) from an admitted operation that partially succeeds in native code (cleanup ownership must survive). Current D3D12 global early-success flags and Vulkan ProjectID publication after delegated failure remain within that second-stage review.

## Windows checkpoint validation

Code `c589c3b477afa7daea85dfd45778a42b2d76573c` is pushed. Full Windows build/test/package/upload run [36284675798](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/36284675798), job 108523054982, and format run [36284675823](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/36284675823) succeeded. The Windows log confirms 590 wrapper, 388 complete-chain, 32 path, 56 shutdown and 39 metadata checks. Public Init/Shutdown signatures were also compared against 0b96b32d: all three APIs retain their public signatures.

Artifact `OptiScaler_Aurora_v1.0_20260927_compat_c589c3b4.7z`: id 10919943631, 234788713 bytes, GitHub artifact digest `sha256:ebd72e36136002bc730d410cc54614ba06771636499179fb66a6eac4b8691908`. This is compilation/CPU evidence, not a Release or in-game verification.

## Admitted failure follow-up

Vulkan Init_ProjectID_Ext previously called UpdateProject even when its delegated Init_Ext2 returned failure. Init_ProjectID reaches the same path. Added a success check before project identity publication. This prevents a failed request from overwriting ProjectId/engine information; it does not roll back earlier application/path publication or undo partially initialized native state.

The complete-chain suite now has **400** checks: 12 new assertions cover both ProjectID entry variants, native-busy and provider-busy failure, unchanged project metadata/no global Vulkan success flag, and a subsequent successful retry. The new fixture failed at check 390 against the preceding production code, then passed after this fix. This provides a direct before/after reproduction rather than a source-string-only assertion.

## Final follow-up validation

Final code `7efb6022da019e06fab8b9759d6d3b0d39cde852`: Windows [36302276941](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/36302276941), job 108572025280, and format [36302276928](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/36302276928) passed. Full DLL compilation, configured compatibility tests, package and upload completed successfully. MSVC confirms 590 exported admission, **400** complete Init-chain, 32 path, 56 shutdown and 39 metadata checks.

Artifact `OptiScaler_Aurora_v1.0_20260927_compat_7efb6022.7z`: id 10925534199, 234787629 bytes, GitHub artifact digest `sha256:c50e187cbd17b28ed3f5c7c09b1f510e419a2b98ad7b408075f430e8ff02baaf`. No main-branch merge, Release or game test occurred.

## Global success-flag follow-up

The legacy D3D12/Vulkan global initialized flags could return success before checking replacement-provider readiness. D3D12's Init and ProjectID wrappers also bypassed the shared core; Init_with_ProjectID could skip a different device because it checked only the global flag.

The final local-state fast path now follows provider Init admission in D3D12 Init_Ext and Vulkan Init_Ext2. D3D12 wrapper shortcuts are removed so the shared core makes the device-aware decision. Provider Init already handles successful repeats without a second SDK Init; native API/device admission continues to handle its own successful repeats. The existing optional-unavailable-provider fallback is retained, and disabling D3D12 replacement does not create a required provider dependency.

The complete-chain suite adds **55** checks (400 -> 455): all nine D3D12/Vulkan variants with existing global state and a provider NotInitialized result, existing optional fallback, successful repeat, second-device initialization, selected local device identity and disabled D3D12 replacement. New checks failed at 402 before the fix and pass afterward. The 590 exported admission and 152 complete provider readiness checks also passed locally. These checks do not remove the remaining combined configuration/admission or shared Evaluate resource work.

## Readiness fast-path validation

Final code `087078d32c481ab247908c85181844c458a42a8d` passed Windows run [36310007830](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/36310007830), job 108593988482, including full DLL build, compatibility checks, packaging and upload. Format run 36310007829 passed. The MSVC log confirms 590 exported admission checks, **455** complete exported Init-chain checks and 152 provider Init readiness checks.

Artifact `OptiScaler_Aurora_v1.0_20260927_compat_087078d3.7z`: id 10929510178, 234792050 bytes, GitHub artifact digest `sha256:31c7421e4d505b1dcfa9189e3d01004a45220bd4d8d05d110fe2078b4cc8bcb2`. This remains a Compatibility-fixes build artifact. The user now authorizes a formal Release after the remaining code-validation gate; no Release was created in this checkpoint.
