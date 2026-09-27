# Exported NGX transition admission — 2026-09-27

## Defect and repair

The old thread-local `_skipInit` flag propagated delegated Init state to any SDK callback reentering a public Init on the same thread. Such a callback could skip native Init/path publication as if it were an intended internal delegation. Independently, exported Init wrappers could interleave global metadata/device updates across APIs, and exported Shutdown could enter during an exported Init before provider-level admission was acquired.

All 19 public D3D11/D3D12/Vulkan Init and Shutdown variants now enter one shared, nonwaiting transition gate before their private core executes. Callback reentry and overlapping exported transitions return NotInitialized without entering the core. Lease destruction releases admission after normal returns, failures and exceptions; no mutex is held across SDK calls. An inline shared gate also excludes calls across translation units.

Internal delegation is now explicit through file-local NgxCore functions with a `delegated` parameter. SDK callers can only reach the original public ABI, which always enters the gate and starts with `delegated=false`. The thread-local skip flags and scope objects are removed. The original native/provider return policy, argument overrides, and cleanup order are preserved in this structural step.

## Focused checks

- 590 checks execute all 19 actual public wrappers, including every pair of nested Init/Shutdown calls, cross-thread rejection, cross-translation-unit sharing, error return and exception unwind. SDK/core bodies in this fixture are counted stand-ins.
- 388 checks execute all 13 complete production Init chains (private cores plus public wrappers), with fake SDK, provider and state services. Each normal fresh chain calls native Init once and publishes paths once. Reentry from native and delegated provider phases cannot add path/metadata writes or native/provider calls. Exceptions release outer admission.
- Updated existing path ownership suite: 32 checks, now passing explicit internal delegation rather than a thread-local flag.
- Actual shutdown-body regression: 56 checks with the new gate and private entry functions.
- Metadata ownership regression: 39 checks.
- Two in-memory negative controls are rejected: returning success on busy admission, and incorrectly starting another native Init on an internal delegated call. No production files were mutated for negative controls.

The new complete-chain suite is part of the full Windows build workflow. The 590-wrapper suite replaces the old 24 checks of the removed thread-local scopes; do not count both as current coverage. No unrelated installer suites were run.

## Remaining transaction boundary

This gate serializes exported transitions only. Ordinary Evaluate, direct native/provider calls and independent metadata consumers retain their existing admission. Therefore a provider/native busy result discovered later in an already-admitted Init can still follow earlier path/metadata publication. Direct proxy readers still acquire paths and metadata separately. An admitted partial failure is not automatically rolled back by this patch, and global early-success flags are not a substitute for per-device readiness.

Next: join the outer transaction to native/provider admission without thread-local bypass or locking across SDK callbacks, and publish an owned combined configuration only at the appropriate commit point. Preserve cleanup ownership after partial native success rather than pretending failure erased SDK state. Then address shared HUD/depth buffers and concurrent ordinary Evaluate. These are explicit outstanding items; this checkpoint does not meet the aurora synchronization gate or prove a Witcher/ZZZ crash fixed in-game.

No installed game, runtime deployment, driver profile, SL1 protection, MFG multiplier policy or installer was modified. Real-game testing remains deferred as requested.
