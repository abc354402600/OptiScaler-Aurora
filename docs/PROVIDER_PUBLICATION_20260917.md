# Provider publication boundary — 2026-09-17

Continuation from `a59bd442` on `Compatibility-fixes`. This is a bounded initialization/publication fix, not completion of the native provider shutdown concurrency design.

## Actual defects

- `Nvngx_FG::getProvider` assigned a global unique_ptr before checking API availability. Other callers could observe that candidate while fallback destroyed/replaced it. Concurrent first calls also mutated the same unique_ptr without synchronization.
- All four provider Shutdown/Shutdown1 adapters used the lazy factory. Shutdown before any published provider could load DLLs, choose fallbacks and mutate configuration during teardown.
- Simply adding a nonblocking construction guard would have introduced a routing defect: exported Create and Vulkan capability/scratch routes interpreted a temporarily missing provider as permission to enter native NGX or return a fabricated scratch size.

## Changes

`ProviderPublication<T>` privately owns the final provider and publishes its address with release/acquire ordering only after construction and availability/fallback decisions complete. The published owner is never replaced and lasts until DLL/static teardown, as before. Construction uses a nonblocking atomic gate; concurrent and recursive callers receive an explicit Pending result. No mutex is held while loading DLLs or calling constructors. Failed/throwing factories release the gate and permit retry; no negative cache is added.

The factory retains the existing provider order, availability criteria and fallback policy. `State::activeFgNvngx` is atomic because fallback writes it while render/UI paths read it. This does not make all Config/State fields or notification APIs thread-safe.

D3D12 and Vulkan exported FG Create routes return NotInitialized on Pending, clearing caller output first. Vulkan instance/device extension requirements, feature requirements and scratch-size routes also preserve Pending rather than falling into their prior native/default path. Non-FG queries do not construct a provider just to test FG availability. API-specific unavailability still follows the existing fallback route. Provider Init adapters preserve the Pending result and their outer Init adapters propagate NotInitialized before committing the outer success state. Existing native initialization calls earlier in those outer adapters are not rolled back; other prior native failure policies are unchanged.

All four provider shutdown adapters use Peek only. A missing or still-constructing provider returns failure without triggering construction or waiting on a loader callback. An already published provider receives the same Shutdown/Shutdown1 call as before.

## Focused validation

- **22 production-header CPU checks**: no partial publication, deterministic concurrent construction pause, contender returns without waiting, no API call on Pending, API-specific support, one stable pointer after publication, recursive callback, null-factory retry, exception retry, and 12 contending threads performing 12,000 lookups with one factory and no partial observations.
- **36 executable source-extraction checks**: actual exported FG routing prefixes and actual provider shutdown adapters compiled against counted stand-ins. Pending cannot reach the native fallback boundary or invoke replacement Create; outputs are cleared; invalid outputs rejected; available and unavailable cases retain their routes; non-FG creation does not query the provider; shutdown before/during construction does not lazy-load and published shutdown preserves device arguments/call counts.
- The extraction intentionally stops at existing native/internal fallback boundaries and returns a sentinel there. It does not execute those native implementations or validate GPU behavior.
- Full Windows MSVC build/CI results will be recorded after the pushed checkpoint completes.

## Remaining boundaries

This fixes **C++ provider object publication**, not successful **native API/device initialization**. Native Init/Shutdown/Evaluate can still overlap after a provider is published. Peek deliberately does not certify native initialization or device ownership. Outer shutdown still has global cleanup and native error handling limitations documented in the preceding audit. A complete follow-up needs API/device lifecycle ownership, operation admission, callback-safe shutdown and retired-handle behavior; replacing that design with a mutex around DLL calls risks deadlocks.

Other existing boundaries remain: shared HUD-copy resources, Config/global State accesses, teardown after DLL/static lifetime, and caller behavior after NotInitialized. A game is not guaranteed to retry a failed call, so real-game testing remains required. There is no automatic hidden native fallback for Pending.

Native SL1, the established 6X patches, DualFeature=false, installed games and driver settings are unchanged. No installer revival, release, main-branch merge or replacement archive.
## DLL export and destructor follow-up

The same failure-path review found an additional concrete defect in `Nvngx_DllProxy`: `depthCopy[2]` had no initializer. Its real derived providers have user-provided constructors, so construction does not reliably zero this base member. The destructor's SAFE_RELEASE operations could read/release indeterminate pointers, including when the publication factory rejects an unavailable candidate. Both pointers now start null.

18 additional native forwarding paths only checked generic API availability (the Init export), then called another possibly absent export. Every such call now also checks its own target pointer, including Init_Ext, Create, Release, Evaluate, query and parameter routes. Existing four shutdown guards remain. An absent Evaluate export is rejected before depth/parameter mutation. Availability/fallback policy is unchanged; optional missing exports return failure rather than triggering a null call.

**69 further executable checks** compile all 22 actual DLL forwarder bodies with absent, present and unavailable exports. They also use the exact production depth pointer member declaration and destructor in a stand-in base with a user-provided derived constructor, constructed over nonzero storage: no resource cleanup before allocation, and one valid allocated resource released once. SDK and resource operations are test stand-ins; no GPU behavior is established.

## Combo partial-release follow-up

Combo deleted its wrapper even when a child Release failed, while the outer registry correctly retained failed-release handles for retry. That left a retained registry token pointing to freed Combo storage. It now marks release started, clears only successfully released child handles, skips already released children on retry, and deletes the wrapper only after both children are released. Evaluate rejects a handle once release starts, including a failed/partial release, before touching parameters or child resources. The existing outer registry serializes these accesses; no new lock across a native DLL callback is introduced.

**44 executable ownership checks** use the actual Combo handle fields, Release body and Evaluate admission prefix with the production registry. They cover all four child success/failure combinations, retry without duplicate child release, wrapper retention/deletion, rejection of Evaluate after release starts, retained public identity, duplicate public Release rejection, null inputs, and a C++ exception after one child successfully released. Child providers are stand-ins; failure is assumed to leave that child's handle available for retry, matching the outer registry's existing policy. Foreign native implementations that invalidate a handle despite reporting failure are not made safe by this fix.

Combo Create rollback after a child creation/cleanup failure, native device initialization ownership, and concurrent global shutdown still require separate review. These changes do not claim to complete those boundaries.
## Next lifecycle boundary: source findings, not implemented here

The vendored NGX headers (`external/nvngx_dlss_sdk/nvsdk_ngx.h` and `nvsdk_ngx_vk.h`, Shutdown documentation) distinguish device-only Shutdown1(device) from all-device Shutdown1(nullptr)/Shutdown(). A global construction gate is therefore not a substitute for device ownership.

Concrete next audit targets:

1. The registry's private value currently records only ID/nativeHandle, without API/device/generation. Before native shutdown can invalidate just one device's handles, that ownership must be represented. D3D12 Create can obtain a device from the command list; Vulkan CreateFeature1 supplies a device explicitly, while legacy CreateFeature requires a reliable association rather than assuming a mutable global device belongs to every command buffer.
2. Native Init results other than NotInitialized are still ignored by the outer adapters. A published DLL/export is not proof of successful initialization for that API/device. Success/failure/retry state must be tracked before admitting Create/Evaluate after shutdown or failed initialization.
3. Outer shutdown performs global Aurora cleanup and clears initialization flags without preserving native failure results. The D3D12 route also calls `DLSSFeatureDx12::Shutdown`, which can independently call native NVNGX Shutdown, followed by the outer native shutdown route. This is separate from the already repaired duplicate **replacement-provider** shutdown and needs executable nested-route coverage. `D3D12Device` is currently nulled before that helper receives it, so a Shutdown1 fallback can receive nullptr (global shutdown by the SDK contract).
4. Operation admission must close the target API/device generation before native teardown, with a short metadata lock only. Waiting while a loader or native callback re-enters can deadlock; a busy/error outcome must be propagated through the outer cleanup rather than ignored. Do not silently defer native GPU teardown after the caller destroys its device. Do not retire native handles on a failed shutdown without a clear ownership contract.
5. FFX's native provider shutdown is currently a no-op, while DLL-backed providers call external code. Shared depth/HUD copy state and static FFX initialization need their own ownership review; the publication gate alone does not serialize later evaluations.

Required future tests include two devices with one closing, D3D12 plus Vulkan coexistence, Create/Evaluate/Release overlapping shutdown admission, callback reentry, native Init/Shutdown failures, shutdown before Init, repeated shutdown/reinitialize, and stale handles from a prior generation. Those tests do not exist yet and are not counted in this batch's 171 new checks.

## Local mutation evidence

Two additional local checks modified only generated test translation units (not repository production code). Removing the depth-pointer initializer was rejected at the first DLL boundary assertion. Deleting the Combo wrapper on a failed child release was rejected at ownership assertion 12. Both exited with the test failure code 2; no native DLL/GPU call or installed-game change was involved.
## Completed checkpoint validation

Code checkpoints pushed to `Compatibility-fixes`:

- `771d2aca`: validated provider publication, explicit Pending routes and no lazy load on shutdown.
- `6b92beb9`: initialized DLL depth resources and missing-export guards.
- `e737b087644e9f3120d72172c0108a1bb91f3227`: cumulative Combo partial-release fix.

The [cumulative Windows MSVC DLL build, tests, package and upload](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35129887577) completed **successfully**. Job `104907980795` explicitly reports all **171 new checks** passed: 22 publication, 36 routing, 69 DLL boundary and 44 Combo ownership. Existing compatibility guard checks also passed. These are CPU and build checks, not actual game/GPU validation.

[Incremental clang-format CI](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35129887470) succeeded. Local cumulative formatting check from `a59bd442` covered 10 applicable production C/C++ files with zero edited-line violations. The earlier publication-only [build](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35129237723) and [format check](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/35129237663) also succeeded.

Cumulative Actions artifact: `OptiScaler_Aurora_v1.0_20260916_compat_e737b087.7z`, 234768572 bytes; GitHub artifact API digest `sha256:a538597fb35a8a3f79496ee9f16ee62bb1732d4a133af2f13cbc17bd164f949d`. This is the artifact digest, not a separately measured inner DLL hash. Its date follows the UTC runner date; the local work date is September 17.

The result is a compatibility-branch checkpoint only. Main `aurora` and Releases were not updated. The remaining native API/device shutdown work above and Witcher/ZZZ game validation are still open.
