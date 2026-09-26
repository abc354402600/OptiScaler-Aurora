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

### Next implementation boundary checked against the current source

- Exported D3D12 `Init_Ext` publishes path/application metadata and calls native
  `RunDx12Init` before it reaches `Nvngx_FG::D3D12_Init_Ext` and its transition
  admission. A busy provider can therefore reject after earlier side effects.
  The analogous Vulkan entry and delegated Init variants need the same review.
- Direct replacement-provider Init functions still admit repeated calls using
  the attempted-Init sets as cleanup records, not readiness/idempotence records.
  Native `NativeDeviceLifecycle::Initialize` already returns success for a known
  ready device. Do not incorrectly replace attempted-Init obligations with a
  success-only set or allow a failed partial Init to masquerade as ready.
- Any new outer Init coordinator must acquire admission before metadata/native
  side effects and use an explicit internal delegation route. A thread-local
  "already owns transition" shortcut would let native callbacks bypass exclusion;
  the existing `_skipInit` flags only describe path/native-call delegation and
  must not become blanket authorization for reentrant mutation.
- D3D11, D3D12 and Vulkan publish shared metadata through individually safe
  snapshots. That does not make the combined path/application/project/logging
  updates atomic. Direct `NVNGXProxy::InitDx12/InitVulkan` consumers also read these
  snapshots and need consideration when defining the outer transaction.
- Ordinary replacement Evaluate still admits concurrent readers. D3D12 uses
  process-wide `_hudCopy`; `Nvngx_DllProxy::D3D12_EvaluateFeature` has a static depth
  ring counter, provider-wide depth buffers and uses `currentD3D12Device` for
  allocation. Per-token registry lifetime protection alone does not serialize
  those mutable resources, nor prove their GPU lifetime or device affinity.
  Simply changing every ordinary call to a transition would also reject valid
  read/query callbacks; use a deliberately scoped design and explicit tests.

## Adjacent publication-allocation follow-up

After the Combo checkpoint `f2cd07b2`, review found a second ownership gap in
`CreateProviderHandle`: the wrapper was allocated before the native call, but
`ProviderHandleRegistry::Publish` still allocated its hash-map node/buckets after
successful native creation. A bad allocation then lost the native handle despite
successful child creation.

The creation helper now reserves that registry entry before calling the provider.
Reservations are invisible to identity routing, Read, Release and LiveKeys. An
RAII scope removes unpublished reservations on error or exception; successful
publication changes visibility without another map allocation. Existing
Prepare/Publish callers remain supported. No SDK callback runs under the registry
mutex, and immutable public identity is exposed only after creation finishes.

`Aurora_Provider_Publication_Allocation_Tests.cpp` adds 34 executable checks with
allocation failure injected into the actual standard-library allocation path:
entry/node/bucket failures precede native callbacks, and all allocations may fail
after native success without preventing publication. It also checks hidden
reservation visibility, failure/exception cancellation and later Release.
Existing 32 registry, 16 creation, 20 Release admission, 42 API routing, 50 drain
and 44 Combo Release checks passed for the affected code. Removing reservation
in temporary header copies fails the new test at check 3. The new suite is part
of Windows CI. This does not infer ownership from a failing third-party Create
that writes an arbitrary non-null output; its pre-existing conservative contract
is unchanged.

## Windows validation: private rollback checkpoint

Code `f2cd07b22c5c34135df158e1a35af76e1e35fee4`: Windows run `36249120011`,
job `108423715871`, full DLL build, MSVC checks, packaging and upload succeeded.
Format run `36249120005` succeeded. MSVC logs confirm 15 FFX Create, 56 Combo
Create, 50 drain, 22 FFX Release, 44 Combo Release and 132 Combo Shutdown checks.

Artifact `OptiScaler_Aurora_v1.0_20260926_compat_f2cd07b2.7z`, id `10908468079`,
234784314 bytes, Actions digest
`sha256:b249fef51c922f8827d5ffad5f618ca2bd93a11d9461d9e7d1a088b193b88911`.
The following allocation-reservation checkpoint `11bf92ec` requires its own
final build record; this earlier artifact does not contain that follow-up.

## Final Windows validation: allocation-reservation follow-up

Code `11bf92ec3067fd7ff1bc57cb5a9e8f416ae52755`: Windows run `36249544744`,
job `108424880946`, full DLL build, MSVC tests, package and upload all succeeded.
Format run `36249544709` succeeded. MSVC confirms 15 FFX Create, 56 Combo private
rollback, 50 drain, 32 registry and 16 creation checks. The allocation-injection
suite passes **33 checks with MSVC**, versus **34 with the local Zig/STL**: its
eight allocation-budget trials branch according to each STL's node/bucket
allocation count, so the number of assertion calls differs by implementation.
Both exercised pre-callback allocation failures and allocation-free publication
after native success; this is expected, not a missing Windows test.

Artifact `OptiScaler_Aurora_v1.0_20260926_compat_11bf92ec.7z`, id `10907889573`,
234789475 bytes, Actions digest
`sha256:d6fdf0374dfeb65e5b1b876cbf0e34b24d6b3d5764da78592c5d7d9c3f230cc7`.
Both code checkpoints are pushed to `Compatibility-fixes`. No Release, game
tests, installed-game changes or aurora synchronization occurred. The concrete
remaining Init/Evaluate boundaries above remain the next work.
