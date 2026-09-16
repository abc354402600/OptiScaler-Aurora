# FG creation failure boundary — 2026-09-16

Continuation from `2bf68763` on `Compatibility-fixes`. The user currently cannot test Witcher and does not own ZZZ; actual game verification is pending and must not block independent source-level work. New features are deferred. No main-branch merge is justified by CPU tests alone.

## Confirmed defects repaired

- Both exported Vulkan FG Create routes logged `(*OutHandle)->Id` unconditionally after provider creation. Failure leaves the output null, so the diagnostic path could itself crash. These routes now validate/clear output and only inspect the handle after successful creation with a non-null result.
- The D3D12 and Vulkan provider adapters previously returned early for an unavailable provider before clearing a caller's old output, and published wrappers when a native provider returned success with a null native handle. A shared production helper now clears output before provider lookup, retains unpublished wrapper ownership during creation, and publishes only a successful, non-null native handle.
- D3D12 exported creation clears output before command-list validation and only records/logs native or replacement handles on a successful result. This prevents reading stale outputs on error.

Failed native creation remains the provider's responsibility: Aurora does not guess how to release a pointer written alongside a failure result. C++ exceptions leave output empty and the unpublished wrapper destroyed; this helper does not claim to catch structured exceptions or make foreign binaries safe.

## Device shutdown follow-up

The subsequent call-chain review confirmed that both outer `Shutdown1(device)` implementations called the provider's device shutdown and then delegated to the global exported shutdown, which called the provider again. Local Aurora cleanup is now separate from provider dispatch: the device route performs that cleanup without a second global provider shutdown. Global shutdown still calls the provider once. Four DLL-provider shutdown entry points now check the relevant export before calling it; the previous availability test only checked the Init export, which did not prove Shutdown/Shutdown1 existed.

14 additional checks compile the actual shutdown bodies extracted from the source files against counted NGX/provider stand-ins. They verify one device or global provider dispatch, the device argument, retained local cleanup, and missing/unavailable export rejection. This is executable routing verification, not a duplicated model of the production bodies, and does not validate native GPU teardown. The extraction is limited to these simple function bodies; the full DLL build separately checks their real SDK integration.

Existing global Aurora cleanup and ignored native shutdown result handling are not a complete multi-device lifetime design. This patch removes a confirmed duplicate provider call; it does not claim to coordinate concurrent evaluations or preserve every other live Aurora device context.

## Focused validation

16 Windows C++ checks exercise the production creation helper and registry: null output without native invocation, clearing stale output before callback, failure/unavailable-provider behavior, no publication on failure, successful return with no native handle, failure that writes a pointer, exception cleanup, successful publication/read and release exactly once. These are CPU failure-path checks, not GPU compatibility evidence.

## Global lifecycle audit remains open

`Nvngx_FG::getProvider` still constructs and exposes a shared provider before fallback validation completes. A concurrent call could observe that provider while another call replaces it. A mutex held across constructors is unsafe because Nukems/Enabler constructors load DLLs and can cause callbacks. A nonblocking construction gate also needs outer routing changes: current D3D12 Create treats a temporarily unavailable replacement as permission to try native NGX, which is not equivalent to a retryable initialization state. This boundary should be solved as a distinct publication/routing change, not by quietly returning null from a locked factory.

Shutdown needs separate ordering work too. The FFX provider's shutdown is a no-op, while DLL providers forward native shutdown; device-specific shutdown must not be replaced by a global stop that disables other devices. Handle-level locks and the creation checks in this checkpoint do not serialize native global shutdown against evaluations. No claim of fixing all lifecycle races or the game's reported crash follows from this patch.
