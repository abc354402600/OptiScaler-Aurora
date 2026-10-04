# 2026-10-04 小范围兼容维护

## 实现

- 参考官方 PR #1183（头 `8abf6d7f`），修复零宽高被当作微型覆盖层的判断。Aurora 的普通/DLSSG 创建钩子及包装调用共九处同步处理。保留显式 1–99 像素尺寸的原有过滤；零尺寸交由 DXGI 从窗口取得，不改调用者描述符。
- CoreWindow 也允许零宽高，已单独核对微软文档，不只机械扩展 HWND 补丁：https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforcorewindow 。
- 采用官方 `1117abdb` 的 Control Resonant `DoNotPreserveFGSwapChain` 策略，继续沿用既有用户配置优先规则。
- 适配官方 `0696cf97` 的 `[NvApi] DisableOTA=auto`。普通游戏默认 false，Control Resonant 自动默认 true；显式 true/false 优先，支持配置读取和保存。仅调整游戏 Streamline 2.x 初始化偏好，清除自动下载与加载下载插件两位，其他位保留，不写原始偏好对象。
- 与上游不同，OTA 处理放在 DLSSG 特征列表分支提前返回之前，避免该分支漏用配置。原生 SL1 初始化、Aurora 私有 Streamline 策略、运行库文件、DualFeature 和 6X 算法均未修改。

来源：https://github.com/optiscaler/OptiScaler/pull/1183 、https://github.com/optiscaler/OptiScaler/commit/1117abdb7fabb62828010d3a6e5ebb8bec7f90be 、https://github.com/optiscaler/OptiScaler/commit/0696cf971a3761dc3f22f2ddb0fc61acff7fd96a 。

## 验证与边界

本地 `test_october_compatibility.py` 从生产源码抽取九个条件、SL2 偏好处理前缀和游戏策略，编译执行 315 项检查通过；同时检查 SL1 分离、配置读写、游戏限定及提前返回顺序。恢复单处旧尺寸误判、去掉用户设置保护的两次负向变异均被测试捕获，随后还原修复。测试加入现有 Windows 构建流程。

这些检查使用 CPU 及接口替身，不模拟完整 DXGI 创建、Streamline 插件加载或真实 GPU，不代表 Soulframe、Control Resonant 或其他游戏已实测通过。本批不声称修复巫师3此前全部崩溃、绝区零 11008，也不承诺帧数提升。

完整 Windows DLL 构建及打包结果将在完成后补充。未通过前不视为正式合并候选。不重开安装器、XeFG 所有权、加载锁或 NR/重投影功能项目。
