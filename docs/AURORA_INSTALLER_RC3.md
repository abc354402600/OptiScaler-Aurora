# Aurora RC3 安装器

基线：`aurora-rc2-20260913` / `ab221bf4`。开发分支：`aurora-rc3-installer-20260913`。本轮只修改安装、恢复和报告，不修改核心渲染、DXGI exports、DX12 ImGui、Fetcher 或 6X MFG 路径。

## 普通流程

完整解压发布包，打开 `setup_windows.bat` 或 `Aurora_Setup.bat`。优先识别当前解压位置、已有安装记录及已知游戏目录结构；否则读取 Steam 注册表、常见 SteamLibrary、`libraryfolders.vdf` 和游戏 ACF。存在多个已安装游戏时只选择游戏，不选择唯一 EXE。Steam 库先读取安装元数据，选定游戏后才递归扫描，避免等待整个库扫描完毕。

正常界面只显示游戏、入口目录数、至多三个入口路径和简短保护提示。直接按一次 Enter 开始安装；完成后 Enter 退出，D 查看详细报告。菜单为：一键安装/更新、修复/恢复/卸载、高级工具与诊断。高级模式保留八种 Proxy。没有保存过 Proxy 时默认 dxgi；HTGame 默认 winmm，已有 RC2/RC3 安装沿用此前选择。该默认策略不等于所有游戏版本都已实测。

没有可靠上下文才请求粘贴游戏路径。没有安全入口、扫描不完整、文件冲突或备份损坏时停止写入，不要求玩家猜选一个 EXE 后强行安装。恢复/卸载使用已有清单，游戏 EXE 或可选诊断模块缺失不会阻止 RC3 恢复。

高级无人值守示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Aurora_Setup.ps1 -Action Install -GameRoot 'D:\游戏\The Witcher 3' -PackageDir 'D:\Aurora发布包' -NonInteractive
powershell -NoProfile -ExecutionPolicy Bypass -File .\Aurora_Setup.ps1 -Action Remove -GameRoot 'D:\游戏\The Witcher 3' -NonInteractive
```

`GameExe` 兼容参数只验证该 EXE 通过安全筛选，不缩小默认的冗余部署范围。手动 Proxy 使用 `-Proxy winmm.dll` 等参数；切换已有 Proxy 前需要先卸载，避免并存多个 Aurora Loader。

## 候选与部署

- 复用 RC2 有界扫描器：最多 12000 个目录、18 层、30 秒，不跟随目录联接。候选新增 PE32+、x64、EXE 标志和非 DLL 检查。
- 正向证据包括 Binaries/Win64/Win64r、x64/DX11/DX12 路径、Shipping 等游戏文件名、同目录 DLSS/Streamline/D3D/Unity Runtime、Unity 对应数据目录、PE 导入表中的图形 API。单纯文件大或仅是 x64 EXE 不够。
- 排除 Launcher、Bootstrap、Updater、CrashReporter/CrashHandler、Editor、安装/卸载、EAC/EasyAntiCheat、BattlEye、CEF、Redist、Prerequisite、Engine 工具、工具包、ModManager、Benchmark 等。Crashlands 这类名字不会因为包含 Crash 就被排除。
- **同目录存在被排除的 x64 工具时，整个目录不自动部署。** 目录级 Proxy 也可能被同目录 Launcher 加载，仅过滤文件名无法防止这种影响。这种布局需要维护者评估安全加载方式，普通模式不会绕过。
- 对合理 EXE 按目录去重，每个目录都带独立 Proxy、OptiScaler.dll、INI、完整包内 OptiScaler Runtime 目录、工具及 OptiPatcher。复用 RC2 payload 规则，不转移任意游戏插件、备份或安装状态。所有目录的普通文件完成后，才激活新的 Proxy。
- 所有目标先预检，再取得相应写入前哈希进行逐文件校验；无清单且内容不同的同名文件不覆盖。原有配置保留，新配置仍要求 DualFeature=false。

《巫师3》的 `bin\x64_dx12\witcher3.exe` 与 `bin\x64\witcher3.exe` 都可入选；从任一路径解析上下文会回到游戏根目录。燕云 Win64/Win64r、异环 UE 路径使用通用路径证据，少量已知文件名只增加识别证据或应用已有 Proxy 经验。

## Runtime Group 与保护

原生 Runtime 仍使用 RC2 的版本、架构、SHA256、备份及原子写入机制。每个原生 Runtime 目录形成一个 Group，保存文件信息与候选关联；每个入口保存 `RuntimeGroupIds`。

`SameDirectory` 是同目录磁盘关联；`SharedOrUnresolved` 表示可能共用或尚不能确定，列出可能关联的候选，不能当作实际加载。高级只读诊断按每个 EXE 读取进程模块，只有路径和进程 ID 匹配时才产生 `ObservedBy` / “已观察模块路径”。未启动或访问受限时不猜测。

多个 Group 不意味着各自放开安全限制：**RC3 保留 RC2 全游戏范围的保守 Streamline 保护**。任一原生 SL1、未知代际、未知架构或不可用哈希都会阻止游戏原生 Streamline 同步；这也会保留同一游戏其他目录中的 SL2。引入 Group 没有擅自放宽混合运行库规则。SL1.5.6 继续不替换。DLSS/DLSSG 的未知文件同样保留；DLSSNR 仅记录。

RC3 额外用 `Aurora_RuntimeCatalog.ps1` 固定 RC2 已有 `dist/streamline` 的源文件 SHA256。只有识别为 x64 SL2 且源文件与该目录中的固定字节匹配，才允许同步；仅声称版本为 2.x 的新源文件不够。这个目录确认的是源文件身份，**不宣称已验证所有游戏、驱动或次版本组合**。升级源 Runtime 后应经过维护者验证再更新目录，安装器不自动下载或信任新哈希。

RC3 自动安装只执行一次整个游戏的 Runtime 同步，由一个入口保存 Runtime 日志，避免多个入口争抢同一组共享 DLL。启动器/工具/反作弊目录的 Runtime 只记录不替换；Engine 插件里的原生 Runtime 仍扫描。发现多份尚未恢复的旧 RC2 Runtime 日志时，先恢复原版再升级，不合并来源不明或重叠的备份链。

## 总清单与精确恢复

总清单：`游戏根目录\OptiScaler\AuroraSetup\AuroraInstallManifest.json`，SchemaVersion=3。它是事务索引，记录目标目录、EXE、Proxy、每份 core 日志路径、Runtime 日志所有者、Group 及 Pending/Applied/NeedsAttention/Removed 状态。

文件事务日志继续使用 RC2 格式：

| 记录 | 位置 / 字段 |
| --- | --- |
| 每入口核心文件 | `入口\OptiScaler\AuroraSetup\manifest.json` |
| 原生 Runtime 替换 | `Runtime 所有者入口\OptiScaler\RuntimeSync\manifest.json` |
| 文件记录 | TargetPath、DeployedHash、Created、OriginalHash、BackupPath、BeforeHash、Status |
| 总体报告 | 游戏外临时目录中的 JSON、UTF-8 BOM TXT、操作日志及 Runtime JSON/TXT |

总清单先写，文件日志采用 RC2 的“备份→Pending→原子写入→校验→Applied”。这属于可恢复事务，**不是跨多个目录的全有或全无原子事务**；中断时保留已完成文件和日志，Remove 可以恢复。中断在激活 Proxy 前不会创建新的有效 Loader；原先已安装的 Loader 不会被临时撤掉，因此操作时仍需关闭游戏。

卸载先校验全部将使用的备份，再恢复 Runtime 和核心文件。只删除 Created=true、受清单管理且当前哈希匹配的文件；原本存在且被替换的文件使用已验证备份恢复，并再次校验。任何文件后来被用户或游戏修改，都标记 Preserved 并给出中文提示，其余没有冲突的副本仍继续清理。不会按 DLL 文件名猜测归属，也不会删除未记录的 ReShade、Special K 或其他 Loader。

备份、文件日志、总清单和用户修改保留。未发生过写入的预先存在且字节相同的文件不冒领为新文件；最初手动解压的发布包源文件也不算安装器创建的冗余副本。丢失 Applied 状态下的 core 日志会停止卸载，避免把不完整恢复误报为成功。

## 发布包与验证

打包脚本显式带上新增 Installer、RuntimeCatalog、RC2 恢复入口；CI 通配复制脚本的原流程也包含它们。`setup_windows.bat --legacy` 仍是原历史路径，不享受 RC3 总清单语义；RC3 安装应使用普通入口和 Remove_Aurora。

将累计工具包覆盖到**完整 RC2 发布包**，再用该发布包更新游戏。不要手工覆盖游戏中已经受 manifest 管理的脚本，避免被当作用户修改。工具包不包含新编译的 OptiScaler.dll 或新 Runtime，本轮没有重编译核心的必要。

新增聚焦测试：`tests/Aurora_Installer_Tests.ps1`，使用 Windows PowerShell 5.1、临时目录与 PE fixture。覆盖候选/误排除、PE 导入、中文与空格及特殊符号路径、Steam 多库、冗余部署、目录去重、SL1/未知保护、固定 SL2 源、Runtime 分组和模块关联、RC2 升级、精确卸载、第三方改写、损坏/缺失日志、Proxy 激活前中断、无 EXE/无诊断模块恢复及实际菜单输入。本轮不重跑旧 50 项 / 41 项套件；针对修改过的调用边界加入上述聚焦回归。CI 仍保留旧套件，并增加 RC3 套件。

实机必须核对：巫师3 两种启动方式均能加载；原生 SL1.5.6 哈希不变；当前已验证 OptiFG/DLSSG/6X 配置不变；从任一入口卸载后原生 DLL 恢复；燕云 Win64/Win64r 和异环 winmm 路径实际命中；已有 ReShade/Special K 时冲突提示及保留行为符合预期。脚本测试不证明 GPU 渲染兼容性或 6X 效果。
