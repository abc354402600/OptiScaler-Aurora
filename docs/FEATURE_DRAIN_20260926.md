# Provider feature drain before parent shutdown — 2026-09-26

## Defects and policy

Parent Shutdown previously ignored the registry of outstanding replacement FG handles. DLL providers could destroy their contexts while a public token remained readable; FFX's parent Shutdown is a no-op, so merely retiring that token would leak its feature context and owned D3D12 device reference. Combo can retain one child after a failed Release, requiring retry before either parent is closed.

Normal shutdown now acquires the existing exclusive provider transition admission, selects live features for the requested API/device, suspends their Evaluate admission, calls their actual provider ReleaseFeature, and retires each public token only on success. Only after the drain succeeds does it enter the existing native/provider shutdown callback and local cleanup. No registry lock is held while calling provider/native code. Successful releases remain retired if a later release or parent shutdown fails; retry skips them. Failed releases and exceptions retain ownership and do not proceed to parent close. Selected tokens remain suspended after a partial drain, including those not yet visited; explicit Release or shutdown retry remains available. Unrelated devices/APIs are unaffected. This is a partial-progress transaction, not a rollback that recreates released features.

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

- 46 new `test_provider_shutdown_drain.py` checks compile the actual Create/Release/drain/coordinator methods with production registry/admission and fake SDK/COM calls. They cover invalid command lists/devices, balanced temporary COM reference, device/API isolation, active-call exclusion, detach rejection, worker-thread reentry, failures/exceptions, partial-progress retry, suspended reads with explicit Release recovery, parent failure, stale tokens after reinitialization and unknown legacy Vulkan identity. D3D12 HUD work after admission remains a stand-in.
- 22 new `test_ffx_release.py` checks compile the actual FFX holder/destructor, complete Release and Evaluate rejection prefix. Counted SDK/COM stand-ins check destruction order, absent contexts, error/exception retry and context cleared on error. No FFX GPU execution is simulated.
- Actual exported shutdown tests expand from 52 to 56 checks: failed drain reaches neither native close nor local cleanup and receives the exact requested device. Existing fixtures for unrelated routes model an empty successful drain; the new suite tests the actual drain.
- Affected 85 admission, 104 Init-footprint, 36 publication-routing, 42 handle-API, 20 Release-admission, 44 Combo Release and 132 Combo shutdown checks passed locally.
- Three negative controls in temporary copied sources detect removal of device filtering, ignored drain failure, and premature device release. Production files are never mutated by those controls.
- The suspension follow-up adds a fourth negative control: omitting SuspendReads fails the drain suite when failed teardown would otherwise allow Evaluate. The unchanged 32 registry lifetime checks and affected 42 API/20 Release-route checks also pass.
- The source extraction helper now tolerates whitespace in declarations because clang-format wraps the longer coordinator signatures. It still fails if the production declaration is absent.

## Remaining work and synchronization gate

Repeated Init while old features remain, native Init/global configuration transaction ordering, partial Create rollback, and concurrent ordinary Evaluate access to shared HUD/depth resources are not solved by this batch. A legacy Vulkan token without explicit device ownership intentionally constrains device-specific close. Preserve these boundaries in the next continuation; do not invent a device association or label CPU tests as game compatibility proof.

The user on 2026-09-26 authorizes direct synchronization to aurora when the code-validation gate is actually met, without a separate confirmation or synchronization notification. Real-game tests remain deferred. No Release is authorized. This checkpoint alone does not close the remaining boundaries above. Full Windows validation will be appended after Actions completes.

## Next concrete ownership boundary

Nvngx_Combo::D3D12_CreateFeature still deletes its private wrapper after attempting to release a successful child when the other child creation fails. It ignores the Release result. Now that FFX Release correctly retains its wrapper/device on DestroyContext failure, the Combo Create rollback must retain that private child's ownership instead of losing the pointer. An outer published-handle drain cannot find such an unpublished orphan. Add an explicit private rollback ledger and drain it before parent teardown, or a similarly typed ownership contract; do not publish a failed Create as a usable game handle or guess that an arbitrary failing third-party Create output is valid. Allocation failure and exceptions between child creates also need this ownership model.

Global native Init still writes metadata and initializes native NGX before replacement-provider transition admission. A quick additional lock inside replacement Init would not serialize the entire exported transaction and could reject legitimate delegated Init; keep the existing thread-local delegation semantics when designing that gate.

## Windows validation, first checkpoint

`1c57db0e280f45f26987ce6d56e8d646e5cdfb9d`: run `36221428934`, job `108347303573` passed full MSBuild, compatibility suites, packaging and upload. Format run `36221428908` passed. MSVC logs confirm the first checkpoint's 39 drain, 22 FFX ordering and 56 exported shutdown checks. Artifact `OptiScaler_Aurora_v1.0_20260926_compat_1c57db0e.7z`, id `10898598510`, 234786142 bytes, Actions digest `sha256:86c16229909d3dffcf6a10ed8d6e373f95d06b7c651e86a9fddf7996d701a98b`. The subsequent suspension follow-up has 46 drain checks and requires its own final build result below.

## Final Windows validation

`5ca3e6ecababefbef90e6d781835535148ab7404`: run `36221577866`, job `108347716832`, full DLL/RC build, compatibility tests, package and upload all succeeded. Format run `36221577867` succeeded. MSVC confirms 46 drain + 22 FFX checks, expanded 56 exported shutdown checks and the existing 32 registry tests; affected compatibility suites also passed. Artifact `OptiScaler_Aurora_v1.0_20260926_compat_5ca3e6ec.7z`, id `10899159613`, 234789638 bytes, Actions digest `sha256:6f6087a364668b116a9b787b0daeff7533eaad92483b99dd61a21803b66bbe0b`. No installed game/driver files were modified and no Release was published. CPU/GPU distinction and remaining initialization/private-rollback boundaries above still apply.
