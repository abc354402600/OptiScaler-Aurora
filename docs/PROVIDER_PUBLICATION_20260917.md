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

A separate remaining source finding is Combo's partial Release: it deletes its wrapper even when a child Release fails, while the outer registry correctly retains failed-release handles for retry. That can leave a retained registry token pointing to freed Combo storage. It requires an explicit retryable child-ownership fix and is not covered by the publication/export changes above.
