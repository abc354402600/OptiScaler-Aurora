# NGX initialization snapshots — 2026-09-17

## Owned search paths

Each D3D11/D3D12/Vulkan UpdateInitPaths previously cleared a shared string vector and allocated an unowned raw pointer array. Its entries referenced that vector's string storage, so another Init or GetFeatureCommonInfo could invalidate pointers still being passed to native code. Arrays also had no corresponding owner/release.

NgxPathSnapshot now owns both strings and the pointer array. Each adapter retains a shared immutable snapshot through its native/provider calls and nested delegated calls. Replacing the cached paths uses a short metadata lock and does not invalidate active snapshots; no lock is held during native calls. All 11 exported Init adapter sites retain their owner. The three internal proxy Init helpers and the separate DlssNr_Proxy caller also retain the owning result of GetFeatureCommonInfo. Both owning helper results are marked nodiscard.

Search ordering is unchanged: explicit overrides, Aurora path, caller paths, executable path and discovered runtime paths keep their previous positions. Vulkan's existing bad-length workaround remains. GetFeatureCommonInfo adds the selected DLSS directory only to its own snapshot, eliminating repeated append growth in the shared cache. The cache still means the most recently published search path list; this does not establish per-device search configuration or synchronize other Config/State fields.

32 local extracted-production checks pass: all three actual builders, representative actual Init adapter prefixes, GetFeatureCommonInfo, Unicode/spaces, override ordering, caller-buffer mutation, replacing the cache while an old owner remains, owner reclamation, nested delegated calls, exception unwind, empty lists and Vulkan's bad-length path. Four concurrent writers/readers publish and inspect 4,000 snapshots. Test SDK/Config/native boundaries are stand-ins, not a driver or GPU test. Existing shutdown extraction is adapted for the helper's owning return type; unrelated installer suites are not rerun.

The native calls consume these snapshots during the documented call boundary. This does not promise indefinite pointer validity for a third-party implementation retaining caller arguments after Init returns. Shared application/project metadata, logger state and replacement-provider shutdown remain separate follow-ups. No installer, shader, SL1 or 6X change; no main merge or Release in this checkpoint.
