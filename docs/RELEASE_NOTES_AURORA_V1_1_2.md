# OptiScaler 极光版 v1.1.2

**简体中文** | [English](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/RELEASE_NOTES_AURORA_V1_1_2.en.md)

本维护版吸收官方新增的两项兼容性改进，并包含 v1.1.1 的全部修复。下载下方完整 `OptiScaler_Aurora_v1.1.2_*.7z`，校验值见 `SHA256SUMS.txt`。

## 改动

- **XeLL 模块选择**：普通构建将目标模块查询转交 Windows 按实际选中的 DLL 地址获取引用，避免选中另一份同名库；移除该加载路径修改另一份 DLL 全部导出的旧做法。模块尚未选中、其他名称或带附加标志的查询保留原始处理。低延迟输入构建保持既有路线。
- **Vulkan 菜单**：禁用不支持的 FFX／Combo Nvngx replacement，隐藏强制 XeLL；保留适用的 LatencyFlex 项及中文提示。这是菜单能力约束，不是新增 Vulkan 帧生成后端。

DLSS SR／RR／FG 310.9.1、Streamline 2.14.1 和可选神经渲染组件保持不变。保留 SL1、DualFeature=false、6X 路线及 v1.1.1 零尺寸交换链和 Control Resonant 修复。

## 更新与验证

退出游戏并备份配置，解压完整包后运行 `setup_windows.bat`，确认实际使用的 Proxy 也完成更新。异环继续使用 `winmm.dll`。进入面板确认 Aurora v1.1.2；正常配置无需同时改变 FG 路线。

新增聚焦检查在普通模式执行 118 项、低延迟输入模式执行 108 项，覆盖生产查询函数、失败和转发行为及菜单条件。正式包由标签流程完成 Windows DLL 构建、配置的兼容性检查、运行库和打包校验后发布。

没有新增真实游戏/GPU 或性能基准测试，不承诺 FPS 提升、XeFG 所有并发问题解决，或巫师3闪退／绝区零 11008 全部修复。官方的大型 D3D12 状态跟踪重构未混入本版。

[源码审计](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/UPSTREAM_AUDIT_20261005.md) · [使用指南](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/GUIDE.zh-CN.md)
