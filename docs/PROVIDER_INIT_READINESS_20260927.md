# Provider Init readiness — 2026-09-27

## Confirmed defect and bounded change

The replacement provider tracked attempted initialization only. A second Init on the same API/device could enter the SDK again, including after an unsuccessful Init or partially completed Shutdown. Attempt ownership is necessary for cleanup but does not establish readiness.

Nvngx_FG now maintains readiness separately from attempted-Init cleanup obligations. Its five complete D3D12/Vulkan Init routes use the same production helper under exclusive transition admission:

- A successful existing API/device returns success without another SDK Init or allocation; Init variants share that identity.
- A failed or throwing SDK Init retains cleanup ownership but is not ready. Repeat Init returns NotInitialized until shutdown completes.
- Both bookkeeping allocations happen before the SDK callback. An allocation exception rolls back unpublished readiness without entering the SDK; successful SDK completion requires no subsequent allocation.
- An admitted shutdown clears selected readiness before feature drain, including partial/failed drain. A rejected busy shutdown changes nothing. Other devices and APIs retain their state.

No installer, runtime replacement policy, SL1 policy, driver setting or installed game was changed.

## Focused evidence

Tests extract actual production helper/coordinator/Init bodies and use fake SDK callbacks; they do not simulate GPU execution.

Local Zig C++ checks passed:

- 152 complete provider Init footprint/readiness checks (48 added).
- 55 shutdown drain checks (5 added).
- 17 new Init allocation-fault checks.
- Affected regression fixtures: 85 call admission, 36 publication routes, 56 exported shutdown routing checks.

Three in-memory negative controls failed their executable assertions as expected: reporting failed Init as ready, retaining selected readiness after partial shutdown, and moving attempted-Init allocation after SDK entry. Production files were not mutated for these controls.

The new allocation suite is included in the Windows build workflow. Full Windows DLL/build evidence is recorded below after completion.

## Explicit remaining boundaries

This patch controls repeated replacement-provider Init. It does not make exported/native Init globally transactional: outer wrappers can still publish paths/metadata or initialize the native SDK before reaching provider admission. It also does not add readiness checks to every Create/Evaluate route. Those routes require a separate ordering review rather than a claim that this helper solves all lifecycle state.

Concurrent ordinary Evaluate still needs review of shared HUD/depth scratch state, device affinity and GPU lifetime. No blanket exclusive SDK lock or thread-local lock bypass was introduced. Real-game Witcher/ZZZ/NTE behavior is unverified; game testing remains deferred at the user's request. These remaining boundaries mean the main-branch synchronization gate has not yet been reached.
