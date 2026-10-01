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


## 2026-09-28: configuration readers and UpdateFeature admission

Found an uncovered writer: public `NVSDK_NGX_UpdateFeature` changed application/project metadata without the exported transition gate. Direct native Init captured path and metadata separately and could interleave with exported configuration publication. Immutable storage preserved pointer lifetime but did not exclude these writers.

The shared admission now exposes read/write leases. UpdateFeature acquires a nonwaiting writer before configuration access; direct D3D11/D3D12/Vulkan proxy Init holds a reader before the cached-success check through path capture and the SDK callback. Busy UpdateFeature returns NotInitialized; busy direct Init returns false. Exported delegated native calls retain their existing admission, avoiding nested exclusive entry. The optional DLSS-NR raw re-init holds a reader before consuming its one-time retry flag. No metadata mutex spans SDK callbacks.

Local actual-production-body checks: metadata suite 39 -> 123 (84 added), including application/project updates during path capture and native callbacks, a separate writer thread, exported transition rejection, cached Init under a writer, and retry after path/native exceptions across all three APIs. Negative controls removing either the UpdateFeature writer or the direct Init readers both fail at check 33. Affected routing 56, exported admission 590 and complete Init-chain 455 checks pass. Changed-line formatting only.

Scope limits: this prevents writer/read interleaving, not rollback after an admitted partially successful Init, per-device configuration storage, concurrent D3D11 direct Init, ordinary Evaluate shared-buffer ownership, or the optional DLSS-NR raw re-init bypass of native device lifecycle. The legacy metadata storage tests deliberately update the storage directly to verify retained pointer ownership; production public writers are tested separately. No game/GPU test, main merge or Release is claimed. Full Windows evidence follows after the code checkpoint.


### Next acceptance boundaries confirmed during 2026-09-28 review

- `NgxCore_D3D12_Init_Ext` still publishes paths and application identity before native/provider admission; the provider can reject after native Init succeeds. A generic cache-only rollback would not undo that native device state. Test same-device retries and an unrelated already-ready device against the actual native/provider registries, preserving partial cleanup ownership and avoiding stale global success.
- Every current `NVNGXProxy::GetFeatureCommonInfo` caller was enumerated: the three direct Init methods and optional DLSS-NR re-init now hold configuration read admission. Exported cores retain their exclusive gate. DLL-startup runtime-path discovery is a separate source of State paths and is not covered by this bounded writer/read fix.
- `Nvngx_FG::D3D12_EvaluateFeature` still accesses one static `_hudCopy` under shared operation/handle-reader admission, selecting `State.currentD3D12Device` despite immutable device identity already existing in the handle. `HudCopy_Dx12::Dispatch` mutates its heap counter, buffer, descriptor heaps and constants. Tests must cover same/different handles and devices, callback reentry, Release/Shutdown during use, and allocation failure.
- `Nvngx_DllProxy::D3D12_EvaluateFeature` has a function-static ring counter and provider-wide `depthCopy[2]`. Its buffer helper compares descriptors, not device identity, and immediately releases old storage on descriptor change. A CPU-only serialization fix cannot establish completion of queued GPU work; do not claim that it does. Device association, retirement/fence ownership and the scope of optional depth-copy behavior need explicit handling.
- `UpscalerInputsDx12::Init` only records the selected device when its input is active; it does not recursively call direct native Init. Direct proxy Init call sites are feature construction/Create/query paths, not internal private Init delegation. Preserve the distinction when modifying admission further.


### Final Windows validation: 7874959a

Code `7874959a3501c634ee7c71833408aae4ad5cc2c5` is pushed to Compatibility-fixes. Windows run `36371933325`, job `108769925846`, completed successfully: full DLL build, configured compatibility checks, package and upload. MSVC logs confirm 123 metadata / 56 native routing / 590 exported admission / 455 complete-chain checks. Format run `36371933427` succeeded; local changed-line formatter reported 4 files, 0 violations.

Artifact: `OptiScaler_Aurora_v1.0_20260928_compat_7874959a.7z`, Actions artifact ID `10949214531`, 234793969 bytes, API artifact digest `sha256:674eeecabdf57036e2bdb5afdc9f5d725617350ef3d6c8f8ced4ee6f6c88d12a`. The digest is the Actions artifact digest, not a separately computed inner 7z checksum. No Release/tag/main merge performed. This is a validated compatibility-branch checkpoint, not the finished release candidate.


## 2026-09-28: reject invalid device before publication

The next pre-admission failure case exposed missing null-device validation in the outer Init cores. NativeDeviceLifecycle rejects null, but outer D3D12/Vulkan adapters historically propagate NotInitialized specifically and preserve other optional-backend fallbacks; thus that lower validation is not an outer preflight. D3D11 also allowed a null request to reach native work and local initialization state. Path/application publication preceded these calls.

All 13 private Init variants now reject a null InDevice with InvalidParameter before copying feature info, publishing paths/metadata, calling native/provider code or updating local device/ready state. The shared public admission remains unchanged and delegated calls retain the same valid-device behavior. No blanket propagation of optional backend failures, validation of optional Vulkan loader callbacks, or change to the accepted non-null Init sequence is introduced.

Complete actual Init-chain checks increase 455 -> 598 (143 new): each of 13 null routes before and after a valid Init; unchanged path/metadata writes, SDK call counts, local ready flags and device identities; valid retry afterward. Before the fix the new test fails at check 389. Affected 590 exported admission and 32 path ownership checks pass. The path-only extraction harness starts at localFeatureInfo because it does not model device/result types; full entry validation belongs to the complete-chain suite.

This closes one invalid-request publication hole. It does not close partial native/provider success with a valid device, per-device configuration ownership or shared Evaluate/GPU-resource retirement. Full Windows validation follows after checkpoint publication.


## D3D12 ProjectID follow-through

The two D3D12 ProjectID variants published project metadata before their delegated Init_Ext result, unlike the previously fixed Vulkan variants. When the provider returned NotInitialized (or native/provider callback threw in Init_with_ProjectID), the failed request had already replaced project metadata. Move UpdateProject after a successful delegated result in both D3D12 variants. Preserve native argument forwarding, optional provider fallback and the existing result returned by Init_Ext.

Extended actual-body checks first reproduce failure at check 533. Complete-chain suite now has 626 checks (28 beyond the null-device checkpoint, 171 beyond the prior 455 baseline). D3D12 joins Vulkan for native/provider rejection and later successful retry; all four ProjectID variants are also tested against native/provider exceptions and retry. Metadata storage checks remain 123 passing. Other application/path fields and valid-device partial native/provider state are still a separate transaction boundary; this is not a claim of full rollback.


### Remaining transaction issue: reproduced with native admission

A separate local reproduction on 2545abee extracts the real D3D12 Init cores and wrappers, substitutes the production NativeDeviceLifecycle for the complete-chain harness's native admission stand-in, and holds RunOperation on device A. Init_Ext on new device B returns NotInitialized without a native callback, yet pathWrites and metadataWrites both advance; A remains ready, B remains uninitialized and currentD3D12Device stays A. This proves the remaining pre-publication/admission mismatch; it is NOT a passing correctness test or a claim of a repair. Provider calls and metadata/path publication counters remain stand-ins in this diagnostic harness.

Reproduction source/output retained in the task workspace under `work/ngx-init-transaction-repro/test.cpp` and `result.txt` (2026-09-28). Next implementation must prevent that rejected B request from changing active configuration, and also cover the distinct native-success/provider-failure case without discarding cleanup ownership or treating a native retry as a fresh SDK initialization. Avoid adding a racy CanInitialize precheck: admission and configuration commit need an owned transaction boundary.


### Combined Windows validation: 2545abee

Final code `2545abee6254452be381b165caa5528725a55c2a` includes null-device checkpoint `325e9aab` and the D3D12 ProjectID fix. Windows run `36373142939`, job `108773423640`, completed full DLL build, configured compatibility tests, packaging and artifact upload successfully; format `36373142954` passed. MSVC confirms 626 complete-chain / 590 exported admission / 32 path / 123 metadata checks. The 171 additional complete-chain checks pass both locally and on Windows.

Artifact `OptiScaler_Aurora_v1.0_20260928_compat_2545abee.7z`, id `10949499712`, 234786717 bytes, Actions artifact digest `sha256:0a8ccade6fca41116082d8ada2d2b132df672b8e0ba5a9f9af074de9fd101d82` (not an independently calculated inner-archive digest). Both source checkpoints are pushed. No game test, main merge or Release was performed. Remaining transaction reproduction above and ordinary Evaluate resource ownership remain release gates.

## 2026-09-30 native partial-shutdown quarantine

NativeDeviceLifecycle previously restored ready status after a native Shutdown failure or exception. SDK failure cannot prove that no internal state was released. It now invalidates selected device readiness before entering shutdown and retains failed cleanup ownership. Repeat Init returns busy for a cleanup-owned but not-ready device; it cannot turn a partial close into cached success. Device-bound operations reject that device; legacy operations without device identity reject when any owned device is quarantined. An explicitly identified unaffected device remains usable. Successful shutdown removes ownership and allows a fresh Init.

Focused device test first failed at check 10 against the old implementation. Updated device checks pass 62 (previously 55), actual cached native operation checks pass 387 (previously 348), including Create output clearing, and actual exported/native shutdown routing passes 56. Updated old assertions which incorrectly expected readiness after native shutdown failure; feature-drain rejection before native shutdown still preserves native readiness. Cleanup retry through actual exported routes remains covered. This does not establish native/provider Init rollback or GPU-buffer retirement; those remain separate release gates. Full Windows validation follows after push.
### Depth-copy failure propagation

A second focused defect was reproduced in Nvngx_DllProxy::D3D12_EvaluateFeature: it ignored CreateBufferResource's bool result, then used a retained non-null pointer even if preparation failed (for example, a missing current device). Evaluate now requires both successful preparation and a non-null buffer before barriers/copy/parameter substitution. Otherwise the original game depth stays unchanged and the provider still receives Evaluate. DLL-boundary actual-body tests expand 69 -> 77, covering success/failure crossed with absent/retained buffer; old code fails at check 73. CPU stand-ins verify dispatch only, not GPU resource lifetime. Full per-handle/device association, concurrent ring access and queued-resource retirement remain open.
### Next resource audit: concrete source boundaries

Read HudCopy_Dx12::Dispatch next: its CreateConstantsBuffer failure exits after resource transitions have already been recorded, without the success path's restoration barriers. Its _buffer is created only when null; later descriptor/size changes are not checked at this call site. Investigate these with actual Dispatch-body failure injection before changing behavior. The shared singleton, one constant buffer and two descriptor heaps still need CPU admission AND GPU completion ownership; do not treat serialization or keeping COM references alone as proof against queued descriptor/constant overwrites. NvngxFGMakeDepthCopy defaults false; FGHudCutoff defaults 0, although game quirks can enable HUD processing. Do not globally disable game quirks merely to close an audit. Remaining partial Init/configuration ownership is unchanged by the native shutdown quarantine.
### Final Windows validation: fa9c2b67

Both code checkpoints are pushed: a6c03d89 (native failed-shutdown quarantine) and fa9c2b67 (depth-copy failure result). First Windows run 36679720393 / job 109772304558 and format 36679720383 passed. Final Windows run 36679955083 / job 109773018666 and format 36679955060 passed full DLL, compatibility checks, runtime inventory, package and upload. MSVC confirms 62 native-device, 387 cached-operation, 56 shutdown-route and 77 DLL-boundary checks. No game test was performed for these lifecycle changes; the earlier user's Witcher runtime validation is distinct.

Artifact OptiScaler_Aurora_v1.0_20260930_compat_fa9c2b67.7z, id 11082165732, 219576748 bytes, Actions artifact digest sha256:a3137c1315adb6e7de878f8c3964a67dc1e696b0f69ec90dbfe8cd26d7789a3c (not a separately downloaded inner archive checksum). Next work is the concrete HUD failure/resource boundary above and combined Init partial-success ownership. Main synchronization has not occurred; authorized once these release gates are resolved or explicitly scoped safely.
## 2026-10-01 HUD constant-preparation failure

Actual HudCopy_Dx12::Dispatch extracted-body failure injection confirms that CreateConstantsBuffer failure returned with present and hudless in NON_PIXEL_SHADER_RESOURCE and internal buffer in UNORDERED_ACCESS. The already-recorded transitions were not restored. Fix adds all three restoration barriers before returning false; it does not dispatch compute or overwrite the game output on failure. Nine combinations of incoming present/hudless states exercise failure followed by successful retry using the same resources. 225 assertions pass locally; unmodified code fails at check 7. CPU command/resource stand-ins track transition states and copy preconditions; they are not a GPU fence/concurrency test. Added to Windows CI. Shared object concurrency, constant/descriptor reuse, resize handling and pending-GPU retirement remain distinct open work.
### Final HUD checkpoint validation

Code afe68e0e4626e6f68d97c56c01174b4baa2a6f9e is pushed. Windows run 36751966194 / job 110012578306 and format 36751966124 succeeded; full DLL, runtime inventory, compatibility tests, package/upload passed. MSVC confirms 225 HUD Dispatch failure-state checks. Artifact id 11115591131, OptiScaler_Aurora_v1.0_20260930_compat_afe68e0e.7z, 219577380 bytes, Actions digest sha256:2f20adfa8c91b340551c20c0a15087dfd32e90b78908a73802036888d8e8586a. Keep exact build-generated filename; its date reflects runner naming, while this continuation is recorded as 2026-10-01 in user timezone. No new GPU/game tests, aurora merge or Release. Next: resource resize/device/generation ownership and GPU retirement, plus admitted Init partial-success configuration. The failure-state restoration and native shutdown quarantine are complete checkpoints; do not reimplement them.
## 2026-10-01 HUD incompatible-copy guard

Actual Dispatch-body tests reproduce reuse of the first HUD buffer after present descriptor changes (old code fails at assertion 237). Before CopyResource, compare dimension, width, height, array/depth size, mip count, exact format and sample count/quality. Mismatch skips this optional HUD pass without resource transitions/copy/dispatch and retains the old resource, because queue completion is not owned here. Matching descriptors resume the existing path. Exact format equality is deliberately conservative; no inference about compatible typeless format families is made.

225 -> 345 focused assertions pass, adding eight one-field descriptor changes and return-to-original retry. This prevents invalid copies but is not automatic resize recovery: while the singleton retains the original allocation, HUD fixup remains skipped for the new descriptor until an appropriate context rebuild (currently no automatic rebuild here) or process restart. Framegen provider Evaluate still executes. Do not label full resize handling/GPU retirement complete. Device mismatch, shared CPU/GPU use and combined Init transaction remain open.
### Incompatible-copy checkpoint validation

6e7d63c5 is pushed and fully validated: Windows run 36847081165 / job 110319679594 and format 36847081239 succeeded, including full DLL, compatibility checks, runtime inventory, package/upload. MSVC confirms 345 HUD Dispatch checks. Artifact OptiScaler_Aurora_v1.0_20261001_compat_6e7d63c5.7z, id 11154257790, 219572042 bytes, Actions digest sha256:969a1530f3afce515f2a9847fb7e2f431859eb4fd6d459537dd6cad2ebb000c5 (not a separately downloaded archive checksum). NGX and FSR callers were inspected: both continue their FG flow after optional HUD Dispatch returns false. Automatic resize recovery, device association, shared CPU/GPU state and partial Init transactions remain open; no main merge or Release. Do not repeat the completed incompatible-copy guard.