# OptiScaler 极光版 v1.1.1

**简体中文** | [English](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/RELEASE_NOTES_AURORA_V1_1_1.en.md)

这是 v1.1 的兼容性维护版，正式包包含 10 月 4 日吸收的修复。请下载下方 `OptiScaler_Aurora_v1.1.1_*.7z` 完整包，校验值见 `SHA256SUMS.txt`。

## 更新内容

- 修复游戏以零宽高请求窗口尺寸时，被误判为覆盖层而跳过的问题，覆盖普通、DLSSG 和包装调用的九条创建路径。
- 为 Control Resonant 增加帧生成交换链兼容策略，保留用户显式配置优先级。
- 增加 `[NvApi] DisableOTA=auto`：普通游戏默认不禁用 Streamline 自动下载，Control Resonant 默认禁用；支持显式 true/false。策略在 DLSSG 提前返回前应用，避免漏用。修改后需要完整重启游戏。
- 同步中文默认首页、独立英文说明和包内使用说明。

DLSS SR／RR／FG 仍为 310.9.1，Streamline 仍为 2.14.1；可选神经渲染保持 310.8 Runtime／2.13 插件。保留原生 Streamline 1.x、运行库防降级、DualFeature=false 和原有 6X 路线，不包含 RC3 自动多入口安装器。

## 升级

退出游戏，备份现有配置，按完整包的 `setup_windows.bat` 流程更新，确认所用 Proxy 已更新。异环继续使用 `winmm.dll`。不要将解压完成等同于 Proxy 更新完成；进入游戏后可在面板确认 Aurora 版本为 v1.1.1。使用现有配置时，新增键缺省为 auto。

## 验证与限制

本批生产代码已通过 315 项聚焦检查、两次负向变异验证、完整 Windows DLL 构建、兼容性检查、运行库清单及打包检查；正式标签工作流重新构建并在全部检查成功后发布。

没有新增真实游戏/GPU 验证；不宣称巫师3所有高倍 MFG 闪退、绝区零 11008 或全部游戏兼容问题已解决，也不承诺帧数提升。v1.1 已公开的资源重建、GPU 退役和全局初始化边界继续有效。

[源码与验证说明](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/COMPATIBILITY_MAINTENANCE_20261004.md) · [游戏兼容性](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/COMPATIBILITY.zh-CN.md)
