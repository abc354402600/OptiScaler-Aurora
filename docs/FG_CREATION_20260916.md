# FG creation failure boundary — 2026-09-16

Continuation from `2bf68763` on `Compatibility-fixes`. The user currently cannot test Witcher and does not own ZZZ; actual game verification is pending and must not block independent source-level work. New features are deferred. No main-branch merge is justified by CPU tests alone.

## Confirmed defects repaired

- Both exported Vulkan FG Create routes logged `(*OutHandle)->Id` unconditionally after provider creation. Failure leaves the output null, so the diagnostic path could itself crash. These routes now validate/clear output and only inspect the handle after successful creation with a non-null result.
- The D3D12 and Vulkan provider adapters previously returned early for an unavailable provider before clearing a caller's old output, and published wrappers when a native provider returned success with a null native handle. A shared production helper now clears output before provider lookup, retains unpublished wrapper ownership during creation, and publishes only a successful, non-null native handle.
- D3D12 exported creation clears output before command-list validation and only records/logs native or replacement handles on a successful result. This prevents reading stale outputs on error.

Failed native creation remains the provider's responsibility: Aurora does not guess how to release a pointer written alongside a failure result. C++ exceptions leave output empty and the unpublished wrapper destroyed; this helper does not claim to catch structured exceptions or make foreign binaries safe.

## Focused validation

16 Windows C++ checks exercise the production creation helper and registry: null output without native invocation, clearing stale output before callback, failure/unavailable-provider behavior, no publication on failure, successful return with no native handle, failure that writes a pointer, exception cleanup, successful publication/read and release exactly once. These are CPU failure-path checks, not GPU compatibility evidence.

## Global lifecycle audit remains open

`Nvngx_FG::getProvider` still constructs and exposes a shared provider before fallback validation completes. A concurrent call could observe that provider while another call replaces it. A mutex held across constructors is unsafe because Nukems/Enabler constructors load DLLs and can cause callbacks. A nonblocking construction gate also needs outer routing changes: current D3D12 Create treats a temporarily unavailable replacement as permission to try native NGX, which is not equivalent to a retryable initialization state. This boundary should be solved as a distinct publication/routing change, not by quietly returning null from a locked factory.

Shutdown needs separate ordering work too. The FFX provider's shutdown is a no-op, while DLL providers forward native shutdown; device-specific shutdown must not be replaced by a global stop that disables other devices. Handle-level locks and the creation checks in this checkpoint do not serialize native global shutdown against evaluations. No claim of fixing all lifecycle races or the game's reported crash follows from this patch.
