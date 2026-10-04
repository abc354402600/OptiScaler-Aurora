# OptiScaler 极光版 v1.1

**简体中文** | [English](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/README.en.md)

[项目首页](https://github.com/abc354402600/OptiScaler-Aurora) · [使用指南](https://github.com/abc354402600/OptiScaler-Aurora/blob/aurora/docs/GUIDE.zh-CN.md) · [版本说明](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1)

本版集成 DLSS SR／RR／FG 310.9.1、Streamline 2.14.1；可选神经渲染保持 310.8 Runtime／2.13 插件。新增防降级与初始化、关闭、资源访问保护，默认 `DualFeature=false`。

退出游戏，将完整发行包解压到实际游戏主程序目录，运行 `setup_windows.bat` 并按提示选择 Proxy。异环使用 `winmm.dll`。分别确认安装与 Runtime Sync 结果，进入游戏按 `Insert` 打开面板。卸载使用生成的 `Remove_OptiScaler.bat`，恢复成功前不要删除备份。

本版不包含 RC3 自动多入口安装器。旧 fork 的“单独下载神经渲染文件”“plain／with_DLSS 两种包”和手动全覆盖 Streamline 教程不适用于当前正式包。当前游戏兼容性与未解决问题见项目首页。
