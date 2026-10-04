# OptiScaler Aurora v1.1 — Runtime and compatibility update

[简体中文](RELEASE_NOTES_AURORA_V1_1.md) | **English** · [Home](../README.en.md)

[Download the release](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1). Aurora retains its RTX 40 MFG route and default `DualFeature=false`. The discontinued RC3 automatic installer is not included.

## Changes

- Official DLSS SR/RR/FG **310.9.1**, Streamline **2.14.1** and companion files. Optional Neural Rendering retains the **310.8 runtime / 2.13 plugin**, not 310.9.1.
- Runtime Sync preserves newer game files, native SL1 and unidentified groups instead of downgrading them.
- Improved frame-state and Reflex checks to avoid consuming mismatched or unready frame data.
- Fixed initialization failures being treated as success, lost cleanup ownership after partial initialization, failed handle creation and repeated release handling. Devices recorded as unready cannot continue Create/Evaluate, while owned cleanup remains available.
- Better coordination of multi-device calls, initialization and shutdown, complete shared-object publication, and malformed Runtime path rejection before initialization.
- HUD failure paths restore resource states. Copy operations check dimensions, format, samples and devices; CPU reentry/concurrency is rejected. Partial construction is cleaned up before retry.
- Optional depth-copy checks devices, descriptors and self-copy, protecting CPU state and retaining original depth when preparation fails.
- Vulkan timing ignores unavailable/failed query output and uses exception-safe locking.
- Reviewed upstream UE runtime-path, null-resource, format and interface-forwarding fixes, private Streamline binding improvements, incremental formatting and build traceability.

## Validation and limitations

The [formal build](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/37134982022) passed full Windows DLL compilation, configured compatibility checks, runtime version/SHA256 inventory, archive verification and publication. CPU checks and builds do not establish compatibility across all games/GPUs.

The user reported normal Witcher 3 RTX 4080 Laptop / DLSSG 310.9.1 / 6X operation. Loading, dynamic-MFG switching and mild flicker have not had comprehensive additional game testing. ZZZ `11008` and disappearing-file reports still lack matching logs; they are not confirmed fixed. Genshin and Star Rail bridge configurations have not all been tested.

Mismatched HUD/depth resources skip optional processing. Complete automatic device/size rebuilding, GPU completion/descriptor reuse/retirement and global rollback after late initialization exceptions remain future work. Incomplete global rollback, device-publication reorder and Vulkan query-pool reuse experiments were withdrawn from this release.

The build is unsigned. Download the `.7z` and `SHA256SUMS.txt`; retain configurations and original game backups. v1.0 remains available. Aurora does not modify global driver settings automatically or bypass anti-cheat.
