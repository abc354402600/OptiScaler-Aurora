# OptiScaler Aurora v1.1.1

[简体中文](RELEASE_NOTES_AURORA_V1_1_1.md) | **English**

This maintenance release includes the October 4 compatibility fixes. Download the complete `OptiScaler_Aurora_v1.1.1_*.7z` package from the release assets; verify it against `SHA256SUMS.txt`.

- Stop misclassifying zero-size swapchain requests as overlays across nine ordinary, DLSSG and wrapped creation paths.
- Apply scoped Control Resonant frame-generation swapchain policies, honoring explicit user settings.
- Add `[NvApi] DisableOTA=auto`: normally false, automatically true for Control Resonant, with explicit true/false overrides. Apply it before the DLSSG early return. Restart the game after changing the option.
- Update the Chinese-first homepage, separate English documentation and package instructions.

DLSS SR/RR/FG remain 310.9.1 and Streamline remains 2.14.1. Optional Neural Rendering retains the 310.8 runtime / 2.13 plugin. Native Streamline 1.x, downgrade protection, DualFeature=false and the existing 6X path are preserved. The discontinued RC3 installer is not included.

Exit the game, back up configuration and update through the complete package's `setup_windows.bat`, ensuring the active proxy is updated. NTE continues to use `winmm.dll`. Verify Aurora v1.1.1 in the in-game panel. A missing new configuration key defaults to auto.

The production batch passed 315 focused checks, two negative-control mutations, a full Windows DLL build, configured compatibility tests, runtime inventory and packaging checks. The formal tag workflow rebuilds and publishes only after all required checks pass.

No new game/GPU validation was performed. This release does not establish that all Witcher 3 high-multiplier crashes, ZZZ 11008 errors or other compatibility problems are fixed, and makes no FPS improvement claim. Previously documented resource rebuilding, GPU retirement and global initialization limitations remain.

[Maintenance evidence](COMPATIBILITY_MAINTENANCE_20261004.md) · [Game compatibility](COMPATIBILITY.en.md)
