# Aurora 更新记录

**简体中文** | [English](Changelog.en.md) · [返回首页](README.md)

## 后续维护（尚未发布）

- 修复合法零宽高交换链被当作覆盖层跳过的问题，覆盖普通、DLSSG 和包装调用路径。
- 为 Control Resonant 增加交换链与 Streamline 自动下载兼容策略，保留用户显式配置。
- 详细来源与验证范围见 [10 月 4 日维护记录](docs/COMPATIBILITY_MAINTENANCE_20261004.md)。这些改动不在已发布的 v1.1 包内，不代表相关游戏已完成实机回归。

## v1.1

[正式发行页](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1) · [完整改动与限制](docs/RELEASE_NOTES_AURORA_V1_1.md)

- DLSS SR／RR／FG 更新至 310.9.1，Streamline 更新至 2.14.1；可选神经渲染组件版本保持不变。
- 运行库防降级，保留原生 SL1、较新版本及无法安全识别的组。
- 初始化失败、句柄创建／释放、关闭与共享对象并发保护。
- 帧状态、Reflex、HUD／深度资源复制和 Vulkan 查询结果检查。
- 完整 Windows 构建、兼容性专项检查、运行库清单与打包校验通过；实机边界见发行说明。

## v1.0

[历史发行页](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.0)

建立 Aurora 的 RTX 40 MFG、DLSS 神经渲染、运行库同步及兼容性扩展。旧包保留供历史查阅，不代表当前推荐版本。

## 文档整理（2026-10-04）

首页默认中文，并提供独立英文版；补齐使用指南、兼容性导航及 v1.1 信息。没有改动 DLL、发行标签或已发布安装包。

## 上游历史

[OptiScaler 原始更新记录（英文）](docs/history/CHANGELOG.upstream.en.md)。其中版本号属于上游，不能与 Aurora 版本号混用。
