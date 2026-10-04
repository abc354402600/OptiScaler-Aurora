# Aurora v1.1 增量兼容性审计 — 2026-10-04

## 范围与结论

本次响应用户“先检查官方、其他分支和 fork”的请求。以 Aurora `8a3044d3` 为源码基线；正式 v1.1 标签仍为 `671ccded`。本次只更新审计资料，没有移植代码、替换发行 DLL 或重跑历史测试。

发现值得继续的小范围兼容性修复，但不能据此声称所有 fork 已审完、所有游戏已兼容，或已有公开补丁证明巫师3高倍 MFG 闪退、绝区零 11008 全部解决。v1.1 的既有发布边界保持不变。新增功能不是本轮优先事项。

## 可复查的截止点

| 来源 | 本次截止点 | 相对上次的变化 |
| --- | --- | --- |
| 官方 master | `d63306eae2d3c6aa449d87a9cbaa26d5c83517f6` | 自 `20d9d147a4334a49a99d67d235ad7915e0d6d846` 起 41 个提交、78 个变更文件；包含合并与重投影历史，不是 41 项独立修复 |
| 官方 release/0.9 | `f1dc37829a68e5db0d0c93935b1e5f63ddca7fcc` | 自 `121a87a9f2a0f63a497fd9e0dc19bfb998c7f46e` 起 4 个提交 |
| 官方 reprojection | `44cfee4d436857742a9bf71bbe81396ec9989715` | 已纳入 master 的新功能链 |
| 官方 unify-upscaler-inputs | `97a18c36331418f74dc4b60dde178ade32e2820a` | 所查分支头未变化 |
| grim-susemi/OptiScaler-Susemi | `3def828dadbd79f887996a6733ae261abe0e669f` | 自 `8f387acad612e7ce8ea0b4811823d08f31e204db` 起 13 个提交 |
| AizawaHikaru233/genshin_fsr_brigde | `02f54639b73378e4266079dac9b2ae581c917c3d` | 自 `b31bf20b31724f149a4bef47b867be296491dead` 起 49 个提交 |
| dashdogy/RTX40MFG-Unlock | `706cb1b87c31176817184307eba8dcfa3e79d35c` | 10 月 2 日 v1.4.1-hotfix.1 |
| wilsjo2/OptiScaler_DLSSNR | `973761621353b99bee3dc7d4bb27b117fef2644f` | 所查默认分支头未变化 |
| y4my4my4m/OptiScaler_DLSSNR_Multipass_MFG | `7b7220bbb4994a9c8ae60cfc75a44cb67995efb8` | 所查默认分支头未变化 |
| gprocunier/OptiScaler | `7233fc0cc8e96281572fc873fbea01d615508d1d` | 所查默认分支头未变化 |
| deYangar/OptiScaler_chs | `351f38ae09fafe435a56a08067d61ccf085b5643` | 近期可见提交为官方同步、自动翻译；未据此识别独立兼容性修复 |
| wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass | `1bd39091337cc07ba961c8e59ded57e21dc95b18` | 本次新发现的仓库，提交日期早于 9 月 25 日，不算本周新增修复 |
| sdli1995/dlssg_for_sm86 | `9621db573e07ed54f50c15bbb585ed9a7bdfac28` | 9 月 19 日的 RTX 20/30 专用路径，不是 RTX 40 默认更新 |

[官方增量比较](https://github.com/optiscaler/OptiScaler/compare/20d9d147a4334a49a99d67d235ad7915e0d6d846...d63306eae2d3c6aa449d87a9cbaa26d5c83517f6)。该日期是库存审计截止，不表示所有新增实现均已逐行审完。Susemi 比较接口的文件列表达到 300 项上限，故其大规模源树重整不能视为完整差异审计；下述结论来自指定提交及相关生产代码。全站 fork 列表请求未取得有效结构化结果，本次为具名仓库、官方分支及活跃 PR 的定向检查。

## 优先候选

### 1. 合法零尺寸交换链被错误排除：最适合先修

[官方 PR #1183](https://github.com/optiscaler/OptiScaler/pull/1183)，头提交 `8abf6d7f16dc49d6ebc5edf917b8dbc774eaaf0b`，本次检查仍为开放 PR。作者报告 Soulframe DX12 的菜单/OptiFG 不可用，并推测另一问题可能同源；后者不是已证实关联。

当前 Aurora 将宽或高小于 100 的交换链当作覆盖层跳过，其中包含合法的 0。微软明确允许 CreateSwapChainForHwnd 的宽、高或两者为零，由窗口尺寸推导实际值：[API 文档](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforhwnd)。这是可从代码与 API 契约确认的误判，不等于已在 Aurora 中复现上述游戏问题。

官方 PR 改四处；Aurora 的 `DxgiFactory_Hooks.cpp` 和 `DxgiFactory_WrappedCalls.cpp` 合计有九处相似条件。不能只搬四处，也不能机械修改全部九处：六处传统/HWND 路径与三处 CoreWindow 路径应分别核对 API 契约。下一批应覆盖实际源函数、零值单轴/双轴、非零小窗口与包装调用路径。

### 2. Control Resonant 的限定兼容策略

- [`1117abdb`](https://github.com/optiscaler/OptiScaler/commit/1117abdb7fabb62828010d3a6e5ebb8bec7f90be)：对 `controlresonant.exe` 增加 `DoNotPreserveFGSwapChain`。Aurora 当前该游戏仅有关闭 DXGI 伪装策略。官方 release/0.9 也有对应修复，适合小范围采用。
- [`0696cf97`](https://github.com/optiscaler/OptiScaler/commit/0696cf971a3761dc3f22f2ddb0fc61acff7fd96a)：增加 DisableOTA 设置，默认关闭，仅对该游戏默认开启，并保留显式用户选择。作用是清除 Streamline 的自动下载/加载下载插件许可。可减少插件版本漂移，但需核对 Aurora 私有 Streamline 与原生 SL1 路径，不应全游戏强制关闭或顺便改运行库版本。

### 3. Streamline 插件加载竞态：有价值，但需单独适配

[`f6db41df`](https://github.com/optiscaler/OptiScaler/commit/f6db41dfa7bacb16ac50bd1e5787fdb44362da47) 为多个插件加载/挂钩路径增加互斥锁。锁覆盖 DLL 加载和 hook，DLSSG 还涉及两把锁。Aurora 已有不同的发布与生命周期防护，需要检查加载重入和锁顺序，不能把“加锁”直接视为完整并发修复，也尚未证明该提交自身存在死锁。

### 4. XeFG 的非所属交换链 Present

[Susemi `cb14a206`](https://github.com/grim-susemi/OptiScaler-Susemi/commit/cb14a2060496c55a6d0f4cfd4b7aa0b095078d10) 在非所属交换链 Present 时先原样转发，避免污染帧计数、回调和 FG 状态。Aurora 当前 FGPresent 入口只先检查关闭状态，随后即进行帧计数，因此值得检查同类边界。

不能直接照搬 `This != currentFGSwapchain`：包装层可能存在同一 COM 对象的别名，错误判定会让正常 FG 被跳过；交换链注册与生命周期也需要一致。捐赠方自身记录了这些边界。下一批若实施，应先确定对象身份与明确转发路径，再做真实函数的聚焦检查。

### 5. Titan Quest 2 覆盖层冲突

[官方 `5dc144e2`](https://github.com/optiscaler/OptiScaler/commit/5dc144e29a1ba6fd63549dcabf20bce814d01e6a) 临时阻止加载 `overlayenginex64.dll` / `overlayreleasex64.dll`，针对 THQNOnline 覆盖层与 FG 冲突，亦进入 release/0.9。原补丁使用全局名单；Aurora 若采用，应优先限定已知游戏，评估被关闭的覆盖层功能，避免全局复制。

## 相关项目与暂缓内容

- **巫师3新热修**：[RTX40MFG v1.4.1-hotfix.1](https://github.com/dashdogy/RTX40MFG-Unlock/releases/tag/v1.4.1-hotfix.1) 主要涉及 HairWorks/路径追踪毛发、ReShade/RenoDX 设备别名与加载/跨区域后的毛发缺失。其新毛发子系统包含几何缓冲池和 GPU 退役问题，Aurora 并无同一实现。可借鉴 COM 身份确认和资源退役思路，不能宣称这是此前动态 MFG、6X 切换崩溃的同因修复。发布说明本身仍列出真实游戏验证边界，不宜整体移植。
- **原神桥接**：[`68ed170c`](https://github.com/AizawaHikaru233/genshin_fsr_brigde/commit/68ed170ce06c8e401920173e77a22a016b4e9b5b) 把接管活动窗口从 3000 ms 缩短到 200 ms、处理来源归属/多实例和场景切换，并增加诊断；另有每实例 GPU 互操作更新。它属于桥接项目而非 Aurora 内核，可列为后续配套兼容评估。作者的场景测试结论未在本机复现，不能迁移为绝区零/崩铁已修复结论。官方 #1122 本次读取无新增评论证据。
- **新的 NR 仓库**：[`e237f895`](https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/commit/e237f895623742b761f9e5f00067cb3dc62619f4) 涉及最终画面 NR、HDR、Pre-SR 传递和 GPU 计时，27 文件、2606 行新增；属于功能及架构扩展，不是有测量依据的通用 FPS 优化，暂缓。
- **官方重投影 / DLSS DX11-on-12、Vk-on-DX12**：新增后端和功能链，暂缓，不作为 v1.1 小补丁。
- **官方 DLSSG lobotomy**：`80f4c61b` / `fb41e3e6` 对部分 Streamline 功能调用直接返回成功，涉及输入接管和生命周期契约；不能直接复制到 Aurora 原生 SL1/已验证 6X 路线。
- **性能结论**：本次没有进行性能基准，未找到足以声称“全游戏普遍增帧”的证据。竞态修复、误判修复和功能增加均不能换算为 FPS 增幅。

## 后续批次边界

建议先将零尺寸交换链和 Control Resonant 限定策略组成小批，源码适配、聚焦回归和完整 Windows DLL 构建完成后再决定正式小版本。Streamline 加载与 XeFG 身份处理作为后续独立评审项，不重新开启无限范围的全局重构。保留 v1.1 发行说明中的未闭环边界、SL1 保护、DualFeature=false 及已有 6X 行为。

本次验证仅为远端提交/分支库存、指定差异和本地对应源代码核对；没有新游戏/GPU 验证、没有性能测量、没有编译测试，也没有更改正式资产。
