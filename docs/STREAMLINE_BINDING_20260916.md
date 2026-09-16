# Active Streamline binding — 2026-09-16

Based on `Compatibility-fixes` at `b2fb907d`. Selective adaptation of [official PR 1157](https://github.com/optiscaler/OptiScaler/pull/1157), commit `7543d1437c2b050ec38c02dfb71cc2df5b2cb965`. No new rendering feature or installer work.

## Problem and change

The private D3D12 Streamline path previously resolved DLSSG/Reflex/PCL directly from bundled DLLs before selecting the device. The interposer can initialize a different plugin, so a valid export address is not proof that its plugin was initialized. The upstream author reproduced that mismatch on RTX 5090; this is not proof of the user's RTX 40 ZZZ 11008 cause. Aurora disables OTA and retains its existing private runtime paths and SL1 policy.

The revised path resolves feature functions through the private interposer's `slGetFeatureFunction` only after successful `slSetD3DDevice`, consistent with `external/streamline/sl_core_api.h:300`. Required DLSSG/Reflex/PCL functions and initial Reflex configuration must all succeed before publishing the table and readiness. Optional Reflex camera/PCL state functions can be absent. No bundled-export fallback is used after an active binding failure. Module identities are diagnostic/classification data; forwarded functions and hook trampolines need not share one image.

Unlike a blind port, Aurora now separates runtime initialization from usable FG readiness. The Witcher `CreateSLOnThe2ndDevice` path initializes SL on the first device and selects/binds on the existing second-device hook. The first stage does not report FG ready. Failed function/configuration binding can retry without repeating successful `slInit` or `slSetD3DDevice`; a different selected device requires a new binding. The raw legacy D3D11 accessor is not redirected through this D3D12 policy.

Swapchain setup, activation, dispatch and state evaluation respect readiness; plugin accessors hide incomplete bindings. Two Reflex marker/sleep paths also previously dereferenced an uninitialized frame-token pointer without checking the token API result. They now validate the function and returned token and fall back to the existing native NVAPI call when unavailable. The post-present sleep path checks its function before calling it.

## Validation and remaining boundaries

- 23 local Windows C++ checks against production `FeatureBindingLifecycle`: deferred startup, missing runtime/null device, device failure, incomplete functions, Reflex failure, retry without duplicate device binding, optional function absence, publication before readiness, same-device reuse and new-device failure/recovery.
- Tests simulate the lifecycle, not NVIDIA plugin initialization or FG presentation. Full MSVC build and CI results are recorded below after completion.
- Device initialization still follows the SDK's serialized `slSetD3DDevice` contract. Atomic readiness publication does not serialize arbitrary concurrent device changes, plugin shutdown, or in-flight native callbacks. Provider-global shutdown remains a separate audit.
- No game files, native SL1 libraries, MFG patch bytes, `DualFeature=false`, or driver settings were modified.
- Real-game checks: Witcher first/second-device startup, saved Dynamic MFG loading, 6X and FG toggles; a normal single-device DLSSG title; ZZZ reproduction with exact build/logs if still failing. Check logs for `Active Streamline DLSSG/Reflex/PCL functions ready` or a specific binding error. CPU tests do not establish that existing crashes are resolved.
