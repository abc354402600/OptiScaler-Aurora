# Private feature creation rollback — 2026-09-26

## Confirmed source defects

`Nvngx_Combo::D3D12_CreateFeature` published its wrapper before either child
completed creation. If a child failed, it ignored the successful child's Release
result and deleted the wrapper. In particular, the newly explicit FFX/Combo
release failure handling could not recover ownership already lost during Create.
An exception between child calls also left an unpublished child outside the
public token registry. Draining only published tokens before parent shutdown was
therefore incomplete.

`Nvngx_FFX::D3D12_CreateFeature` acquired a raw COM device reference before
allocating its wrapper, published that wrapper before reading parameters, and
did not reject a null command list or successful GetDevice with a null output.
Allocation and parameter-read exceptions could leak ownership or expose partial
output. These are code-level findings; no claim is made that they explain every
reported Witcher/ZZZ crash.

## Changes

- FFX keeps its wrapper and device reference private with RAII. It publishes
  output only after parameter reads finish. Invalid arguments, initialization
  errors, device-query errors, allocation failures and exceptions leave null
  output. FFX context creation still occurs later in Evaluate.
- Combo registers private ownership before calling either child. Successful
  children remain recorded when rollback fails or throws; the public output
  stays null. The pending record owns a COM reference so its device address cannot
  be reused before retry completes. Failed first-child creation no longer starts
  the second child needlessly.
- Shared `ReleaseChildren` preserves the existing partial-release retry rules
  for both published and private wrappers. Successful cleanup is not repeated.
- Internal `D3D12_DrainPending` runs before native shutdown even when there are no
  public tokens. Combo's direct Shutdown also checks its private ledger. Failed
  private cleanup blocks parent teardown and preserves Init obligations.
- An exception inside the third-party Arturs Create, a failure with non-null
  output, or success with null output leaves uncertain ownership. No guessed
  pointer is sent to Release; shutdown of that device is refused and logged until
  process restart. This intentionally prioritizes retention over false success.
- Only short metadata operations hold the private ledger mutex. Child calls run
  outside it. Exclusive outer transition admission excludes Shutdown from
  concurrent Create; ordinary Create calls can still execute concurrently.
- Provider drain no longer treats an empty public registry as proof that no
  private objects remain. If a provider exists during process detach, it refuses
  to start the drain under the possible loader lock, including an empty registry.

## Validation

Local extracted-source C++ tests compiled with Zig's C++ driver:

| Suite | Checks | Scope |
| --- | ---: | --- |
| `test_ffx_create.py` | 15 | Entire production Create/Release and real wrapper types; counted COM, injected allocation and parameter exceptions |
| `test_combo_create.py` | 56 | Complete Create/rollback/private drain/Shutdown, actual ledger members, SDK stand-ins, device isolation and concurrent Create |
| `test_provider_shutdown_drain.py` | 50 | Actual outer drain/coordinators/registry; includes four new private-drain cases |
| `test_combo_release.py` | 44 | Affected published partial-release behavior |
| `test_combo_shutdown.py` | 132 | Affected child close footprints; private hook stubbed here and real in new suite |
| `test_ffx_release.py` | 22 | Context destruction and device-reference ordering |
| `test_shutdown_routing.py` | 56 | Exported shutdown routing |
| `test_provider_handle_api.py` | 42 | Existing API-specific token routing |

Three in-memory negative controls were rejected by executable assertions:
transferring the FFX device reference before parameter reads; treating live
children as successful rollback; restoring the outer empty-registry early
return. Production files were not mutated by these controls.

The two new suites are included in the Windows build workflow. Full DLL build,
MSVC test results and artifact identity are recorded below once available.

## Remaining scope

This closes the known owned Combo partial-Create gap; it does not establish
arbitrary third-party exception recovery. Repeated Init with old features,
native Init transaction ordering, and concurrent ordinary Evaluate scratch-state
access remain separate lifecycle work. No installer changes, game files, driver
profiles, native SL1 policy or frame-multiplier algorithms were changed.
Actual GPU/game behavior remains unverified at the user's request. No aurora
synchronization or Release is implied by these focused checks.
