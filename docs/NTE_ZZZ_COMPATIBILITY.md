# 异环菜单卡顿与绝区零组件异常

更新：2026-09-15。兼容性强化尚未全部完成；已通过构建的修复、社区解决方法和待确认问题分别记录。本文不是所有游戏版本均稳定的承诺。

## 异环：角色、抽卡等菜单卡顿

观众提供的方法是修改 **NVIDIA Profile Inspector** 中的游戏驱动配置，不是替换 DLL，也不是重装 Aurora。

1. 退出异环，从 [Profile Inspector 项目发布页](https://github.com/Orbmu2k/nvidiaProfileInspector/releases) 获取工具。
2. 在顶部游戏配置中找到 `Neverness to Everness`，确认关联的是实际游戏 `HTGame.exe`。不要选全局配置；找不到对应项时不要猜测另一个游戏或导入来历不明的整套配置。
3. 先导出当前游戏配置备份，并记录下面这个设置的原始值。
4. 在 `05 - Upscaling and Frame Generation` 分组找到 `DLSS-FG - Full-Screen Menu Detection`，改成 **`Allow (0x1)`**。也可搜索设置 ID **`0x104596A1`**。
5. 点击 `Apply Changes`，重启游戏。保持其他选项不变，分别观察大世界、角色、抽卡菜单，以及从菜单返回大世界的表现。
6. 没改善或引入新问题时，将该项改回记录的原值并应用、重启。不要直接恢复整个全局驱动配置。

名称、设置 ID 和 `Allow = 0x00000001` 已在 [Profile Inspector 设置定义](https://github.com/Orbmu2k/nvidiaProfileInspector/blob/master/nvidiaProfileInspector/CustomSettingNames.xml) 核实。不要把它与 Force Enable 或其他 DLSS Override 混为一谈。驱动版本与游戏配置会影响实际效果。

**流畅了，不等于菜单恢复了 6X。** NVIDIA 的 [DLSSG 集成说明，第 6.5 节](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md#65-automatically-disabling-dlss-g-in-menus) 明确描述了检测全屏菜单后关闭 DLSSG 的机制。Profile Inspector 的驱动项与应用端 Streamline flag 也不能未经验证就当成完全相同的开关。

因此目前只能将此方法标记为“观众反馈有效的菜单卡顿缓解办法”。判断是否真的插帧，应对比呈现帧率与实际渲染帧率，不能只凭观感。Aurora 本次没有自动写入驱动配置，也没有强制游戏在缺少有效帧资源的菜单里继续插帧。

## 绝区零：11008、闪退和文件消失

本轮截图记录了 `The client component is running abnormally` / `11008`。其中一张同时显示 FG Input/Output 为“无”，DLSSG 未加载。另一条反馈是运行后文件消失，但缺少具体文件名和安全软件记录。用户估计显卡为 RTX 40 系列；Aurora 构建版本尚不清楚。

这些证据不足以断定是 NVIDIA MFG 崩溃、反作弊拦截、杀毒隔离或启动器修复。尤其不能用“文件消失”直接推断程序执行了卸载。

当前 [官方 OptiScaler 绝区零页面](https://github.com/optiscaler/OptiScaler/wiki/Zenless-Zone-Zero)（页面标注测试 OptiScaler 0.9.4，2026-08-06 更新）提供了明确的输入路径限制：

- 需要 DX12；FG 输入列为 **DLSSG via Streamline**。
- **FSR 3.1 FG 输入在打开菜单时异常，并缺少 HUD**，建议使用上述 Streamline 输入。FSR 超分输入、FSR FG 输入、FSR FG 输出是不同设置，不要互相替代概念。
- 页面记录的可用 Proxy 文件名为 `d3d12.dll` / `dbghelp.dll`。这只是该页面测试环境的记录，不构成本轮 `11008` 的已确认解决方案。

排查时需要：Aurora 具体构建号、显卡/驱动、实际 Proxy 名称、DX12 状态、FG Input/Output、错误发生前的 `OptiScaler.log`，以及消失的文件名。若文件消失，先核对 Windows 安全中心保护历史、其他安全软件记录和启动器修复记录；不要为了试错关闭保护或盲目恢复被隔离文件。日志应由当事人检查后提供，避免带出个人路径等无关信息。

[dlssg_for_sm86 issue 50](https://github.com/sdli1995/dlssg_for_sm86/issues/50) 是另一个模块 0.2.3 在 **RTX 3050** 上启用 FG 进入加载页崩溃的报告。本轮约为 RTX 40 的组件异常没有证据属于同一问题，因此未移植或推荐其替换模块。

## 本轮代码与后续顺序

- Aurora 游戏内“游戏兼容性与已应用修正”增加上述两个游戏的针对性说明；绝区零处于 FSR FG 输入时显示对应提醒。只提供说明，不静默切换 FG 或驱动配置。
- 上游从 `4af2417b` 到 `a4890db5` 只新增一条提交：[仙剑奇侠传七初始化崩溃修正](https://github.com/optiscaler/OptiScaler/commit/a4890db5b3c7c6918f4b35d0fd3318b42e2ccc66)。已移植，仅为 `pal7` 的 Win64/WinGDK Shipping 入口启用现有的两项 UE 资源状态屏障特例，不改变其他游戏默认值。
- 优先闭环：异环菜单单变量对比 → 绝区零带版本/日志的复现 → 巫师3高倍率切换与加载 → 原神桥接回归二分。
- 新功能/优化仍有候选，但未宣称已全部移植：活动 Streamline 插件绑定、FG 资源生命周期重构、OptiInput 锁顺序，以及不同 FG 输出路径的耗时。需要独立证据和验证；不以“全量吸收最新代码”代替兼容性工作。

性能候选复核：[上游 issue 1087](https://github.com/optiscaler/OptiScaler/issues/1087) 的 RX 9070 XT 报告比较了 FSR FG 与修改版 Nukem 路径。维护者认为交换链或 AL2 可能相关，但尚未定位；作者在后续评论中明确说，改写后的路径能运行 FF16，却会在绝区零进入 FG 场景时卡死崩溃。因此没有将它作为 RTX 40 的通用性能补丁导入，也没有用该报告的帧率数字承诺 Aurora 提升幅度。

## 验证记录

代码提交 `b5838339ec3b52d2416c6e8aafedbd23c561492e` 的 [Windows 完整构建、帧/句柄检查、打包上传](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34992007754) 全部成功；[增量格式 CI](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34992007927) 成功。新增说明没有自动设置驱动或修改游戏文件，游戏内布局与实际菜单流畅度仍需用户验证。本机原先提及的异环日志路径及本次尝试的绝区零 Steam 日志路径均没有可读日志，不能据此补出崩溃原因。后续只补交本文验证记录，沿用已通过构建的代码。
