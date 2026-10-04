# OptiScaler Aurora v1.1.2

[简体中文](RELEASE_NOTES_AURORA_V1_1_2.md) | **English**

This maintenance release adopts two new upstream compatibility fixes and includes all v1.1.1 fixes. Download the complete `OptiScaler_Aurora_v1.1.2_*.7z`; verify it against `SHA256SUMS.txt`.

- In normal builds, XeLL module lookup acquires the Windows reference for the selected DLL by address instead of selecting another same-name module. Remove whole-export redirection from this loading path. Uninitialized, unrelated-name and flagged queries retain original handling. Preserve the existing low-latency-input build route.
- Disable unsupported FFX/Combo Nvngx replacement options and hide Force XeLL under Vulkan, retaining applicable LatencyFlex controls. This does not add Vulkan FG backends.

DLSS SR/RR/FG 310.9.1, Streamline 2.14.1 and optional Neural Rendering runtimes are unchanged. Native SL1, DualFeature=false, the 6X path and v1.1.1 swapchain/Control Resonant fixes are preserved.

Exit the game, back up configuration, extract the complete package and run setup, ensuring the active proxy is updated. Keep winmm.dll for NTE and verify Aurora v1.1.2 in the overlay. Do not change a working FG route merely to update.

Focused checks execute the production query function and menu conditions: 118 checks in normal mode and 108 in low-latency-input mode. Formal publication follows the tagged Windows build, configured compatibility tests, runtime inventory and archive checks.

No new game/GPU or performance validation was performed. This does not establish universal XeFG concurrency safety, FPS gains, or resolution of all Witcher crashes/ZZZ 11008 errors. The large upstream D3D12 state-tracking rewrite is excluded.

[Audit](UPSTREAM_AUDIT_20261005.md) · [Guide](GUIDE.en.md)
