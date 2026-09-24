# Replacement-provider transition admission — 2026-09-24

## Source defects and behavior

The per-handle registry prevented Release racing Evaluate for the same public token, but provider Init/Shutdown bypassed it entirely. Shutdown could enter the DLL while an Evaluate/Create/Release/query was still active. Also, the exported D3D12/Vulkan shutdown routes ignored replacement-provider failure and cleared local state anyway, reporting success after incomplete teardown.

ProviderCallAdmission now separates lifecycle transitions from ordinary operations across the one shared replacement provider, including its D3D12 and Vulkan entry points. A transition is admitted only when no operation/transition is active; an operation is admitted only outside a transition. Conflicting calls return FAIL_NotInitialized without waiting. A movable scope owner releases admission on normal return and exceptions. The short metadata mutex is never held while calling native/provider/application code. Concurrent ordinary operations remain allowed as before; this change is transition exclusion, not universal provider thread safety.

All 22 NVSDK-result entry points in Nvngx_FG are covered. The three Create variants clear OutHandle even when admission is denied. Both exported shutdown coordinators hold provider transition admission across native shutdown, provider shutdown and local cleanup. A busy provider therefore prevents the exported shutdown from touching native ownership in the first place. A later provider error propagates and preserves local cleanup state for retry; a successful native shutdown is not rolled back or repeated because its existing ownership ledger already records completion. A published provider is closed even if the current configuration selector has changed to None. An absent provider or unsupported API closes as a no-op without loading a DLL.

The shutdown callback supplied to the coordinator must be used synchronously within its admitted scope; it is not a stored/deferred teardown API. No game/driver settings, SL1 runtime policy, installer behavior or frame multiplier code changes.

## Focused checks

- 85 new extracted entry-prefix/production-admission checks cover all 22 provider SDK entry points, busy transition/operation routing, empty Create outputs, moved leases, reentrant callback threads, exceptions, admission retained through caller cleanup, and no-op unsupported/absent-provider shutdown. Native/GPU bodies beyond ordinary admission are stand-ins.
- Actual exported native/provider shutdown checks expand from 43 to 52: blocked shutdown changes neither API/device ownership nor local state, provider failure is propagated, and retry does not repeat a successful native shutdown.
- Affected 36 provider publication-route and 18 per-handle Release-route checks pass with the actual new coordinator bodies.
- Full Windows build/format/package outcome will be recorded after CI completes. These CPU checks do not establish that the Witcher loading/toggle crash is fixed.

## Remaining lifecycle work

This excludes simultaneous teardown/operation execution; it does not yet associate replacement handles with an API/device generation or define all partially successful shutdown states. In particular, an admitted successful shutdown followed by Init must not make an old handle valid again. FFX shutdown is currently a no-op, DLL shutdown forwards teardown, and Combo can close only one child successfully; those contracts must be handled explicitly before automatic handle retirement. Shared HUD/depth resources and concurrent ordinary Evaluate calls remain outside this transition fix. Native Init before the replacement-provider call and other global State/Config updates are not made one transaction by this change.

Next work remains device/generation ownership and partial-child teardown, including release/recovery of resources whose parent shutdown did not free them. Do not merge unfinished lifecycle work into aurora or describe compatibility as fully verified. Real-game tests remain deferred by the user.
