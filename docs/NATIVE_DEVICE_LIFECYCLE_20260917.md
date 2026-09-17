# Native NGX device ownership — 2026-09-17

This continuation addresses native D3D12/Vulkan Init and Shutdown ownership. It does not change the installer, shaders, SL1 protection, DualFeature policy or 6X patch.

## Defects and changes

- A single per-API initialized boolean represented multiple native devices. Successful Init is now tracked by exact device, separately for D3D12 and Vulkan. Repeated successful Init for the same device is idempotent; failed initialization can retry. The internal Vulkan helper no longer reports success after a native initialization failure.
- Shutdown1(device) previously led to global cleanup and could leave another live device marked uninitialized. Native shutdown now targets only the owned device; unknown/already-closed devices do not invoke native shutdown. A device-specific missing export fails rather than falling back to an all-device call. Shutdown()/Shutdown1(nullptr) retain the SDK's all-device meaning.
- D3D12 cleanup nulled the cached device before passing it to DLSSFeatureDx12::Shutdown; that helper could itself shut native NGX down, followed by another outer shutdown. The nested native dispatch is removed. Shared NGX hooks remain installed because other APIs/devices may still use them.
- Native failure now reaches the outer caller before it clears local device state or dispatches provider shutdown. Successful shutdown of a noncurrent device preserves current Aurora state; one API does not clear the other API's current-feature pointer. D3D12's existing process-exit skip is retained.
- DLSS and DLSSD internal initialization caches now also check exact-device readiness, allowing another or reinitialized device to initialize native NGX.
- Init/Shutdown metadata transitions use a short mutex, released before native callbacks. Concurrent/reentrant transitions return NotInitialized without waiting on native/loader callbacks. Metadata allocation precedes the native Init call. C++ exceptions restore bookkeeping; no native resource rollback is claimed after an exception. Ordinary readiness queries use an atomic count.

## Focused validation

- **37 production-header checks**: two devices/two APIs, failed Init and Shutdown, exact/global close, retry, idempotence, null/unknown device, exceptions, callback reentry and deterministic concurrent transition admission.
- **43 extracted-production routing checks**, replacing the previous 14: actual native proxy Init/Shutdown bodies and outer adapters with counted SDK stand-ins; correct device forwarding, absent Shutdown1, failed native calls, no duplicate nested dispatch, current/other API cleanup and process-exit skip.
- These local C++ tests pass. The full MSVC build and incremental-format results will be appended after the checkpoint is pushed. The tests use CPU stand-ins, not a real driver or game.

## Explicit remaining boundaries

This is an Init/Shutdown ownership checkpoint, not full concurrent operation admission. Create/Evaluate/Release still obtain raw native entry points: an already admitted call can overlap shutdown, and any-ready availability does not establish ownership for every handle. The next stage must address this without holding locks across external DLL calls.

Replacement FG providers have separate device/handle ownership and shutdown semantics, not covered by this native registry. Outer adapters still ignore their shutdown result. Global module loading, mutable shared depth/HUD resources and general State/Config ownership are not solved here. Aurora still has a single current-device cache; native multidevice bookkeeping does not make every renderer feature multidevice-safe. The process-exit skip intentionally leaves native bookkeeping until DLL teardown.

The user has deferred real-game validation and authorized synchronization to aurora after code work/review/build completion. Remaining lifecycle work means that gate has not yet been reached. No main-branch merge or Release is performed by this checkpoint.

## Init/Shutdown checkpoint validation

Commit `3df849934112a115ef09fa280ffe810337b4042c` was pushed to Compatibility-fixes. [Windows DLL build, CPU checks and package](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35188944901) and [incremental format](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35188944895) succeeded. Job `105097010598` confirms 37 device checks and 43 shutdown checks passed. Artifact `OptiScaler_Aurora_v1.0_20260917_compat_3df84993.7z` was uploaded (ID `10484080454`, 234774490 bytes).

## Native operation admission follow-up

Nine D3D12/Vulkan Create/Evaluate/Release/DestroyParameters getters now return same-signature guarded entry points rather than raw native pointers. Export availability is stable after module initialization; readiness is checked at invocation, including when a caller cached a pointer before shutdown. Create outputs are cleared on rejected admission, and Vulkan CreateFeature1 additionally verifies its explicitly supplied device. Shutdown getters also route through the ownership helper so callers cannot bypass it.

An operation briefly increments an API-local active count and releases the metadata mutex before foreign code. Init of a new device and owned-device/global Shutdown reject while that API has active guarded calls. During a transition new calls are rejected. Exceptions unwind the active count. There is no wait across a native callback and no deferred teardown. Calls on another API remain independent. This is conservatively API-wide because legacy native handle and command-buffer routes do not expose complete device/generation ownership; it does not pretend those associations have been solved.

The changed Busy return exposed an existing bug in TryDestroyNGXParameters: it returned true even if native DestroyParameters failed. It now reports success only for native Success, preserving the existing internal-table deletion and unknown-table policy.

Focused tests now contain **55 device/admission checks** (18 added) and **236 new extracted-operation/parameter-destruction checks** covering all nine actual getters, cached pointers before/during/after shutdown, callback reentry, output clearing, absent exports, explicit unknown Vulkan device, retries, both shutdown getters and native destroy failure. The existing 43 shutdown routing checks were rerun because the shared lifecycle header changed; they passed. Local checks use counted native stand-ins. Cumulative MSVC validation will be recorded after this follow-up is pushed.

Still open: calls bypassing these getters, parameter acquisition/query routes, old native handles after a device generation closes/reopens, D3D11, replacement-provider lifecycle, and global module publication. Existing higher-level owners may discard resources after a failed release; no general ownership redesign is claimed. These checks do not establish in-game behavior or complete the main-branch merge gate.
