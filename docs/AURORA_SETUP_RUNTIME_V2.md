# Aurora Setup / Runtime Sync v2

本页保留 RC2 行为与 Runtime Sync v2 安全机制的历史说明。RC3 默认界面与冗余部署行为见 [RC3 安装器说明](AURORA_INSTALLER_RC3.md)。

RC2 修改基于 `aurora` 提交 `e1673a16673070401612db04cc0593ca4dc3a6f6`。这是一组安装工具更新，不包含重新构建的 OptiScaler.dll。

## 使用方式

完整解压发布包，运行 `setup_windows.bat` 或 `Aurora_Setup.bat`。选择安装，输入单个游戏目录或 EXE 路径；确认候选主程序、手动选择 Proxy，然后输入对应数字并按 Enter（回车）。

- 支持原有八种 Proxy，拒绝覆盖无法识别的已有同名 Proxy。
- 同时存在多个可能的 EXE 时列出完整路径与排序依据，不把文件名推断当成实际加载结论。
- Launcher 输入可以沿明确的 Launcher/UE/Win64 目录结构扩大到单个游戏范围；不扫描磁盘或整个游戏库。
- Win64/Win64r 都保留为候选。程序大小、UE 路径、同目录运行库只参与排序。
- 已有配置保留。新配置要求包内 `DualFeature=false`；AMD/Intel 用户可手动选择显卡伪装设置。
- 包内 OptiPatcher.asi 会随包部署；新版不联网下载额外插件。原 BAT 保留在 `setup_windows.bat --legacy` 路径，旧选项和 Wine 行为仍可手动调用；该路径保留旧界面及旧卸载逻辑，不享受新版安装清单保护。
- 安装后执行只读检查，再选择是否同步。后续请从目标游戏目录运行检查、修复或卸载工具。

| 操作 | 行为 |
| --- | --- |
| `Check_DLSS_Runtime.bat` | 只读扫描游戏文件；把 JSON 诊断报告写入系统临时目录，并显示路径 |
| `Aurora_Setup.bat` → 运行库修复 | 识别版本、备份、写入操作记录、替换、校验 |
| `Aurora_Setup.bat` → 恢复原版运行库 | 仅从已验证备份恢复，游戏更新/用户修改冲突时保留现状 |
| `Remove_Aurora.bat` | 先恢复运行库，再按新版安装清单卸载；保留用户改过的配置及恢复记录 |

## 安全边界

Runtime Sync 的 `Check` 与旧版行为不同，绝不调用修复。自动调用方要修复时必须显式使用 `-Mode Install`。`-Rescan` 参数仍接受，v2 每次检查完整扫描。

扫描不再排除 Data、Assets、Content 或 Unity 的 `*_Data/Plugins/x86_64`，也不把整个 Engine 目录排除出运行库搜索。只在 EXE 候选筛选阶段排除 Engine/Launcher/Editor 等辅助程序。默认上限：18 层、12000 个目录、30 秒；达到预算、读取失败或跳过链接会报告“不完整”，并阻止同步。小范围运行库诊断可直接指定 GameRoot，但 InstallDir 必须在该范围内。

原生 Streamline 任一已发现组件为 SL1、无法识别或非 x64 时，保留整组游戏原生 Streamline。源包 SL 文件也必须确认是 x64 SL2。即使某个 SL1 文件不在源包名称列表中，也会参与保护判断。识别失败不通过强制版本选项绕过。DLSS/DLSSD/DLSSG 必须可识别版本及架构；`nvngx_dlssnr.dll` 只做清单记录。

这里的版本检查只能识别代际与架构，不保证所有次版本组合兼容。源包应由维护者验证；脚本不联网下载 DLL，不改变已有运行库包。

替换以单个文件为单位使用同目录临时文件和原子替换。替换前先保存 SHA256 校验后的原版备份及 Pending 清单，再替换并校验，最后记录 Applied。升级保留原始备份；进程在替换前后被终止，可根据 BeforeHash / DeployedHash 恢复。**这不是整个游戏目录的全有或全无事务**：中途失败时已有成功操作仍保留，并可从清单恢复。

清单损坏、目标越界、备份越界、缺失必要哈希、备份损坏、目标被第三方修改、链接/目录联接均会停止相关操作。备份不在卸载后自动销毁。使用同一游戏根目录的操作共享锁；运行中的可识别游戏进程会阻止修改。

v1 清单可读取并升级为 v2；必须属于同一规范化安装目录和扫描根。v1 误替换的 SL1 仅在原版备份哈希有效且目标仍等于已部署版本时恢复。`Restore` 不依赖源运行库文件是否还存在。

## 诊断的含义

磁盘清单包含实际路径、版本、代际、架构、SHA256、建议动作和原因。指定 `-GameExe` 后，仅对路径完全匹配的进程读取可访问的模块列表，报告实际模块路径和版本；未启动、受限或已退出都标记未知。

工具不声称检测到了 NVIDIA App AI 插帧、游戏 FG 开关或 6X 能力。有关设置的中文建议明确标注为排查建议。原生 DLSSG 输入与 OptiFG 输入需要不同游戏设置，不能统一要求“打开游戏 FG”。

高级命令示例（路径替换为实际目录）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runtime_sync.ps1 -Mode Check -InstallDir 'D:\ExampleGame\bin' -GameRoot 'D:\ExampleGame' -GameExe 'D:\ExampleGame\bin\Game.exe' -ReportPath 'D:\Reports\Aurora.json'
```

报告必须位于游戏目录外并使用 `.json` 后缀。同目录会生成同名中文 `.txt`，按“发现 → 可能原因 → 操作”列出诊断。如果文本已存在，则保留原文本，只更新 JSON，并在窗口说明。安装菜单的一键检查每次使用新的临时报告文件名。

诊断版本 2.1 在原有 JSON SchemaVersion=2 上新增 `DiagnosticVersion`、`Phase`、`GameExe`、`Processes`、`Findings`；保留原来的清单字段。`Phase=PreOperation` 表示观察发生在本次文件操作之前，不能用安装前清单证明安装后的状态。`DiskSHA256` 是模块路径上的当前磁盘文件哈希，不是内存哈希。报告含有完整本地路径，分享前可自行检查。

未保存游戏 EXE 时，安装目录内恰好只有一个候选，才将它用于本次只读进程观察；多个候选不自动选。进程观察区分未启动、同名不同路径、访问受限、已退出和完整模块快照。只有完整快照才会提示“未观察到可识别的 Aurora”，仍不把此提示当作绝对加载失败结论。

多份同名 Runtime 本身不是错误。诊断会对比实际模块路径、扫描清单和已有同步记录，分别提示扫描范围外副本、未列入清单的副本、同步位置与实际加载位置不同，以及同步后磁盘哈希变化。Aurora 自带 `OptiScaler` 目录的运行库不因未出现在原生清单中而被误报。所有这些判断都不触发修复，也不扩大写入范围。

`Aurora_Diagnostics.ps1` 必须与其他工具一起发布，安装清单负责其备份和卸载。恢复/卸载流程不依赖该诊断模块，缺失时仍能进入原有恢复逻辑。异环 HTGame.exe 的 Proxy 提示来自已有用户实测反馈，仅供手动选择参考，不自动改选或保证所有版本适用。

## 实机回归清单

1. 异环：从 NTELauncher 路径开始，选择 HTGame.exe；用既有已验证 Proxy 对比安装与 Insert 面板。
2. 燕云：同时展示 Win64/Win64r；分别记录真实进程路径，确认实际使用 Win64r 的版本。
3. UE 与 Unity：核对分散目录中的运行库清单；验证无法识别时保留原文件。
4. 巫师3：确认原生 SL1.5.6 哈希不变；使用既有 OptiFG → DLSSG → None (Real DLSSG) 配置，关闭原生 FG、保持 DualFeature=false，比较 2X/3X/6X。
5. 安装→保存游戏内配置→卸载；确认配置保留，Proxy 移除，运行库恢复，其他 Mod 未变。
6. 游戏/启动器更新后先只读检查。出现清单冲突时，不把“停止替换”当成修复成功。

本地自动化测试使用 Windows PowerShell 5.1、编译生成的 x64/x86 PE 测试文件和临时目录，不启动真实游戏，也不证明 GPU 渲染、驱动或 MFG 行为。运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Aurora_Runtime_Tests.ps1`；测试目录保留，便于检查。

诊断的新增定向测试可独立运行：`powershell -NoProfile -ExecutionPolicy Bypass -File tests/Aurora_Diagnostics_Tests.ps1`。包含合成模块观察、真正运行的 x64 测试进程、Unicode 路径下的只读 JSON/TXT、安装后诊断及卸载。此套测试不调用先前的 50 项测试。两套测试均已配置到 CI；本地是否重跑基础套件应根据后续代码变化决定。
