# 兼容性调查记录 · 2026-09-13

核对仓库：`abc354402600/OptiScaler-Aurora`，分支 `aurora`，提交 `e1673a16673070401612db04cc0593ca4dc3a6f6`。没有改动本次涉及的 C++ 渲染或帧生成文件。

## 米哈游游戏

| 游戏 | 已找到的现有工作 | Aurora 实际状态与处理 |
| --- | --- | --- |
| 绝区零 | 官方有专用 quirk 和 DX12/Proxy 配置 | `Quirks.h` 已有 `zenlesszonezero.exe → IgnoreTagsWithoutHudlessForFG`，`Streamline_Hooks.cpp` 已实现资源标签筛选。新版安装器复用官方 d3d12.dll / -use-d3d12 指引，仍手动选择 Proxy，不重复移植旧 quirk |
| 原神 | 独立 Genshin FSR Bridge 对接原生 FSR2，并可连接 OptiScaler；上游有 overlay 输入阻塞和 FG 回归报告 | Aurora 已有低级鼠标/键盘钩子转发及按原始 Target 查找 DirectInput detour 的修复。桥接项目需要独立部署和实测，未把其专用 DX11→DX12 输入桥接代码强行加入全局逻辑 |
| 星穹铁道 | 官方仓库 #994 报告 DLSS 切换时短暂停顿及普通安装被游戏移除的现象 | 该报告未提供已合并的完整解决补丁；本次未发现足以直接加入默认配置的成熟修复。扫描支持 StarRail_Data/Plugins 等位置，但发现 DLL 不等于已解决加载兼容性 |

依据：[绝区零官方说明](https://github.com/optiscaler/OptiScaler/wiki/Zenless-Zone-Zero)、[最初的 ZZZ quirk 提交](https://github.com/optiscaler/OptiScaler/commit/274ba5499a7c9e3208b00ee2407aff608ba14d98)、[Genshin FSR Bridge](https://github.com/AizawaHikaru233/genshin_fsr_brigde/blob/main/README.md)、[原神输入问题 #1124](https://github.com/optiscaler/OptiScaler/issues/1124)、[星铁问题 #994](https://github.com/optiscaler/OptiScaler/issues/994)。

原神桥接作者提供了相同配置下两个 nightly 的 FG 对比，较新版本出现 `E_ABORT` 和 Streamline 异常。这是明确的待复现线索，不足以证明 Aurora 当前也有同一缺陷，亦不足以确定应回退哪项修复。详见 [#1122](https://github.com/optiscaler/OptiScaler/issues/1122) 及其 [报告](https://github.com/AizawaHikaru233/genshin_fsr_brigde/blob/main/assets/optiscaler-fg-regression/REPORT.md)。没有把第三方项目或 issue 的自述当成 Aurora 实机验证。

已查询上游提交/issue、桥接项目原文以及相关 fork；`abc354402600/OptiScaler-Community-Fixes` 的搜索端点返回 422，不能把不可检索解释为不存在修复。`Dagherbou/OptiScaler_DLSSNR` 的 Genshin 提交检索未返回结果。以上是本次调查范围，不声称穷尽所有 fork。

## 巫师3 / SL1.5.6 闪烁

上游 [7ce71e7](https://github.com/optiscaler/OptiScaler/commit/7ce71e7640788b0a7d1a046627bb649bde1073e3) 将 SL1 输入与 Reflex 帧编号关联，明确针对 Witcher 3 的 **DLSSG → FSRFG** 严重闪烁。Aurora 的 `Streamline_Inputs_Sl1_Dx12.cpp` 已有 `SetFrameCount(frameIndex - 1)`、帧编号索引及 Reflex 输入处理。

后续 [22f7e86](https://github.com/optiscaler/OptiScaler/commit/22f7e8632d6d3f3aeca31c942927a867fdca043f) 限定 SL1 输入检查仅作用于 DLSSG 输入，避免影响 OptiFG。Aurora 的 `IsSL1AndFGActive()` 已限定 `activeFgInput == FGInput::DLSSG`，并有更后的 RenderSubmitStart / PresentStart 处理。因此不能把早期提交直接覆盖当前 hook。

Aurora README 已验证的 6X 路径为 **OptiFG (Upscaler) → DLSSG → None (Real DLSSG)**。它与上述原生 DLSSG 输入修复的适用路径不同。没有足够证据把当前 OptiFG 6X 闪烁归因于缺少该修复。本次不改倍率上限、SL1 ABI、资源生命周期或 DualFeature 默认值。

实机对比请固定驱动、场景、分辨率和设置，每次更改保存并完全重启：FG 关闭 → 2X → 3X → 6X；区分 HUD 闪烁、全屏明暗闪烁、物体/历史帧闪烁，保存对应配置和日志。再按单变量方式核对 HDR、VRR 和叠加层。此处是定位流程，不是声称这些变量就是原因。

## 保留的稳定基线

- `OptiScaler/menu/menu_overlay_dx.cpp`：文件未改。
- `OptiScaler/exports/dxgi.h` 与 `OptiScaler/Source.def`：文件未改；三个扩展导出名称存在。
- `Streamlined_fetcher_windows.bat`：文件未改。
- 中文 UI、MfgUnlock、IFGFeature、DLSSG 与 SL1 输入代码：文件未改。
- `OptiScaler.ini`：文件未改，`DualFeature=false` 保持。

额外发现：仓库 `dist/streamline` 中的组件版本并不全部是 2.14。实际 PE 信息显示 interposer 和 dlss_nr 为 2.13，directsr 为 2.12，其余列出的组件为 2.14。本次只报告每个文件的真实版本，未更换二进制，也不把这直接认定为闪烁原因。源码中的运行库文件不代表已审计最新发行包。
