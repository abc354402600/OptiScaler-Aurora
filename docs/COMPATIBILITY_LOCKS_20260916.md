# Input loader lock and FG routing follow-up — 2026-09-16

Continuation from `86fd6c82` on `Compatibility-fixes`. This is another focused compatibility checkpoint, not a declaration that all games are fixed.

## Optional input module discovery

[Upstream issue 1162](https://github.com/optiscaler/OptiScaler/issues/1162) describes a startup wait cycle involving GetProcAddress(dinput8) under the input state lock and a DllMain callback taking that same lock. Source inspection confirms the relevant pattern in Aurora. The report concerns Forza Horizon 5 on two forks, not an established ZZZ 11008 cause.

Aurora now prepares GameInput, XInput, and DirectInput module/export snapshots before acquiring the lock used to publish state and install hooks. BeginFrame calls a private locked initializer, so it cannot accidentally resolve exports under an outer recursive acquisition. Installed integrations skip further export resolution. References keep discovered modules alive through publication and are released after unlocking; failed discovery can be retried when a module appears later.

This deliberately preserves state-lock serialization of the existing Detours transactions, instead of introducing independent installation threads. It is a narrower implementation than the private-fork rewrite described in the issue. Win32 hook initialization, optional HID code, application callbacks made under input locks, and cross-subsystem Detours transactions have not been comprehensively redesigned. Do not call this a proof that every loader-lock cycle is eliminated.

Production `PrepareBeforeLock` helper is exercised by eight CPU checks: a simulated loader callback acquiring the state lock, locked publication, result propagation, normal unlocking, discovery and publication exceptions, prepared-object destruction after unlock, and concurrent publication serialization. The simulation is not a real game loader test.

## Provider identities through the outer NVNGX router

The previous provider registry guarded Evaluate/Release internally, but D3D12/Vulkan exported routes still read `handle->Id` before consulting it. Known provider identities now come from the registry first. They keep routing to the provider even when the active replacement selection has changed. Vulkan's earlier raw-ID log has been removed.

Retired provider entries retain their small public tokens until registry/DLL destruction. This prevents stale pointers from being recycled into new live provider or foreign handles. The native provider still releases its resources on successful Release; callbacks reject retired entries. The retained production value contains only an ID and a raw native handle pointer, not owned GPU resources. Memory therefore grows by one small identity record per successfully created FG handle, not per frame. Arbitrary foreign/stale native NGX pointers remain governed by the native API contract.

Provider tests expand from 14 to 17, covering retired identity lookup without dereferencing the caller's pointer, unknown identity rejection, and address non-reuse in addition to release/evaluate overlap. Existing outer shared-state side effects and provider-global shutdown/selection concurrency are separate follow-ups; identity protection alone does not redesign them.

## Remaining work

The Streamline follow-up has now been narrowed to specific call sites. `Streamline_Proxy.h::InitWithD3D12` resolves bundled plugin exports before `_slSetD3DDevice`. `D3D12_Hooks.cpp` later sets a second device for `CreateSLOnThe2ndDevice` and immediately calls Reflex. A future active-interposer binding change must cover both paths, distinguish initialization requested from device/functions ready, and publish complete DLSSG/Reflex/PCL groups before callers use them. Missing required functions must not leave a partially usable group or call an uninitialized bundled fallback. Audit the D3D11 accessor sharing and initialization retry behavior too. [PR 1157](https://github.com/optiscaler/OptiScaler/pull/1157), reviewed at `7543d143`, supplies evidence and an implementation candidate; Aurora's private runtime and disabled OTA flags mean its reported driver/plugin mismatch is not yet demonstrated here.

For provider-global ordering, `Nvngx_FG::getProvider` currently constructs/publishes a shared singleton independently of per-handle locks, while Shutdown calls the provider directly. In the D3D12 outer Release route, exposure tracking and current FG context cleanup also precede the per-handle release guard. Retained identities solve neither concurrent singleton initialization nor native shutdown versus in-flight evaluation. A follow-up must coordinate those operations and their callbacks, not simply add a mutex around every API call and risk a new reentrant deadlock.

- Active Streamline plugin-function binding: audit deferred-device initialization and function publication order before adopting the broader PR.
- Provider-global/context lifecycle: native resource shutdown and settings changes need a coherent ordering beyond pointer identity.
- Genshin regression bisect: controlled known-good/bad bridge/runtime comparison still needs real repro feedback. Do not blindly revert the upstream mutex commit or import an untested FG lifecycle fork.
- ZZZ 11008/file disappearance: tentative RTX 40 information only; no exact build or crash/security history to establish the cause.
- Witcher: saved Dynamic MFG loading, toggling modes, and the separate CPU crash signature require renewed game testing.
- NTE: the per-game NPI menu setting remains a reversible community workaround awaiting local comparison; no driver settings were changed.

No native SL1 replacement, 6X unlock change, installer work, main-branch merge, or Release publication is included.

## Completed validation

Code/workflow checkpoint: `94e3c2c721aae8edde0aec021551897c9a865a37` (input fix `120a421e`, provider routing fix `1be0123b`).

- Local Windows C++ checks: 8 input-lock checks and 17 provider-handle checks passed. Incremental clang-format 20.1.8 review from `86fd6c82`: 10 changed C/C++ files, zero edited-line violations.
- [Full Windows MSVC DLL build, focused guard tests, packaging and upload](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34995403209): **success**. Job `104470259892` explicitly reports 17 provider checks and 8 input-lock checks passed; the existing frame-guard test also completed successfully in the same required step.
- [Incremental clang-format CI](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34995403062): **success**.
- Uploaded artifact: `OptiScaler_Aurora_v1.0_20260915_compat_94e3c2c7.7z`, 234777713 bytes. GitHub artifact API digest: `sha256:81d8161515674d5068326ed9f192df9d881abdde459b52aa354180705dfb68f0`; not a separately measured inner DLL hash.
- Subsequent documentation-only commit records validation and next-stage source audit; unchanged C++ is not rebuilt for that record. No real-game/GPU validation is implied.
