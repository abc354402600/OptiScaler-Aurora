# Installation and usage

[简体中文](GUIDE.zh-CN.md) | **English** · [Home](../README.en.md)

For the Aurora v1.1 release package. It uses the traditional `setup_windows.bat` flow, not the discontinued automatic multi-entry installer.

## Install

1. Download the complete `.7z` from the [v1.1 release](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1). `SHA256SUMS.txt` is provided there. Do not copy only `OptiScaler.dll`.
2. Find the actual game executable. Task Manager → game process → **Open file location** can help; fully exit the game before installation. UE games often use `Binaries\Win64`; the launcher folder may be different.
3. Back up existing settings and extract every package file there. Identify any same-name third-party loader before overwriting it.
4. Run `setup_windows.bat` and select a proxy. `dxgi.dll` is a common starting point; use `winmm.dll` for Neverness to Everness. Use setup/removal when changing proxies and do not leave multiple Aurora proxies.
5. Check core setup and Runtime Sync separately. Setup may continue after synchronization fails; read warnings and reports.
6. Launch the game and press `Insert`. The Windows on-screen keyboard (`Ctrl + Win + O`) can help; some keyboard layouts may need `Alt + Insert`.

## Settings

- Confirm basic loading and rendering, then change one setting at a time. Avoid simultaneously changing the proxy, FG routes and multiple runtimes.
- `FG Input` and `FG Output` select different parts of the pipeline. Save and fully restart after changing routes.
- RTX 40 MFG reaches 6X in tested configurations, not necessarily in every game.
- Neural Rendering is experimental. Adjust model resolution to balance cost and quality; the earlier 40% suggestion is a starting point, not a universal optimum.
- Keep the default `DualFeature=false`. `Run inside the upscaler` is optional and can cause corruption or instability in some games.

## Runtimes, updates and removal

v1.1 bundles DLSS SR/RR/FG 310.9.1 and Streamline 2.14.1. Optional Neural Rendering keeps its 310.8 runtime / 2.13 plugin. Runtime Sync uses actual versions, groups and verification results to decide what to replace. **Preservation is not necessarily a failure:** newer files, native SL1 and unidentified groups should be retained.

After game updates or launcher verification, wait for completion, exit the game, run `Check_DLSS_Runtime.bat` and read the result. Do not force-overwrite unidentified groups.

Uninstall with the generated `Remove_OptiScaler.bat`. Keep scripts, manifests and backups until restoration succeeds. On failure, close the game and address the reported cause; do not delete backups first.

Runtime Sync requires Windows PowerShell and is skipped by setup under Wine. Proton DLL overrides must match the proxy, for example `WINEDLLOVERRIDES="dxgi=n,b" %command%`. This does not establish support for every Linux game.

## Troubleshooting

| Symptom | Check first |
|---|---|
| Overlay unavailable | Actual executable folder, loaded proxy, supported game upscaler input and shortcut. |
| Game no longer launches | Proxy conflicts, other loaders and mixed versions. Do not indiscriminately delete DLLs. |
| Only 2X available | Loaded DLSSG/Streamline, FG routes, saved settings and restart state, not just bundled versions. |
| Stops working after an update | Restored game files; run the runtime check and retain its report. |
| Neural Rendering corruption | Disable `Run inside the upscaler`, restart if needed and keep other variables unchanged. |
| Missing files or component error | Exact filename, launcher restoration and security-software records. The symptom alone does not identify the cause. |

Some Capcom mod setups may separately require a compatible REFramework; Aurora does not bundle it. Games requiring launcher authentication or verification must complete their normal startup process.

For reports include Aurora/game versions, GPU/driver, proxy, FG input/output, steps and relevant `OptiScaler.log`, after reviewing personal paths. See [compatibility and limitations](COMPATIBILITY.en.md).
