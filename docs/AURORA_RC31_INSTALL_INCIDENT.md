# RC3.1 安装实机问题修复（2026-09-14）

基线：`6ce9ee94`，工作分支：`aurora-rc3-installer-20260913`。本轮只处理安装链路；不修改渲染、6X、Streamline Fetcher 或核心 DLL。研究工作暂停。

## 已从实机日志确认的事实

- 异环旧版安装报告 `9b318d42765448fc94ee7c7305182ec7` 把 AntiCheatExpert 内的 ACE-Service64、ACE-Setup64、ACE-Tray 当作三个候选，向同一个 ACE 目录部署 dxgi。主 Win64 目录没有安装日志；其中 OptiScaler.dll 是用户解压的源文件。旧版的成功提示只证明错误目标的复制完成，并不证明游戏注入成功。
- 主 Win64 同时含 HTGame.exe、CrashCapture.exe、CrashClientReporter.exe。旧版“同目录任何 x64 工具即排除整个目录”误排除 HTGame；同时反作弊过滤漏了 AntiCheatExpert/ACE，评分又把祖先 Win64 的分数给了子目录，三项缺陷共同造成错误部署。
- UE 插件的 DLSS/Streamline 位于 Engine/Plugins/.../ThirdParty/Win64。旧 Runtime 安全过滤把 ThirdParty 一律排除，所以异环没有同步。
- 用户 Remove 后，旧总清单状态是 Removed。随后游戏启动器重建整个 Win64，旧 ACE 部署日志消失；安装入口仍强制要求旧日志存在，导致无法重装。
- 巫师3报告 `771e810a0d304e47a9d56d6ae6f5985a` 确认 `bin/x64` 与 `bin/x64_dx12` 都已部署，DLSS/DLSSG 已同步至 310.9，SL1.5.6 保留。OptiScaler.dll 与 dxgi.dll 共存符合自包含部署设计；解压时已有且内容相同的源文件不会被凭空登记为安装器所有。

## 修复

1. 明确过滤 AntiCheatExpert、ACE、CrashCapture 等程序与目录；Win64/Binaries 评分只应用于直接入口，不再传递到任意子目录。安全筛选按目录缓存，提交前和最终校验重新检查。
2. 异环 HT/Binaries/Win64/HTGame.exe 固定使用 winmm，拒绝 dxgi 等覆盖。保留通用共目录工具保护，仅对该配置中的两个已采集 SHA256 的崩溃组件允许共存：
   - CrashCapture.exe：`1C909503EC05A58552F244654D62105BDA92B16D90F66C6E87B5F69944CA3FB5`
   - CrashClientReporter.exe：`FC334948C58161D706035A17C72DAFABC1BBF309A0EB1AE853EFFE11A25FBD26`
   这是一项有限的兼容配置，不是“静态检查证明任何运行时都不会加载 Proxy”。未知版本或额外工具仍阻止自动安装，反作弊目录始终排除。组件更新后需要重新核对，不能只按名称放行。
3. Runtime 模式允许 ThirdParty 内的原生 DLL 进入原有版本/架构/备份流程；工具和反作弊目录仍保留，SL1 与未知代际仍保护，源 SL2 仍受固定 SHA256 catalog 限制。
4. 已完成 Removed 状态可开始新安装：校验仍存在的日志全部 Restored，归档旧总清单，创建新的目标清单；旧 ACE 目标不会带入新部署。Remove/Restore 不使用此例外，缺日志仍不操作。Applied/Pending/NeedsAttention 缺注册日志不能当作全新安装；另补上更新时缺 Runtime 日志会丢失原版恢复关联的漏洞。
5. 最终成功前重检所有候选、所选 Proxy、完整 payload 和已同步 Runtime。若第一入口的文件在第二入口完成时发生变化，状态为 NeedsAttention，不能显示成功；Remove 仍保留用户修改。
6. Runtime JSON 加入 PostOperation 和实际同步/相同版本/保护计数，保留原诊断 Inventory 作为操作前证据。普通 UI 显示真实入口、Proxy、同步结果，并明确区分磁盘校验与游戏内加载。
7. 新报告集中在 `%LOCALAPPDATA%\Aurora\Logs\<会话ID>`。保留最近 20 次操作，活动会话、未知文件、目录链接不清理；不递归删除、不接触安装清单和备份。旧 Temp 文件不自动删除，故障证据已另存。
8. 当前解压上下文里有游戏但入口被安全策略阻止时，不再悄悄改选另一个 Steam 游戏。

## 验证

- 新增 `Aurora_Install_Incident_Tests.ps1`：49 项，覆盖真实目录形态、ACE 排除、共目录工具例外的严格边界、ThirdParty Runtime、旧 ACE Removed 清单与目录重建、缺 Runtime 日志、双入口、SL1、最终状态异常、日志保留和 junction。
- 新增 `Aurora_Install_Entry_Tests.ps1`：9 项，通过真实 CMD/Windows PowerShell 5.1，模拟“完整包解压到主 Win64 → 自动定位 → Enter 安装 → 更新 → Remove”，区分源 OptiScaler.dll 与生成 Proxy 的 ownership。
- 相关回归：Fault Matrix 69 项、Metadata Fuzz 92 项。仅因本次修改触及事务完成判定与清单读取而回归；未重跑旧 RC3 81、RC2 41、旧 50 项套件。
- 旧 RC3 的普通 UI 断言同步改为“部署完成”，保留禁止散落哈希和逐文件日志的检查；用本轮实际入口输出验证这一受影响断言。Push 自动触发的既有 Actions 仍按原配置运行，未手工要求重跑旧套件。
- 真实目录只读扫描：异环选出唯一 HTGame.exe/winmm；巫师3两个 EXE/dxgi。异环只读 Runtime 检查得到 9 项可同步（3 个 DLSS 系列、6 个 SL2）；没有替换实机文件。
- 测试使用合成 PE；涉及崩溃组件的测试仅在临时测试包内替换两个已知指纹为合成组件指纹，不修改生产配置、不附带真实游戏 EXE。上述测试不证明 GPU/游戏兼容性。

## 更新与实机复测

针对本次异环现场：主 Win64 的文件是完整发布包的解压源文件、没有该目录的安装日志，可以把本次“安装链路热修工具包”覆盖到该 Win64，再运行 Aurora_Setup.bat。确认标题含“安装修复版 20260914”，摘要是 HTGame.exe / winmm.dll。

若要保留游戏内已由清单管理的旧工具不被手工修改，则把完整构建包解压到独立目录，再覆盖热修工具。独立包不一定能自动发现非 Steam 的异环，可从该包目录执行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Aurora_Setup.ps1 -GameRoot "E:\Neverness To Everness\Client\WindowsNoEditor"` 明确选定游戏。不要将仓库替换 ZIP 解压到游戏，也不要把旧 RC2/RC3 ZIP 再覆盖到本次工具上。

如果当前旧记录已经 Removed，直接安装即可，历史总清单会归档。如果仍显示 Applied/NeedsAttention 且旧目标是 ACE，先使用修复包的修复/恢复/卸载菜单按原日志卸载；若日志缺失，保持停止，不删除或伪造 metadata。任何无法证明 ownership 的文件都保留。

实机需确认：异环摘要是 HTGame/winmm，ACE 目录没有新增 Aurora；winmm 存在、dxgi 不生成；游戏内 Insert/加载提示、退出稳定性与启动器行为；9 项 Runtime 同步后的游戏表现以及 Remove 恢复。巫师3验证双入口、SL1.5.6、既有 6X。两个共目录崩溃工具的动态模块行为仍需实际运行核对。

保留的 OptiScaler.dll、手工解压工具或用户修改文件不代表卸载失败。清单与备份有意保留。没有自动修改真实游戏，没有合并 aurora 或发布 Release。
