# 2026-10-05 增量吸收：XeLL 与 Vulkan 菜单

基线 Aurora `b9e9feb8`（已发布二进制为 v1.1.1 / `b7dbe773`）。官方 master 从 `d63306ea` 到 `500ed3354f61c7463e086243f6968645c2a90148` 新增四个提交。本次继续优先吸收明确、可适配的上游修复，不重审历史、不扩大安装器工作。

## 本批适配

- [3658a08f](https://github.com/optiscaler/OptiScaler/commit/3658a08f2ec7da0f3ad31ba27d3823e5ef1a08f9)：非 LOW_LATENCY_INPUTS 构建也安装 GetModuleHandleExA hook；仅拦截无附加标志、有效输出指针的 `libxell.dll` 查询。已选择模块时，交由原始 Windows API 按模块地址获取引用，不把另一份同名库当作目标；未选择时继续原始查询。移除该路径的全导出重定向，保留低延迟输入构建原行为和其独立初始化路径。未增加延迟加载或模块卸载机制，不声称完整 loader 并发问题已解决。
- [b49177b0](https://github.com/optiscaler/OptiScaler/commit/b49177b0d7b092bc69a94a6a2bb8becfeadd0a1c)：Vulkan 禁用 FFX/Combo Nvngx replacement，隐藏强制 XeLL。保留适用的 LatencyFlex 项、中文提示和 DX11/DX12 菜单行为。此为选项可用性修复，不改现有保存配置或宣称增加 Vulkan 后端支持。

## 不重复搬入的内容

- [ef4e5706](https://github.com/optiscaler/OptiScaler/commit/ef4e57068f7d808b91a12c137608d1a93a8c0e50)：给旧 D3D12 Shutdown 中 currentFeature 解引用加空指针判断。Aurora 的关闭路径此前已改造，旧嵌套 Shutdown 被移除，不恢复旧代码再加判断。
- [500ed335](https://github.com/optiscaler/OptiScaler/commit/500ed3354f61c7463e086243f6968645c2a90148)：D3D12 hook 状态跟踪重构，差异约两千行。涉及命令列表状态及线程录制，不作为小修复整套搬入；需要与 Aurora 资源跟踪、恢复语义逐项比较。
- 官方 release/0.9 仍为 `f1dc3782`，reprojection 为 `44cfee4d`，unify-upscaler-inputs 为 `97a18c36`；PR #1183 仍为 `8abf6d7f`，相关尺寸修复已在 Aurora v1.1.1 完成。

## 相关仓库复核

以下默认分支与 10 月 4 日库存一致：Susemi `3def828d`、RTX40MFG-Unlock `706cb1b8`、原神桥接 `02f54639`、wilsjo2 新 NR 仓库 `1bd39091`、旧 NR 仓库 `97376162`、y4 `7b7220bb`、gprocunier `7233fc0c`、sm86 `9621db57`。这不表示审完全站所有 fork/分支。

deYangar 中文 fork 新到 `b6c9cc5c`，新增翻译空响应兜底修复、官方同步与格式工具更新。Aurora 不使用同一自动翻译流水线，不移植其 CI 改造。原神桥接、巫师3毛发子系统、XeFG 非所属交换链身份和 Streamline 加载锁仍保留上次列出的评审边界，不因暂无新提交就视作已吸收或已解决。

补查上述四个重点仓库的非默认分支：RTX40MFG dev `d00d3b2a` 是 9 月 1 日许可证提交；原神 frame-generation `30ffb903` 是 7 月归档提交，不是比默认分支更新的修复。Susemi input-stuck-key `8d64cbac`（8 月 31 日）涉及重复按键错误吞掉释放事件，Aurora 的 SetKeyDown 和 GetRawKeyboardSanitizeActionLocked 已有对应按下过渡保护。其 proton-overlay-fixes `07bc4a28`（9 月 4 日）涉及覆盖层后端、队列与 DLSSG，包含多项捆绑变更；其中高倍率冻结阈值在 Aurora 已有倍率缩放，剩余 Proton 路径不能整体算成已吸收。NR 仓库 shutdown 分支 `a8eac0c4`（9 月 21 日）头提交是预发布文档，swapchain-review `6cdb5f7e`（9 月 7 日）同为发布记录；后续必须追到具体生产差异，而非以分支名判断新颖性。本轮保留这些截止点，不把旧分支当新发现的紧急修复。

## 验证

`tests/test_xell_module_routing.py` 抽取生产模块查询函数，在普通模式 118 项、LOW_LATENCY_INPUTS 模式 108 项检查通过；覆盖目标/非目标模块、未初始化、Windows API 失败、标志和空指针原样转发，并执行 Vulkan 菜单条件及显示前缀。模块引用由计数替身验证，不是在 Windows loader/GPU 中运行；检查不证明所有模块生命周期安全。

完整 Windows DLL 构建和打包结果随后记录；通过前不把本批称为正式发布。没有真实游戏/性能测试，不承诺 FPS 增幅或巫师3、绝区零症状全部解决。

候选 `b5f5ad62` 的 [Windows run 37219898063](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/37219898063) 完整构建、配置的兼容性检查、运行库、防降级、打包和上传均成功；format 37219897934 成功。另以错误的按文件名查询替换按地址查询，新增测试成功捕获回归，随后恢复代码。发布准备只更新版本和文档/脚本，不增加生产逻辑；正式发布状态以标签流程读回为准。

## v1.1.2 正式发布与独立下载验证

标签 `aurora-v1.1.2` 指向 `1d22875d`。[正式 run 37238662303](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/37238662303) 全步骤成功，格式 run 37238662407 成功；Release 已读回为 latest、非草稿、非预发布。

独立下载公开资产 `OptiScaler_Aurora_v1.1.2_20261004.7z`（219575034 bytes），重算 SHA256 为 `17c608e1a848505ab72dea9ab0e3dce5e192072757189a73bc3fd87fd6e88af8`，与 GitHub 资产 digest、下载的 SHA256SUMS.txt 一致。7-Zip 测试全部通过，48 个文件；DLL ProductVersion 为 `10.0.0-dev-aurora-v1.1.2 (1d22875) (20261004_220649)`。包名/元数据日期来自构建环境，用户侧核验日期为 2026-10-05。仅读取 PE 元数据，未加载 DLL 或改动游戏。
