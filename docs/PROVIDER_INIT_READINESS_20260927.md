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

## Next-stage source map (reviewed this turn)

- `inputs/NVNGX_DLSS_Dx12.cpp`: Init, Init_ProjectID and Init_with_ProjectID delegate to Init_Ext; Init_Ext publishes application metadata and performs native Init before provider admission. Several wrappers also return success from the global nvngxDx12Inited/device check. A complete fix must cover those early returns rather than only the five provider bodies changed here.
- `inputs/NVNGX_DLSS_Vk.cpp`: Init/Init_Ext/ProjectID routes delegate toward Init_Ext2. ProjectID_Ext publishes project metadata even after the delegated call returns failure. This is another transaction-ordering case to cover, not a separate claim of a reproduced game crash.
- `proxies/NVNGX_Proxy.h`: direct InitDx12/InitVulkan readers acquire paths and application metadata separately. A consistent outer transaction must include these consumers or pass an owned combined configuration explicitly.
- `framegen/nvngx/Nvngx_FG.cpp`: Evaluate reads provider-wide _hudCopy and global currentD3D12Device. `Nvngx_DllProxy.cpp` uses a static depth-ring counter and provider-wide depthCopy[2]. CPU admission, per-device ownership and GPU resource retirement are different requirements.

Next implementation acceptance cases: rejected outer Init must leave global configuration/native callback counts unchanged; delegated internal Init must succeed without admitting external callback reentry; failed provider/native transitions must not publish global success; different devices/APIs must not silently inherit another call's configuration. Include allocation/exception paths and shutdown overlap. Preserve native SDK error policy deliberately rather than turning every optional native-backend failure into a fatal error.

## Full Windows validation

Code `8f35f6a6d118c1b5e60e7c0d7a852b46a835221e` is pushed to Compatibility-fixes. Windows run [36282357765](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/36282357765), job 108516500119, completed successfully: full DLL build, lifecycle checks, package and upload. Format run [36282357759](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/36282357759) also passed; local changed-line formatter checked two C++ files with zero violations.

The Windows log confirms 152 complete Init, 55 shutdown drain and 17 allocation checks, plus affected 85 admission, 36 publication-route and 56 shutdown-route checks. Local focused total is 401 checks, of which 70 were added in this patch; the Windows workflow additionally executes its existing compatibility build gate. No legacy RC2/RC3 installer suite was invoked.

Artifact: `OptiScaler_Aurora_v1.0_20260927_compat_8f35f6a6.7z`, id 10919586222, 234789344 bytes, GitHub artifact digest `sha256:d4c8614132f120d83e0453af7124464bee77e777ee1e9cebd63880e504637083`. This is build evidence, not a published Release or real-game compatibility result.
