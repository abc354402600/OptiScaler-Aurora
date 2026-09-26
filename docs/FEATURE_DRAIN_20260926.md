# Provider feature drain before parent shutdown — 2026-09-26

## Defects and policy

Parent Shutdown previously ignored the registry of outstanding replacement FG handles. DLL providers could destroy their contexts while a public token remained readable; FFX's parent Shutdown is a no-op, so merely retiring that token would leak its feature context and owned D3D12 device reference. Combo can retain one child after a failed Release, requiring retry before either parent is closed.

Normal shutdown now acquires the existing exclusive provider transition admission, selects live features for the requested API/device, calls their actual provider ReleaseFeature, and retires each public token only on success. Only after the drain succeeds does it enter the existing native/provider shutdown callback and local cleanup. No registry lock is held while calling provider/native code. Successful releases remain retired if a later release or parent shutdown fails; retry skips them. Failed releases and exceptions retain ownership and do not proceed to parent close. This is a partial-progress transaction, not a rollback that recreates released features.

Identity tokens remain retained until DLL unload, so successful Shutdown followed by Init cannot resurrect a previously drained token through address reuse. This closes that specific stale-handle path; repeated Init without a preceding successful close remains separate work.

## Device identity and conservative boundaries

- D3D12 Create obtains its device from the actual command list, with a temporary COM owner spanning creation/publication. Null command lists, failed GetDevice and null returned device are rejected with an empty output. Stored identity is immutable and non-owning; it is only compared, never dereferenced for cleanup.
- Vulkan CreateFeature1 records its explicit device and rejects null. Legacy Vulkan CreateFeature has no device argument and remains explicitly unknown; mutable global vkDevice is not used to guess.
- Device-specific shutdown with any matching-API unknown-device live token returns NotInitialized before releasing anything. The caller can release that token explicitly or request global shutdown. Global shutdown can drain unknown-device tokens of its API safely through their provider; it does not drain the other API.
- Once DLL_PROCESS_DETACH has set isShuttingDown, live-feature drain is rejected before entering GPU/provider destruction under a possible loader lock. No successful cleanup is claimed. This does not redesign the DLL's other existing detach behavior.
- ReleaseFeature's existing provider/driver contract still applies: CPU exclusion is not a GPU fence or proof that submitted work has finished. No real GPU tests were performed, per user instruction.

## FFX feature cleanup repair

FFX Release previously dropped its device reference before deleting the wrapper whose destructor destroys the context. It also discarded context destruction failures in the destructor while reporting successful Release. Release now explicitly destroys the context while the owned device reference is alive. Error/exception retains the wrapper/reference for retry; Evaluate rejects a wrapper whose release has started. Successful destruction clears the context before resetting the holder, preventing double destruction, then releases the device and deletes the wrapper. If the SDK clears the context even while returning failure, retry does not call DestroyContext on null.

This covers the normal explicit Release path and the shutdown drain that uses it. It does not assert that every separate context-holder destructor elsewhere can recover from a destruction failure.

## Tests and source scope

- 39 new `test_provider_shutdown_drain.py` checks compile the actual Create/Release/drain/coordinator methods with production registry/admission and fake SDK/COM calls. They cover invalid command lists/devices, balanced temporary COM reference, device/API isolation, active-call exclusion, detach rejection, worker-thread reentry, failures/exceptions, partial-progress retry, parent failure, stale tokens after reinitialization and unknown legacy Vulkan identity. D3D12 HUD work after admission remains a stand-in.
- 22 new `test_ffx_release.py` checks compile the actual FFX holder/destructor, complete Release and Evaluate rejection prefix. Counted SDK/COM stand-ins check destruction order, absent contexts, error/exception retry and context cleared on error. No FFX GPU execution is simulated.
- Actual exported shutdown tests expand from 52 to 56 checks: failed drain reaches neither native close nor local cleanup and receives the exact requested device. Existing fixtures for unrelated routes model an empty successful drain; the new suite tests the actual drain.
- Affected 85 admission, 104 Init-footprint, 36 publication-routing, 42 handle-API, 20 Release-admission, 44 Combo Release and 132 Combo shutdown checks passed locally.
- Three negative controls in temporary copied sources detect removal of device filtering, ignored drain failure, and premature device release. Production files are never mutated by those controls.
- The source extraction helper now tolerates whitespace in declarations because clang-format wraps the longer coordinator signatures. It still fails if the production declaration is absent.

## Remaining work and synchronization gate

Repeated Init while old features remain, native Init/global configuration transaction ordering, partial Create rollback, and concurrent ordinary Evaluate access to shared HUD/depth resources are not solved by this batch. A legacy Vulkan token without explicit device ownership intentionally constrains device-specific close. Preserve these boundaries in the next continuation; do not invent a device association or label CPU tests as game compatibility proof.

The user on 2026-09-26 authorizes direct synchronization to aurora when the code-validation gate is actually met, without a separate confirmation or synchronization notification. Real-game tests remain deferred. No Release is authorized. This checkpoint alone does not close the remaining boundaries above. Full Windows validation will be appended after Actions completes.
