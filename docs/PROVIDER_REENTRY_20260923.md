# Replacement-provider callback admission — 2026-09-23

## Observed source defect

ProviderHandleRegistry formerly held a shared mutex throughout Evaluate and an exclusive mutex throughout Release. If a provider callback reentered Release for that same token, or Release called back into handle identity lookup, the callback attempted to acquire a lock already held by its own call stack. A callback waiting for another thread using the same token could also create a lock cycle. This is a reproducible CPU-side lifetime defect, not proof of the cause of a specific Witcher crash.

## Change

The registry now counts admitted readers and marks an admitted release under a short per-token mutex, then invokes the provider with the mutex released. Release returns busy immediately while readers or another release are active. Evaluate returns busy during Release. Successful Release retires the token; failures and exceptions release admission while preserving ownership for an explicit retry. There is no queued or deferred native teardown. Public token addresses and immutable identity fields remain retained until registry destruction, preserving routing and preventing address reuse. Published wrapper fields are passed to callbacks as const; their native resource pointers are not themselves dereferenced by identity lookup.

D3D12 and Vulkan replacement-provider routes distinguish busy (`FAIL_NotInitialized`) from unknown/retired (`FAIL_FeatureNotFound`). The exported Release paths already return the provider result directly, so a busy/failing attempt does not report success or remove the token. Concurrent Evaluate calls remain admitted as before; this change does not establish that an arbitrary provider supports concurrent evaluation.

## Focused validation

- Production-header lifetime checks expanded from 17 to 32, including nonblocking busy release and explicit retry, same-thread callback reentry, identity during Release, callback joining a second thread, exception cleanup, concurrent double-release and token retirement.
- 18 new extracted-production D3D12/Vulkan Release checks confirm busy/failure propagation and zero native Release calls while Evaluate owns the token.
- Affected 16 creation-failure and 44 Combo partial-release checks pass locally.
- Windows full-build and package results are recorded after CI completion; none of these CPU checks validate a game/driver.

## Completed Windows build

Code checkpoint `64f5ef468a9654c83ebf75a04c33f23c00b7fee4` passed full Windows build, MSVC checks and packaging in [run 35786223489](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35786223489); format run 35786223620 also succeeded. Job 106943575380 confirms the 32 registry, 18 Release-route, 16 creation and 44 Combo checks passed. The broader existing lifecycle CI guards also passed; unrelated installer suites were not rerun locally.

Artifact: `OptiScaler_Aurora_v1.0_20260922_compat_64f5ef46.7z`, id 10719838064, 234785521 bytes. GitHub API artifact digest: `sha256:f9fb12e761ab77db973bb4c7d1a9963309212908d4844f47f0183cc63767a34a` (container digest, not inner DLL hash).

A local negative-control build removed the active-reader admission check in a temporary copy. The regression test failed at "busy release returns without waiting or touching native handle", as intended. Production sources were not mutated by that negative control.

## Remaining scope

Provider-global Init/Shutdown still needs API/device admission, handle generation association and shutdown-result propagation. This registry fix does not prevent provider-global Shutdown racing an admitted Evaluate or an old handle reaching a reinitialized provider. Shared HUD-copy resources, Combo Create rollback when a child release fails, and application code ignoring failed release results also remain separate concerns. Do not merge this ongoing lifecycle batch to aurora until the agreed code/review/build gate is satisfied. Real-game tests remain deferred at the user's request.

The next implementation must preserve the distinct cleanup contracts: Nvngx_FFX::Shutdown1 currently does no teardown, while DLL providers forward native teardown; Combo forwards to two children and can partially succeed. Do not retire every live handle blindly on a global success, forward an old-generation Release into a new device context, or repeat a successful child's shutdown merely because the other child failed. D3D12 command lists can identify their device; legacy Vulkan Create lacks an explicit device and must not guess across multiple live devices. These are concrete follow-up boundaries, not completed behavior.
