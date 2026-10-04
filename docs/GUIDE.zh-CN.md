# 安装与使用

**简体中文** | [English](GUIDE.en.md) · [返回首页](../README.md)

适用于 Aurora v1.1.1 正式包。它使用传统 `setup_windows.bat` 流程，不会自动给多个游戏入口冗余部署。

## 安装

1. 从 [v1.1.1 发行页](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1.1) 下载 `.7z`。同页提供 `SHA256SUMS.txt`；下载完整包，不要只取 `OptiScaler.dll`。
2. 找到实际游戏主程序目录。可启动游戏，在任务管理器中右键游戏进程，选择“打开文件所在的位置”，然后完全退出游戏。UE 游戏常见位置为 `Binaries\Win64`，启动器所在目录未必正确。
3. 备份已有配置，把包内全部文件解压到这里。若有其他 Mod Loader 的同名 DLL，先确认归属，不要直接覆盖。
4. 运行 `setup_windows.bat`，按提示选择 Proxy。一般可从 `dxgi.dll` 开始；异环使用 `winmm.dll`。切换入口时使用安装／卸载流程，不要保留多个 Aurora Proxy。
5. 分别检查核心安装与 Runtime Sync 的结果。脚本在同步失败后可能继续，因此必须留意同步警告和报告。
6. 启动游戏，按 `Insert` 打开面板。没有该键时可用 `Ctrl + Win + O` 打开屏幕键盘；部分布局可尝试 `Alt + Insert`。

## 从旧版升级

完全退出游戏，先将 `OptiScaler.ini` 复制到游戏目录外备份，再解压完整新版并运行安装。继续选择此前使用的 Proxy；只有确认同名文件属于 Aurora 时才允许覆盖，其他加载器文件不要直接替换。安装结束后按需恢复自己的配置，进入游戏确认面板标题为 v1.1.1。只看到新版 `OptiScaler.dll` 不能证明旧 `dxgi.dll`／`winmm.dll` 已更新。

如果游戏已有正常配置，保留原有 FG 路线，不必为了升级同时更换倍率和输入／输出。新增 `DisableOTA` 缺省为 auto；仅在排查相关插件问题时修改，修改后完整重启。

## 参数调整

- 先确认原始画面和基本加载正常，再逐项调整。不要同时更换 Proxy、FG 输入／输出及多个运行库，以免难以定位问题。
- `FG Input` 是输入路线，`FG Output` 是输出路线。变更路线后保存设置并完全退出、重启游戏。
- RTX 40 MFG 在已验证配置中最高可到 6X，不保证所有游戏都能使用全部倍率。
- 神经渲染为实验功能；模型分辨率可用于权衡画质和开销。原教程的 40% 只是起点，不是所有显卡的最佳值。
- 默认保持 `DualFeature=false`。`Run inside the upscaler` 不是必要开关，部分游戏开启后会花屏或不稳定。

## 运行库、更新与卸载

v1.1.1 集成 DLSS SR／RR／FG 310.9.1、Streamline 2.14.1。可选神经渲染仍使用 310.8 Runtime／2.13 插件。Runtime Sync 根据实际版本、分组和校验结果决定替换或保留；**没有替换不一定是失败**，较新版本、原生 SL1 和无法安全识别的组应保留。

游戏更新或启动器验证后，先等更新完成、退出游戏，再运行 `Check_DLSS_Runtime.bat`，阅读结果。不要用“强制全覆盖”处理未识别的组。

卸载使用安装时生成的 `Remove_OptiScaler.bat`。保留恢复所需的脚本、清单与备份，等恢复成功后再清理。若恢复失败，先关闭游戏并处理报告中的原因；不要先手动删除备份目录。

Windows Runtime Sync 依赖 Windows PowerShell，Wine 下安装脚本会跳过这一步。Proton 的 DLL override 必须对应所选 Proxy，例如 `WINEDLLOVERRIDES="dxgi=n,b" %command%`；这不代表所有 Linux 游戏均已验证。

## 常见问题

| 现象 | 优先检查 |
|---|---|
| 无法打开面板 | 实际 `.exe` 目录、Proxy 是否加载、是否启用游戏支持的超分输入，以及快捷键。 |
| 安装后无法启动 | Proxy 冲突、第三方加载器、版本混用；不要无差别删除目录中的 DLL。 |
| 只显示 2X | 实际加载的 DLSSG／Streamline、FG 路线、保存及重启状态，不只看包内文件版本。 |
| 游戏更新后失效 | 是否恢复了原文件，再运行运行库检查；保留报告。 |
| 开启神经渲染后花屏 | 关闭 `Run inside the upscaler`，必要时重启；保持其他变量不变。 |
| 文件消失或组件异常 | 核对具体文件、启动器恢复记录和安全软件记录；不能单凭现象认定原因。 |

部分卡普空游戏的 Mod 环境可能另需适配的 REFramework；Aurora 不集成它。依赖启动器登录或验证的游戏应完成其正常启动流程。

提交问题请附：Aurora 版本、游戏版本、显卡／驱动、Proxy、FG 输入／输出、复现步骤及相关 `OptiScaler.log`。日志先检查个人路径等信息。[游戏兼容性与已知限制](COMPATIBILITY.zh-CN.md)另有记录。
