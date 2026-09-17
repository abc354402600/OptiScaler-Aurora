# Native NGX export-table publication — 2026-09-17

The native module loader wrote `_module.dll` before resolving the export table. Another caller could see a nonnull DLL, skip initialization and read partially populated fields. Parallel loaders could also mutate the same table. This is distinct from replacement-provider object publication already fixed earlier.

The native loader now builds a private NvngxModule and resolves all exports before publishing it once, using the existing ProviderPublication helper. Every public accessor acquires the published table or reads an immutable empty table. The module/table is never replaced while callers use it. Loading and export resolution run without a lock held across external callbacks; a concurrent/reentrant InitNVNGX returns promptly while the table stays unavailable. Failed load or a C++ exception permits a later retry.

The existing explicit-module preference, package/override/driver search order, hook setup, optional export handling and module lifetime are retained. No new native-library unload policy is introduced: an exception after loading can still leave the loader reference, and previously installed hooks are not rolled back. Null optional exports remain null. Module filename lookup now starts with a zeroed buffer and uses the returned length only on successful, nontruncated lookup; the previous uninitialized buffer could be read on failure.

## Validation scope

`test_native_module_publication.py` compiles the actual NvngxModule, builder, publication method and representative public accessors against loader/export stand-ins and the production publication helper. It runs seven fresh-process scenarios: explicit module, failed load followed by search retry, resolution exception followed by retry, blocked loader, blocked export resolution, failed filename lookup, and truncated filename lookup. All populated export fields are checked; one optional export is intentionally absent. Hook callbacks reenter initialization before publication. Contenders return while construction is deliberately paused.

All seven scenarios passed locally (776 assertions, including repeated export-table checks). The affected 43 shutdown and 236 operation routing checks also passed after adapting their test-owned table accessor. The new scenario script is included in Windows build CI. Full cumulative build results will be added when available.

This validates publication ordering, not the real loader, Detours, driver or GPU. InitNVNGX's existing void interface still expresses unavailable/pending through null accessors, not a new public status. Outer initialization fallback policies remain unchanged. Shared initialization metadata/path vectors, D3D11 device ownership, native stale-handle generations, parameter query admission and replacement-provider shutdown remain separate audit items. Do not treat this checkpoint as completion of all global concurrency work or proof of game crash resolution.

## Delegated Init scope follow-up

D3D11, D3D12 and Vulkan each used a global `_skipInit` flag while forwarding an Init variant to another adapter. A second thread could observe that flag and skip its own native Init/path setup. These three delegation flags are now thread-local. Same-thread forwarding/nesting still restores the previous flag, including exception unwind; no new blocking lock is introduced.

Removed the unused `State::NVNGX_FeatureInfo` pointer and its three writes. The D3D12/Vulkan assignments stored the address of a stack-local common-info structure. Repository-wide reference inspection found no reader, so removal changes no intended behavior and prevents future code from consuming a dangling pointer. This removal is not claimed as proof of an observed crash cause.

`test_native_init_scopes.py` compiles each actual scope class and flag declaration. Its 24 checks passed locally, covering nested same-thread forwarding, isolation of a second thread, previous-state restoration and exception unwind for all three APIs. This does not make shared State strings/path vectors thread-safe, nor distinguish unrelated same-thread native reentry from the existing intentional delegation scope.

## Local mutation checks

Two negative-control checks changed only generated test inputs, not repository production files. Removing the in-flight-operation rejection from the copied lifecycle header failed operation assertion 6. Restoring the historical global skip flag in the extracted Init scope test failed assertion 5. Both compiled and then exited with assertion code 2. This demonstrates that the new checks detect the specific shutdown overlap and cross-thread skip defects; it is not a real-game test.

## Next bounded initialization review

The remaining shared-path issue has concrete source locations: each D3D11/D3D12/Vulkan `UpdateInitPaths` clears and appends `State::NVNGX_FeatureInfo_Paths`, builds a raw pointer array, and points its entries at that vector's strings. Another Init can clear/reallocate those strings while a native call still consumes the first array. `NVNGXProxy::GetFeatureCommonInfo` also appends to the same vector and allocates another array; the caller in `dlssnr/DlssNr_Proxy.cpp` must be included alongside the three internal Init helpers. The arrays have no matching owner/free operation. Thread-local skip flags and export publication do not fix this lifetime boundary.

A follow-up should give each native call a deep-owned immutable path snapshot, including both strings and the pointer array, retain it through nested delegated calls, and publish the cached search paths independently of active call storage. Preserve configured/driver/game path ordering and Vulkan's existing bad-length workaround. Test overlapping Init with different paths, same-thread nesting, retry and snapshot replacement without dangling entries. Other shared metadata (application/project strings and logging callback) needs a separate consistent snapshot; a mutex held during native Init/log callbacks is not an acceptable substitute.

The vendored `nvsdk_ngx.h` and `nvsdk_ngx_vk.h` explicitly do not promise thread-safe methods. Current operation admission prevents Init/Shutdown overlap with the guarded operations; it does not serialize all simultaneous operations or make caller-owned resources thread-safe. Replacement-provider shutdown must additionally track its own successful Init, handle API/device/generation and partial shutdown results before outer cleanup can claim success. None of these source findings alone establishes a Witcher or ZZZ crash cause.

## Completed cumulative validation

Latest code checkpoint `514a224ae370ae67608321dee7440c3adaabfe5c` is pushed to Compatibility-fixes. [Full Windows MSVC DLL build, compatibility checks, package and upload](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35218003287) succeeded, as did [incremental clang-format](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35218003276). Job `105190983876` confirms 55 device/admission checks, 43 shutdown routing checks, 236 operation/parameter checks, all seven module-publication scenarios and 24 Init scope checks. Earlier compatibility guard checks also passed. The publication-only [build](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35217693925) and [format run](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35217694014) succeeded too.

Artifact `OptiScaler_Aurora_v1.0_20260917_compat_514a224a.7z`: ID `10495699132`, 234774378 bytes, GitHub artifact API digest `sha256:a148db27f71863a839887145182f1e7cd3c2963bd6ec14fb77ecac42b9bae541`. This is not a separately measured inner DLL digest. Local cumulative formatting from `1a26bda8` covered 11 applicable production C/C++ files with no edited-line violations; whitespace checks passed and production work is committed.

No game/GPU validation, installer changes, aurora merge, Release or replacement archive was performed. Real-game tests remain deferred at the user's request; the concrete code boundaries above remain the reason the conditional aurora synchronization has not yet occurred.
