<div align="center">

# OptiScaler Aurora / OptiScaler 极光版

**RTX 40 Multi Frame Generation · DLSS Neural Rendering · Automatic Runtime Sync**  
**RTX 40 多帧生成 · DLSS 神经渲染 · 自动运行库同步**

[![Aurora v1.0](https://img.shields.io/badge/Aurora-v1.0-7c3aed?style=for-the-badge)](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.0)
[![RTX 40 MFG](https://img.shields.io/badge/RTX%2040%20MFG-Up%20to%206X-76B900?style=for-the-badge&logo=nvidia&logoColor=white)](https://github.com/abc354402600/OptiScaler-Aurora)
[![DLSS](https://img.shields.io/badge/DLSS-310.9-00AEEF?style=for-the-badge)](https://github.com/abc354402600/OptiScaler-Aurora)
[![Streamline](https://img.shields.io/badge/Streamline-2.14-2563eb?style=for-the-badge)](https://github.com/abc354402600/OptiScaler-Aurora)

[![DLSS Neural Rendering](https://img.shields.io/badge/DLSS%20Neural%20Rendering-310.8-8b5cf6?style=flat-square)](https://github.com/abc354402600/OptiScaler-Aurora)
[![Runtime Sync](https://img.shields.io/badge/Runtime%20Sync-Auto%20Backup%20%7C%20Repair%20%7C%20Restore-16a34a?style=flat-square)](https://github.com/abc354402600/OptiScaler-Aurora)
[![Downloads](https://img.shields.io/github/downloads/abc354402600/OptiScaler-Aurora/total?style=flat-square&label=Downloads&color=0ea5e9)](https://github.com/abc354402600/OptiScaler-Aurora/releases)

<br>

<a href="https://github.com/abc354402600/OptiScaler-Aurora/releases/download/aurora-v1.0/OptiScaler_Aurora_v1.0_20260910.7z">
  <img src="https://img.shields.io/badge/⬇%20Download-Aurora%20v1.0-22c55e?style=for-the-badge" alt="Download Aurora v1.0">
</a>
<a href="https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.0">
  <img src="https://img.shields.io/badge/Release%20Notes-版本说明-334155?style=for-the-badge" alt="Release Notes">
</a>

</div>

---

**Aurora focuses on three things: better RTX 40 MFG compatibility, lower-cost DLSS Neural Rendering, and a much easier installation workflow.**  
**Aurora 主要解决三件事：更好的 RTX 40 多帧生成兼容性、更低开销的 DLSS 神经渲染，以及更省事的自动化安装流程。**

> **Aurora v1.0 = RTX 40 MFG + DLSS Neural Rendering + DLSS 310.9 + Streamline 2.14 + Automatic Runtime Sync**  
> **极光版 v1.0 = RTX 40 多帧生成 + DLSS 神经渲染 + DLSS 310.9 + Streamline 2.14 + 自动运行库同步**

---

## Why Aurora? / 极光版有什么不同？

| Feature / 功能 | Aurora v1.0 |
|---|---|
| RTX 40 Multi Frame Generation | ✅ Up to **6X** tested / 已验证最高 **6X** |
| DLSS Runtime | ✅ **310.9** |
| Bundled Streamline Runtime / 集成 Streamline 运行库 | ✅ **2.14** |
| DLSS Neural Rendering | ✅ **310.8** |
| Adjustable NR model resolution | ✅ 可调神经渲染模型分辨率 |
| Automatic DLSS / Streamline sync | ✅ 自动同步 |
| Original game runtime backup | ✅ 自动备份游戏原文件 |
| SHA256 deployment verification | ✅ 自动校验 |
| Runtime self-check / repair | ✅ 一键自检 / 修复 |
| Uninstall restore | ✅ 卸载自动恢复 |
| Neverness to Everness MFG crash fix | ✅ 异环 MFG 闪退修复 |
| Onimusha compatibility changes | ✅ 鬼武者兼容性增强 |
| Legacy Streamline 1.x protection | ✅ 自动识别 / 保护 / 自愈 |
| The Witcher 3 compatibility | ✅ SL1 protection + RTX 40 6X MFG |
| The Blood of Dawnwalker compatibility | ✅ DLSS 5 + RTX 40 6X MFG verified |

---

## 🚀 RTX 40 Multi Frame Generation / RTX 40 多帧生成

Aurora adds compatibility changes for NVIDIA Multi Frame Generation on RTX 40-series GPUs in supported games.

**Up to 6X Multi Frame Generation has been verified on tested titles.**

The RTX 40 MFG workflow uses the NVIDIA **DLSS-G / MFG runtime path**, rather than converting the feature to FSR frame generation.

Aurora 针对 RTX 40 系 NVIDIA Multi Frame Generation 增加了兼容性增强。

**目前已在实测游戏中验证最高 6X 多帧生成。**

RTX 40 MFG 使用 NVIDIA **DLSS-G / MFG 运行路径**，并非将该功能转换为 FSR 帧生成。

---

## ✨ DLSS Neural Rendering / DLSS 神经渲染

Aurora bundles the **DLSS Neural Rendering 310.8** runtime and supports adjustable model-resolution settings.

Reducing the model resolution can significantly lower Neural Rendering processing cost in compatible games, allowing users to find a better balance between image quality and performance.

Aurora 已集成 **DLSS Neural Rendering 310.8** 运行库，并支持调节神经渲染模型分辨率。

在兼容游戏中，降低模型分辨率可以明显减少 Neural Rendering 的性能开销，让用户根据自己的显卡与游戏自由平衡：

**Image Quality ↔ Performance**  
**画质 ↔ 性能**

Current bundled NVIDIA runtimes / 当前集成 NVIDIA 运行库：

- **DLSS 310.9**
- **DLSS Neural Rendering 310.8**
- **Streamline 2.14**

> [!NOTE]
> **DLSS Neural Rendering is experimental and game-dependent.**  
> **DLSS 神经渲染仍属于实验性功能，实际兼容性与效果取决于具体游戏。**

---

## ⚡ Runtime Sync v2 / 运行库检查、修复与恢复

新版工具将检查与修复分开：`Check_DLSS_Runtime.bat` 只读检查；需要替换时，在 `Aurora_Setup.bat` 中选择“备份后修复运行库”。安装末尾也可以选择同步。

扫描会记录散布在 UE Engine/Plugins、Data、Assets、Unity Plugins 等位置的 DLSS / Streamline 文件。只同步源包中已有、版本和 x64 架构均可识别的文件。游戏中发现 SL1 或未知代际时，整组原生 Streamline 都保留；DLSSNR 只记录，不覆盖。

每次替换前先校验备份，再保存操作清单，最后替换并核对 SHA256。游戏更新或用户修改过的受管理文件不会被静默覆盖；出现冲突会保留当前文件和备份。只读报告不代表已加载或已解锁 6X。

`Remove_Aurora.bat` 先恢复运行库，再按安装清单卸载。修改过的 `OptiScaler.ini`、其他 Mod、原有文件以及恢复记录会保留。不要手动删除 `OptiScaler/RuntimeSync` 和 `OptiScaler/AuroraSetup` 中仍需使用的备份。

完整操作说明和限制见 [Aurora Setup / Runtime Sync v2](docs/AURORA_SETUP_RUNTIME_V2.md)。

## 3-Step Installation / 三步安装

### 1. 完整解压发布包，选择游戏目录

可以先把完整发布包解压到独立文件夹，再运行 `setup_windows.bat` 或 `Aurora_Setup.bat`。输入单个游戏的目录或 EXE 路径，安装程序会扫描候选主程序。

任务管理器可能指向启动器，不能单独作为安装依据。比如异环应核对 `Client/WindowsNoEditor/HT/Binaries/Win64/HTGame.exe`；Win64 与 Win64r 并存时会同时列出，Win64r 仅作为较高优先级候选，不自动代选。

### 2. 手动选择游戏程序与 Proxy

每个菜单都需要 **输入对应的数字并按 Enter（回车）**。保留全部八种选择：`dxgi.dll`、`winmm.dll`、`version.dll`、`dbghelp.dll`、`d3d12.dll`、`wininet.dll`、`winhttp.dll`、`OptiScaler.asi`。ASI 方式需要已有 ASI Loader。

核对屏幕上显示的完整安装路径和 Proxy 后安装。已有未知 Proxy 不会被覆盖，其他 OptiScaler Proxy 未卸载时也不会叠加安装。安装末尾先检查，再由你选择是否备份并同步运行库。

---
### 3. Launch the game / 直接进入游戏

After setup completes, launch the game normally.

Press:

`Insert`

to open the OptiScaler overlay.

You can then configure:

- RTX 40 Multi Frame Generation
- MFG ratio
- DLSS Neural Rendering
- Neural Rendering model resolution
- DLSS presets
- Sharpness
- Other OptiScaler options

安装完成后正常启动游戏即可。

进入游戏按：

`Insert`

打开 OptiScaler 参数面板，然后根据需要配置多帧生成、DLSS Neural Rendering、模型分辨率与其他参数。

---

## Recommended Settings / 推荐设置

| Option / 选项 | Recommended / 建议 |
|---|---|
| RTX 40 MFG | Start with **6X** where supported / 支持时可优先尝试 **6X** |
| DLSS Neural Rendering | ✅ Enable / 开启 |
| Model Resolution | 40% recommended starting point / 推荐从 40% 开始尝试 |
| `Run inside the upscaler` | ⚠️ Keep disabled unless the game is known to work with it / 未确认兼容前建议关闭 |
| Proxy DLL | `dxgi.dll` for most games / 大多数游戏优先 `dxgi.dll` |
| Neverness to Everness / 异环 | Use `winmm.dll` / 推荐 `winmm.dll` |
| Save Configuration | Save settings at the bottom of the overlay / 调完后记得保存配置 |
> [!TIP]
> These are starting-point recommendations, not universal requirements.  
> 这些是建议起始设置，不代表所有游戏都必须这样配置。

## 🎮 Tested Aurora Compatibility / 已验证的 Aurora 兼容性

### Compatibility Overview / 兼容性总览

| Game / 游戏 | Recommended Proxy / 推荐 Proxy | RTX 40 MFG | DLSS Neural Rendering | Run inside the upscaler | Notes / 备注 |
|---|---|---|---|---|---|
| **Neverness to Everness / 异环** | `winmm.dll` | ✅ **6X Verified / 已验证 6X** | ✅ Works / 可用 | ⚠️ **Not recommended / 不推荐** | `dxgi.dll` may trigger illegal-module detection; Aurora fixes the RTX 40 MFG instant crash. / `dxgi.dll` 可能触发非法模块检测；Aurora 已修复 RTX 40 MFG 瞬间闪退。 |
| **Onimusha: Way of the Sword / 鬼武者：剑之道** | `dxgi.dll` | ✅ **6X Verified / 已验证 6X** | ✅ Works / 可用 | ❌ **Disable / 建议关闭** | May cause severe visual corruption when enabled; Aurora includes additional compatibility changes. / 开启后可能严重花屏；Aurora 已加入额外兼容性修改。 |
| **The Witcher 3: Wild Hunt / 巫师3：狂猎** | `dxgi.dll` | ✅ **6X Verified via OptiFG / 已验证 6X** | ✅ Works / 可用 | — Not used / 未使用 | Keep the game's native Streamline 1.5.6. For 3X–6X MFG, use `OptiFG (Upscaler) → DLSSG → None (Real DLSSG)`. / 保留游戏原生 Streamline 1.5.6；多帧生成使用 OptiFG → DLSSG。 |
| **The Blood of Dawnwalker / 黎明行者之血** | — | ✅ **6X Verified / 已验证 6X** | ✅ Works / 可用 | — Not tested / 未测试 | **DLSS 5 + 6X MFG verified together. / 已验证 DLSS 5 与 6X 多帧生成可同时正常使用。** |

> [!TIP]
> **This table only lists configurations that have been tested or explicitly documented for Aurora.**  
> **本表只记录已经实测或在 Aurora 中明确确认的配置，不代表其他游戏一定无法使用。**

### Neverness to Everness / 异环

- Fixed the instant crash when enabling `Unlock MFG on RTX 40`
- RTX 4080 Laptop verified with **6X MFG**
- Recommended proxy: `winmm.dll`
- `dxgi.dll` may trigger illegal-module detection
- DLSS Neural Rendering works
- `Run inside the upscaler` is currently not recommended for this title

**已修复游戏内启用 `Unlock MFG on RTX 40` 时的瞬间闪退。**

RTX 4080 Laptop 已验证：

**6X Multi Frame Generation / 6X 多帧生成**

推荐 Proxy：

`winmm.dll`

---

### Onimusha: Way of the Sword / 鬼武者：剑之道

- RTX 40-series **6X MFG verified**
- DLSS Neural Rendering works
- Aurora includes additional compatibility changes for this title
- `Run inside the upscaler / DualFeature` may cause severe visual corruption and should remain disabled

RTX 40 系已验证：

**6X Multi Frame Generation / 6X 多帧生成**

DLSS Neural Rendering 可正常运行。

Aurora 同时包含针对该游戏的额外兼容性修改。

---

### The Witcher 3: Wild Hunt / 巫师3：狂猎

Aurora has been verified with the DX12 version of The Witcher 3.

**Important:** The Witcher 3 uses the older native **Streamline 1.5.6** runtime.  
Aurora Runtime Sync v1.3 automatically detects and preserves these SL1 files instead of replacing them with Streamline 2.x.

**重要：**《巫师3》使用游戏原生 **Streamline 1.5.6**。  
Aurora Runtime Sync v1.3 会自动识别并保护这些 SL1 文件，不再使用 Streamline 2.x 强制覆盖。

Verified configuration / 已验证配置：

- Proxy: `dxgi.dll`
- DLSS 310.9: ✅
- DLSS Neural Rendering: ✅
- RTX 40 Multi Frame Generation: ✅ **2X–6X**
- Game-native Streamline 1.5.6 protection: ✅
- Recommended MFG path: `OptiFG (Upscaler) → DLSSG`
- FG Nvngx Replacement: `None (Real DLSSG)`

#### RTX 40 3X–6X MFG setup / RTX 40 多帧生成设置

1. In the game settings, select **DLSS** as the upscaler.
2. Disable the game's native DLSS Frame Generation.
3. Open the Aurora overlay with `Insert`.
4. Set:
   - **FG Input** → `OptiFG (Upscaler)`
   - **FG Output** → `DLSSG`
   - **FG Nvngx Replacement** → `None (Real DLSSG)`
5. Click **Save Settings**.
6. Completely exit and restart the game.
7. Load into an actual game scene.
8. Open the Aurora overlay again.
9. Enable **Active** under `Frame Generation (DLSSG)`.
10. Select the desired MFG ratio: **2X / 3X / 4X / 5X / 6X**.

游戏内操作：

1. 游戏超分辨率选择 **DLSS**。
2. 关闭游戏原生 DLSS 帧生成。
3. 按 `Insert` 打开 Aurora。
4. 设置：
   - **FG Input** → `OptiFG (Upscaler)`
   - **FG Output** → `DLSSG`
   - **FG Nvngx Replacement** → `None (Real DLSSG)`
5. 点击底部 **Save Settings**。
6. **完全退出并重新启动游戏。**
7. 读取存档进入实际游戏场景。
8. 再次打开 Aurora。
9. 在 `Frame Generation (DLSSG)` 中勾选 **Active**。
10. 选择需要的倍率：**2X / 3X / 4X / 5X / 6X**。

> [!IMPORTANT]
> After changing `FG Input` or `FG Output`, you must **Save Settings and restart the game** before the DLSSG controls become available.
>
> 修改 `FG Input / FG Output` 后，必须先 **Save Settings 并重启游戏**，之后才会出现完整的 DLSSG 帧生成控制项。

![The Witcher 3 Aurora 6X MFG setup](images/witcher3_mfg_6x_setup.png)

---

### The Blood of Dawnwalker / 黎明行者之血

Aurora has been verified with **DLSS 5 and RTX 40 Multi Frame Generation enabled together**.

Verified result:

- DLSS 5 works correctly
- RTX 40-series **6X MFG works correctly**
- **DLSS 5 + 6X MFG can be used simultaneously**

Aurora 已完成《黎明行者之血》实机验证：

- **DLSS 5 正常运行**
- RTX 40 系 **6X 多帧生成正常运行**
- **DLSS 5 + 6X 多帧生成可以同时正常使用**

> [!NOTE]
> The game's native Frame Generation options do not define Aurora's final MFG limit. If a system only exposes 2X in Aurora, check the Aurora configuration, saved settings, loaded DLSSG runtime, and restart state before treating it as a game limitation.
>
> 游戏原生帧生成选项并不代表 Aurora 的最终 MFG 上限。如果 Aurora 本身只能显示 2X，应优先检查 Aurora 设置、配置是否保存、实际加载的 DLSSG Runtime，以及是否完整重启游戏，而不是直接认为该游戏只支持 2X。


## 🛠️ Troubleshooting / 常见问题与排错

### 1. The game does not launch after installing Aurora / 安装 Aurora 后游戏进不去

The selected proxy DLL may not be compatible with this game.

For most games, start with:

`dxgi.dll`

If the game crashes, reports an illegal module, or does not start, try another proxy DLL such as:

- `winmm.dll`
- `version.dll`
- `dbghelp.dll`
- `d3d12.dll`
- `wininet.dll`
- `winhttp.dll`

Only use one OptiScaler proxy DLL at a time.

**如果安装后游戏无法启动，最常见的原因之一就是当前 Proxy DLL 不兼容。**

大部分游戏优先尝试：

`dxgi.dll`

如果出现闪退、非法模块、启动失败等问题，可以依次尝试：

`winmm.dll` → `version.dll` → 其他 Proxy

例如：

**Neverness to Everness / 异环目前推荐使用 `winmm.dll`。**

---

### 2. The launcher restored old DLSS / Streamline files / 启动器把新版 DLSS / Streamline 又恢复成旧版了

Some game launchers, game updates, or file-verification systems may restore the game's original runtime files.

If this happens, wait for the launcher to finish updating, then run:

`Check_DLSS_Runtime.bat`

This is a read-only check. To repair, run Aurora_Setup.bat and select runtime repair; changed managed files require resolving the reported conflict first.

**部分游戏启动器、游戏更新或文件验证，会把 Aurora 已替换的运行库重新恢复成游戏原版。**

遇到这种情况：

**先等启动器更新完成，再运行：**

`Check_DLSS_Runtime.bat`

工具只读检查。如需修复，请在 Aurora_Setup.bat 中选择运行库修复；受管理文件已变化时，先处理报告中的冲突，不会自动覆盖。

Runtime Sync also keeps restore information and verified backups for managed original game files.

Runtime Sync 同时会保存恢复信息以及经过校验的游戏原文件备份。

---

### 3. `Insert` does not open the OptiScaler overlay / 按 `Insert` 无法打开 OptiScaler 面板

Normally, press:

`Insert`

to open the OptiScaler overlay.

If your keyboard does not have an Insert key, you can open the Windows On-Screen Keyboard:

`Ctrl + Win + O`

and click:

`Insert`

Some keyboard layouts may also work with:

`Alt + Insert`

**正常情况下按 `Insert` 即可打开 OptiScaler 参数面板。**

如果键盘没有 Insert 键，可以按：

`Ctrl + Win + O`

打开 Windows 屏幕键盘，然后点击：

`Insert`

部分键盘布局也可以尝试：

`Alt + Insert`

---

### 4. `Run inside the upscaler` causes visual corruption / 开启后花屏或画面异常

`Run inside the upscaler / DualFeature` is experimental and is not compatible with every game.

If you see:

- severe visual corruption
- strange colors
- broken rendering
- evaluation failures
- unstable image output

disable:

`Run inside the upscaler`

and restart the game if required.

**`Run inside the upscaler / DualFeature` 属于实验性功能，并不是所有游戏都兼容。**

如果开启后出现：

- 花屏
- 颜色异常
- 画面破碎
- 模型执行失败
- 图像输出异常

直接关闭：

`Run inside the upscaler`

必要时重新启动游戏。

Aurora can still use DLSS Neural Rendering without this option in compatible titles.

在兼容游戏中，即使关闭该选项，Aurora 仍可以正常使用 DLSS Neural Rendering。

---

### 5. The launcher cannot start the game, but the game executable works / 启动器进不去，但直接运行主程序可以

Some games behave differently depending on whether they are launched from the launcher or directly from the real game executable.

If one method fails, try the other:

- Launcher → Game
- Game `.exe` directly

**部分游戏通过启动器和直接运行主程序时，加载环境并不完全相同。**

如果其中一种方式无法进入游戏，可以尝试另一种。

不过如果游戏依赖启动器进行登录、验证或更新，请先确保启动器已经完成必要流程。

---

### 6. Capcom games and REFramework / 卡普空游戏与 REFramework

Some Capcom games may require **REFramework** for the intended modding setup or compatibility workflow.

Aurora does not currently bundle REFramework.

If a supported Capcom title requires it, install a compatible REFramework version separately before using Aurora.

**部分卡普空游戏在 Mod / 兼容性环境下可能需要先安装 REFramework。**

Aurora 当前不会集成 REFramework。

如果对应游戏需要，请先单独安装兼容版本的 REFramework，再使用 Aurora。

---

### 7. Aurora stopped working after a game update or Steam verification / 游戏更新或 Steam 验证后 Aurora 失效

Game updates and Steam file verification may restore original game runtime files.

First run:

`Check_DLSS_Runtime.bat`

for a read-only diagnosis, then choose runtime repair in Aurora_Setup.bat if needed.

If the game executable or loading behavior has changed after a major update, you may also need to run:

`setup_windows.bat`

again and reselect the appropriate proxy DLL.

**游戏更新或 Steam 验证完整性后，部分 DLL 可能会被恢复成游戏原版。**

优先运行：

`Check_DLSS_Runtime.bat`

只读检查运行库；需要修复时，再运行 Aurora_Setup.bat 选择运行库修复。

如果游戏大版本更新后主程序、加载方式或目录结构发生变化，再重新运行：

`setup_windows.bat`

并重新选择合适的 Proxy DLL。

---

> [!TIP]
> If Aurora worked before an update but suddenly stopped working afterwards, first suspect restored game runtime files before changing multiple settings at once.  
> 如果 Aurora 原本可以正常使用，但游戏更新后突然失效，优先检查运行库是否被游戏或启动器恢复，不建议一上来同时修改大量设置。

## Important Notes / 重要说明

> [!IMPORTANT]
> **Aurora is a community fork and is not an official OptiScaler, NVIDIA, Capcom or Hotta Studio release.**  
> **Aurora 是社区分支，并非 OptiScaler、NVIDIA、Capcom 或 Hotta Studio 官方版本。**

> [!CAUTION]
> **Do not use Aurora in online or anti-cheat protected environments unless you fully understand the risk.**  
> **除非你完全了解潜在风险，否则不建议在联网或受反作弊保护的环境中使用 Aurora。**

Multi Frame Generation and DLSS Neural Rendering compatibility still depend on the game, GPU, NVIDIA runtime and game-specific implementation.

多帧生成与 DLSS 神经渲染的实际兼容性仍取决于游戏、显卡、NVIDIA 运行库以及具体游戏实现。

---

## Upstream & Credits / 上游项目与致谢

Aurora is built on the work of the OptiScaler community and related forks.

Aurora 基于 OptiScaler 社区以及相关分支的工作成果。

The original projects, authors, contributors, licenses, documentation and credits remain fully respected.

原项目、作者、贡献者、许可证、文档与致谢信息均予以完整保留和尊重。

The original upstream README is preserved below for reference and compatibility documentation.

下方继续保留原上游 README，作为功能、兼容性与文档参考。

---

<div align="center">

  ![Logo](https://github.com/user-attachments/assets/c7dad5da-0b29-4710-8a57-b58e4e407abd)

</div>
<hr />
<br />
<div align="center">
  <a href="https://github.com/sponsors/cdozdil?frequency=one-time"><img src="images/gh-sponsor-red.png" /></a>
  <a href="https://buymeacoffee.com/nitec"><img src="images/bmac.png" /></a>
</div>
<br />

## Table of Contents

**1.** [**About**](#about)  
**2.** [**How it works?**](#how-it-works)  
**3.** [**Supported APIs and Upscalers**](#which-apis-and-upscalers-are-supported)  
**4.** [**Installation**](#installation)  
**5.** [**Known Issues**](#known-issues)  
**6.** [**Compilation and Credits**](#compilation)  
**7.** [**Wiki**](https://github.com/optiscaler/OptiScaler/wiki)

<br />
<div align="center">
  <a href="https://discord.gg/wEyd9w4hG5"><img src="https://img.shields.io/badge/OptiScaler-blue?style=for-the-badge&logo=discord&logoColor=white&logoSize=auto&color=5865F2" alt="Discord invite"></a>
  <a href="https://github.com/optiscaler/OptiScaler/releases/latest"><img src="https://img.shields.io/badge/Download-Stable-green?style=for-the-badge&logo=github&logoSize=auto" alt="Stable release"></a>
  <a href="https://github.com/optiscaler/OptiScaler/releases/tag/nightly"><img src="https://img.shields.io/badge/Download-Nightly-purple?style=for-the-badge&logo=github&logoSize=auto" alt="Nightly release"></a>
  <a href="https://github.com/optiscaler/OptiScaler/wiki"><img src="https://img.shields.io/badge/Documentation-blue?style=for-the-badge&logo=gitbook&logoColor=white&logoSize=auto" alt="Wiki"></a>
</div>
<div align="center">
  <a href="https://github.com/optiscaler/OptiScaler/releases"><img src="https://img.shields.io/github/downloads/optiscaler/optiscaler/total?style=for-the-badge&logo=gitextensions&logoSize=auto&label=Total" alt="Total DL"></a>
  <a href="https://github.com/optiscaler/OptiScaler/releases/latest"><img src="https://img.shields.io/github/downloads/optiscaler/optiscaler/latest/total?style=for-the-badge&logo=gitextensions&logoSize=auto&label=Stable&color=green&logoColor=white" alt="Stable DL"></a>
  <a href="https://github.com/optiscaler/OptiScaler/releases/tag/nightly"><img src="https://img.shields.io/github/downloads/optiscaler/OptiScaler/nightly/total?style=for-the-badge&logo=gitextensions&logoColor=white&logoSize=auto&label=Nightly&color=purple" alt="Nightly DL"></a>
  <a href="https://github.com/optiscaler/OptiScaler/stargazers"><img src="https://img.shields.io/github/stars/optiscaler/optiscaler?style=for-the-badge&logo=githubsponsors&logoColor=white&label=S.T.A.R.S." alt="Stars"></a>
</div>


## About

**OptiScaler** is a tool that lets you replace upscalers in games that ***already support DLSS2+ / FSR2+ / XeSS*** ($`^1`$), as well as manage ***frame generation*** in already mentioned games _(either by replacing existing FG options or enabling it in DX12 games through experimental ***OptiFG***)_. It also offers extensive customization options for all users, including those with Nvidia GPUs using DLSS.

> [!CAUTION]
> * We've been informed about some **FAKE websites** presenting themselves as OptiScaler team, so we would like to strongly highlight that we **DO NOT HAVE an official website!**  
> * We **DON'T have an official manager app**, so please be careful when downloading or using them! And please don't bother us to provide support for something which isn't even ours!
> * Only **LEGIT places** are this Github, our Discord server and Nitec's NexusMods page.  
> * OptiScaler is **FREE**, any kind of monetary requirements are scams!  

> [!TIP]
> _For example, if a game has DLSS only, OptiScaler can be used to replace DLSS with XeSS or FSR 3.1 (also works for FSR2-only games, like The Outer Worlds Spacer's Choice, albeit requires manually providing nvngx_dlss.dll)._

**Key aspects of OptiScaler:**
- Enables usage of XeSS, FSR2, FSR3, **FSR4**$`^2`$ (_officially, RDNA4 and RDNA3 dGPUs only_) and DLSS in (temporal) upscaler-enabled games
- Allows users to fine-tune their upscaling experience with a wide range of tweaks and enhancements (RCAS & MAS, Output Scaling, DLSS Presets, Ratio & DRS Overrides etc.)
- Since v0.7.0+, added ***experimental DX12*** frame generation support with possible HUDfix solution ([**OptiFG**](#optifg--hudfix-experimental-hud-ghosting-fix))
- Supports [**Fakenvapi**](#installation) integration - enables Reflex hooking and injecting _Anti-Lag 2_ (RDNA1+ only), _LatencyFlex_ (LFX) or _XeLL_ - _bundled since 0.9_  
- Since v0.7.7, added support for **Nukem's** FSR3-FG mod [**dlssg-to-fsr3**](#installation), only supports games with ***native DLSS-FG*** - _bundled since 0.9_
- Since v0.7.8, added **ASI plugin loading** support (_disabled_ by default (`LoadAsiPlugins=` in INI), loads from customisable folder, default `plugins`)
- New project - [**OptiPatcher**](https://github.com/optiscaler/OptiPatcher) - an ASI Plugin for OptiScaler for enabling DLSS and DLSSG inputs without spoofing in ***supported games***.
- Since v0.7.8, OptiScaler is now automatically applying certain game patches for a better out-of-the-box experience
- Since v0.9.0, separated FG Inputs and Outputs, added XeFG and FSR4-FG support, as well as bundled Fakenvapi and Nukem's FSR3-FG mod
- For a detailed list of all features, check [Features](Features.md)


> [!IMPORTANT]
> _**Always check the [Wiki Compatibility list](https://github.com/optiscaler/OptiScaler/wiki) for known game issues and workarounds.**_  
> Also please check the  [***OptiScaler known issues***](#known-issues) at the end regarding **RTSS** compatibility.  
> A separate [***FSR4 Compatibility list***](https://github.com/optiscaler/OptiScaler/wiki/FSR4-Compatibility-List) is available for community-sourced tested games.  
> ***[3]** For **not bundled** items, please check [Installation](#installation).*  

> [!NOTE]
> ### Upscaler notes
> <details>
>  <summary><b>Click for [1], [2] </b></summary>  
>  
> **[1]** For **Unreal Engine** games, only UE XeSS -> Opti XeSS/FSR4 work  
>  
> *Regarding **XeSS** inputs, since **Unreal Engine plugin** does not provide depth, replacing in-game XeSS breaks other upscalers (e.g. Redout 2 as a XeSS-only game), but you can still apply RCAS sharpening to XeSS to reduce blurry visuals.* 
>
> *Regarding **FSR inputs**, FSR 3.1 is the first version with a fully standardised, forward-looking API and should be fully supported. Since FSR2 and FSR3 support custom interfaces, game support will depend on the developers' implementation. With Unreal Engine games, you might need [ini tweaks](https://github.com/optiscaler/OptiScaler/wiki/Unreal-Engine-Tweaks) for FSR inputs.*  
>
> **[2]** *Regarding **FSR4**, please check [FSR4 Compatibility list](https://github.com/optiscaler/OptiScaler/wiki/FSR4-Compatibility-List) for known supported games and general info.*
> 
> </details>


## Official Discord Server: [OptiScaler](https://discord.gg/wEyd9w4hG5)

*This project is based on [PotatoOfDoom](https://github.com/PotatoOfDoom)'s excellent [CyberFSR2](https://github.com/PotatoOfDoom/CyberFSR2).*

## How it works?
* OptiScaler acts as a middleware, it intercepts upscaler calls from the game (_**Inputs**_) and redirects them to the chosen upscaling backend (_**Output**_), allowing user to replace one technology with another one. **Inputs -> OptiScaler -> Outputs**  
* _Or put more bluntly, **Input** is the upscaler used in game settings, and **Output** the one selected in Opti Overlay._
* _Same goes for FG options which are separated into **FG Input** and **FG Output**._

> [!NOTE]
> * Pressing **`Insert`** should open the Optiscaler **Overlay** in-game with all of the options (_`ShortcutKey=` can be changed in the INI file, or under **Keybinds** in the overlay_). 
> * Pressing **`Page Up`** shows the performance stats overlay in the top left, and can be cycled between different modes with **`Page Down`** (_keybinds customisable in the overlay_).  
> * If Opti overlay is instantly disappearing after trying Insert a few times, maybe try **`Alt + Insert`** ([reported workaround](https://github.com/optiscaler/OptiScaler/issues/484) for alternate keyboard layouts).

![inputs_and_outputs](https://github.com/user-attachments/assets/7ff37fd7-515f-488d-99ff-faa586e206fc)

## Which APIs and Upscalers are Supported?
Currently **OptiScaler** can be used with DirectX 11, DirectX 12 and Vulkan, but each API has different sets of supported upscalers.  
[**OptiFG**](#optifg--hudfix-experimental-hud-ghosting-fix) currently **only supports DX12** and is explained in a separate paragraph.

#### For DirectX 12
- XeSS (Default)
- FSR 2.1.2, 2.2.1
- FSR 3.X (and FSR 2.3.X)
- FSR 4.X (via FSR 3.X/4, _officially RDNA4 and RDNA3 dGPUs only_)
- DLSS

#### For DirectX 11
- FSR 2.2.1 (Default, native DX11)
- FSR 3.1.2 (unofficial port to native DX11)
- DLSS (native DX11)
- XeSS 2.X (native DX11, _Intel ARC only_)
- XeSS, FSR 2.1.2, 2.2.1, FSR 3.X w/Dx12 (_via D3D11on12_)$`^1`$
- FSR 4.X (via FSR 3.X/4 w/Dx12 interop, _officially RDNA4 and RDNA3 dGPUs only_)

> [!NOTE]
> <details>
>  <summary><b>Expand for [1]</b></summary>
>
> _**[1]** These implementations use a background DirectX12 device to be able to use DX12-only upscalers. There's a performance penalty up to 10-ish % for this method, but allows many more upscaler options. Also native DX11 implementation of FSR 2.2.1 is a backport from Unity renderer and has its own problems of which some were fixed by OptiScaler._
> </details>

#### For Vulkan
- FSR 4.X (via FSR 3.X/4 w/Dx12 interop, _officially RDNA4 and RDNA3 dGPUs only_)
- FSR2 2.1.2 (Default), 2.2.1
- FSR3 3.1 (and FSR2 2.3.2)
- DLSS
- XeSS 2.x

#### OptiFG + HUDfix (experimental HUD ghosting fix) 
**OptiFG** was added with **v0.7** and is **only supported in DX12**. 
It's an **experimental** way of adding FG to games without native Frame Generation, or can also be used as a last case scenario if the native FG is not working properly.  
* Currently supports FSR3-FG (requires HUDfix to avoid HUD ghosting), XeFG and FSR4-FG (ML model deals with the HUD, so may or may not require HUDfix).

For more information on OptiFG and how to use it, please check the Wiki page - [OptiFG](https://github.com/optiscaler/OptiScaler/wiki/OptiFG).


## Installation
> [!CAUTION]
> _**Warning**: **Do not use this mod with online games.** It may trigger anti-cheat software and cause bans!_

> [!IMPORTANT]
> **For installation steps, please check the [**Wiki**](https://github.com/optiscaler/OptiScaler/wiki)**  

## Configuration
Please check [this](Config.md) document for configuration parameters and explanations. If your GPU is not an Nvidia one, check [GPU spoofing options](Spoofing.md) *(Will be updated)*

## Known Issues

> [!NOTE]
> **For a list of known issues, please check the [**Wiki**](https://github.com/optiscaler/OptiScaler/wiki)**.
> 
> Also worth checking the [Compatibility List](https://github.com/optiscaler/OptiScaler/wiki/Compatibility-List) for possible game issues and their fixes.

## Compilation

### Requirements
* Visual Studio 2022

### Instructions
* Clone this repo with **all of its submodules**.
* Open the OptiScaler.sln with Visual Studio 2022.
* Build the project

## Thanks
* @PotatoOfDoom for CyberFSR2
* @Artur for DLSS Enabler and helping me implement NVNGX api correctly
* @LukeFZ & @Nukem for their great mods and sharing their knowledge 
* @FakeMichau for continous support, testing and feature creep
* @QM for continous testing efforts and helping me to reach games
* @TheRazerMD for continous testing and support
* @Cryio, @krispy, @krisshietala, @Lordubuntu, @scz, @Veeqo for their hard work on (now outdated) [compatibility matrix](https://docs.google.com/spreadsheets/d/1qsvM0uRW-RgAYsOVprDWK2sjCqHnd_1teYAx00_TwUY)
* And the whole DLSS2FSR community for all their support

## Credit
This project uses [FreeType](https://gitlab.freedesktop.org/freetype/freetype) licensed under the [FTL](https://gitlab.freedesktop.org/freetype/freetype/-/blob/master/docs/FTL.TXT)

## Sponsors
<table>
 <tbody>
  <tr>
   <td align="center"><img alt="[SignPath]" src="https://avatars.githubusercontent.com/u/34448643" height="30"/></td>
   <td>Free code signing on Windows provided by <a href="https://signpath.io/">SignPath.io</a>, certificate by <a href="https://signpath.org/">SignPath Foundation</a></td>
  </tr>
 </tbody>
</table>

