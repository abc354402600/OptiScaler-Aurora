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

## Remaining scope

Provider-global Init/Shutdown still needs API/device admission, handle generation association and shutdown-result propagation. This registry fix does not prevent provider-global Shutdown racing an admitted Evaluate or an old handle reaching a reinitialized provider. Shared HUD-copy resources, Combo Create rollback when a child release fails, and application code ignoring failed release results also remain separate concerns. Do not merge this ongoing lifecycle batch to aurora until the agreed code/review/build gate is satisfied. Real-game tests remain deferred at the user's request.
