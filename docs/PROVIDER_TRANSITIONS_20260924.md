# Replacement-provider transition admission — 2026-09-24

## Source defects and behavior

The per-handle registry prevented Release racing Evaluate for the same public token, but provider Init/Shutdown bypassed it entirely. Shutdown could enter the DLL while an Evaluate/Create/Release/query was still active. Also, the exported D3D12/Vulkan shutdown routes ignored replacement-provider failure and cleared local state anyway, reporting success after incomplete teardown.

ProviderCallAdmission now separates lifecycle transitions from ordinary operations across the one shared replacement provider, including its D3D12 and Vulkan entry points. A transition is admitted only when no operation/transition is active; an operation is admitted only outside a transition. Conflicting calls return FAIL_NotInitialized without waiting. A movable scope owner releases admission on normal return and exceptions. The short metadata mutex is never held while calling native/provider/application code. Concurrent ordinary operations remain allowed as before; this change is transition exclusion, not universal provider thread safety.

All 22 NVSDK-result entry points in Nvngx_FG are covered. The three Create variants clear OutHandle even when admission is denied. Both exported shutdown coordinators hold provider transition admission across native shutdown, provider shutdown and local cleanup. A busy provider therefore prevents the exported shutdown from touching native ownership in the first place. A later provider error propagates and preserves local cleanup state for retry; a successful native shutdown is not rolled back or repeated because its existing ownership ledger already records completion. A provider with an outstanding Init attempt is closed even if the current configuration selector has changed to None. An absent provider or unsupported API closes as a no-op without loading a DLL.

The shutdown callback supplied to the coordinator must be used synchronously within its admitted scope; it is not a stored/deferred teardown API. No game/driver settings, SL1 runtime policy, installer behavior or frame multiplier code changes.

## Init cleanup footprint follow-up

A capability query can publish the provider without ever initializing it. Propagating that provider's Shutdown failure would incorrectly reject ordinary DLSS-only shutdown. Five provider Init routes now record a per-API/device cleanup footprint immediately before calling the SDK. Shutdown skips devices with no attempt; successful close clears only the affected footprint (or all for global close). Failed or throwing Init may have partially allocated resources and therefore keeps its cleanup obligation; failed or throwing close keeps it for retry. Null Init devices are rejected before invoking the SDK. Published-but-unused providers close without calling the SDK.

These sets are accessed only under transition admission. They track attempted initialization, not readiness, COM ownership, reference counts or handle generations. Repeated Init behavior remains forwarded. The Combo follow-up below tracks child-level cleanup separately.

## Combo partial-child shutdown follow-up

Combo previously called both child Shutdown methods again on every retry. If Arturs completed but FFX failed (or the reverse), retry could close an already closed SDK while the other still required recovery. Combo now records each child Init attempt separately per D3D12 device, before entering that child. A successful child close clears only that child/device obligation immediately; failure or exception retains it. Unknown-device and unused-child close are no-ops. Global close clears only the children that succeeded. A failed first child result still allows the second child to attempt cleanup, and the first failing result is preserved. An exception leaves not-yet-called children pending, and retry resumes without repeating completed children.

The existing outer transition gate serializes these sets; no mutex is held over a child call. The change does not redefine FFX's no-op Shutdown as feature destruction, retire outstanding Combo handles, or fix partial Create rollback. Those require explicit feature ownership/generation handling next.

## Handle API identity follow-up

The shared registry previously identified a token without checking which API created it. A Vulkan token supplied to D3D12 Evaluate/Release (or the reverse) could therefore reach the wrong native API, and a mistaken Release could retire another API's live token. All three Create routes now publish immutable D3D12/Vulkan identity. Both Evaluate and Release routes reject a mismatched token with FeatureNotFound before native handle use. A rejected wrong-API Release does not retire it, so the original API can still release it normally.

This solves API identity only. Device identity and initialization generations remain separate work; the Vulkan Create variant without an explicit device needs a verified association instead of blindly using mutable global state.

## Focused checks

- 42 new extracted API-routing checks cover all three Create routes, wrong/right API Evaluate/Release, failed Release retry, retired tokens and failed Create output clearing. Affected Release admission checks expand from 18 to 20. D3D12 shader work is replaced by a stand-in only after the actual API guard.
- 85 new extracted entry-prefix/production-admission checks cover all 22 provider SDK entry points, busy transition/operation routing, empty Create outputs, moved leases, reentrant callback threads, exceptions, admission retained through caller cleanup, and no-op unsupported/absent-provider shutdown. Native/GPU bodies beyond ordinary admission are stand-ins.
- 104 new checks execute all five complete Init bodies and the real shutdown coordinators with fake SDK results: never-initialized provider, wrong/null device, busy/Pending/unavailable lookup, failed/throwing Init and close, retry, global clearing, and independent API footprints.
- 132 new extracted Combo Init/Shutdown checks exercise both child error permutations, global/per-device close, unknown device, retry without double close, repeated Init, exceptions before/after the first child, failed Init cleanup and multi-device retention. The 44 existing affected Combo Release checks also pass.
- Actual exported native/provider shutdown checks expand from 43 to 52: blocked shutdown changes neither API/device ownership nor local state, provider failure is propagated, and retry does not repeat a successful native shutdown.
- Affected 36 provider publication-route and 20 per-handle Release-route checks pass with the actual new coordinator bodies.
- Negative control: removing the D3D12 Init-footprint insertion in a temporary source copy fails check 7 of the new complete-Init suite; production files were not mutated.
- Full Windows build/format/package outcome will be recorded after CI completes. These CPU checks do not establish that the Witcher loading/toggle crash is fixed.

## Remaining lifecycle work

This excludes simultaneous teardown/operation execution; it does not yet associate replacement handles with a device/generation or define all partially successful shutdown states. In particular, an admitted successful shutdown followed by Init must not make an old handle valid again. FFX shutdown is currently a no-op, DLL shutdown forwards teardown, and Combo now remembers independently completed child closes; those contracts must be handled explicitly before automatic handle retirement. Shared HUD/depth resources and concurrent ordinary Evaluate calls remain outside this transition fix. Native Init before the replacement-provider call and other global State/Config updates are not made one transaction by this change.

Next work remains device/generation and outstanding-feature ownership, including release/recovery of resources whose parent shutdown did not free them. Do not merge unfinished lifecycle work into aurora or describe compatibility as fully verified. Real-game tests remain deferred by the user.
