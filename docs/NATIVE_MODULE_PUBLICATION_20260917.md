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
