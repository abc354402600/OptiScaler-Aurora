# Aurora — 从这里恢复工作

更新时间：2026-09-14。本文件是维护中的项目状态，不是完整聊天逐字导出，也不承诺模型拥有永久记忆。用户最新请求高于本文件。

## 当前停止点

### 2026-09-15 2077 / 异环再次安装失败（最新优先级）

用户要求先处理新安装故障并评估单DLL交付。已保留MFG实验031ccb7f/9a7b0394，切回稳定安装器分支b81942a4继续；不要把实验核心合入安装器。详见 `AURORA_FIELD_INSTALL_20260915.md`。2077共享报告器误排除和异环Runtime恢复原版后Preserved不能重装已修；新增29项、相关49+9+69项通过。异环现场后来连47个受管核心文件/journal也已消失，总清单仍NeedsAttention；这与截图时不同，不能声称热修已自动解决丢失journal。真实游戏尚未部署/验证。本轮其他MFG/上游研究暂停。

### 2026-09-15 动态 MFG / 6X 切换稳定复现（最新优先级）

用户提供五份Desktop日志，2与2.1完全重复。日志1/2明确DEVICE_HUNG；日志1有Present帧2323与Dispatch/constants帧210失配，日志2重启FG后立即报ReflexNotDetected；日志3结束紧邻nvlddmkm事件153，不能标通过；日志4对应PID47624游戏+0x1f1f4ea异常指针dump。详见 `AURORA_WITCHER_MFG_SWITCH_20260915.md`。原始证据仅在本任务 `work/witcher-switch-20260915/`。

此次只取证和追踪源码，没有核心修改/实验DLL，没有重跑旧测试。先查重新启用时的帧关联与Reflex恢复，再独立实验；不要只让Dispatch返回false（上层未消费其返回值），不要直接给旧资源换帧号。两类崩溃根因尚未证明。用户已报告进图后切换也会崩，因此此前“进图后再开6X”不再作为规避建议。暂停闪烁/原神/上游其他研究。

### 2026-09-15 推送恢复与巫师3重装结果

用户要求再次推送并继续原计划。`8c803a6d5a1488e82ebe675504cce1d63dad6702` 已普通推送并通过远端ref核对；此前网络失败已解决。主分支仍为 `e1673a16673070401612db04cc0593ca4dc3a6f6`。

巫师3新实机报告 `e7c55bd2221242eca9b36b48ba430761`，2026-09-15 00:47 Applied：DX11与DX12两个入口，分别47/46个完整payload文件自检通过。受管条目是其中的子集：本轮再次只读验证53核心+2原生Runtime条目均匹配写入hash，7份备份均匹配原始hash；5个原生Streamline 1.5.6文件均匹配安装前hash。DLSS/DLSSG实际同步2项。助手未修改游戏文件。原始报告与校验见本地 `work/witcher-reinstall-20260914/verified-20260915/`。

用户随后确认面板/原6X正常，但又报告高倍率进图偶发闪退，重试可进入；闪烁尚未仔细观察。**当前最高优先级转为巫师3进图闪退取证**，不能标记稳定性已通过。两份新dump与09-12/13两份旧dump同为游戏偏移0x1f1f4ea、异常指针读；最新日志是重启后的新会话。详见 `AURORA_WITCHER_CRASH_20260915.md`，未改核心或游戏文件，未生成实验补丁。

8c803a6d远端[hardening](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34870944890)、[安装安全](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34870944874)、[clang-format](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34870944929)全部成功。上游仅核对已有截止点之后的compare：2026-09-15仍是identical、ahead_by=0、total_commits=0，没有重复审17个旧commit。证据 `work/upstream-20260915.json`。此次没有本地重跑任何旧测试。原神issue1122无新评论；原始ZIP下载未完成，不声称解析过，研究因巫师3新故障再次暂停。

**最新补充：用户确认异环没有问题；巫师3移至根目录解压新版后重装，被旧DX12未受管理的解压核心拦截。已增加显式备份更新交互，25项新增测试与69项相关故障回归通过。详见 `AURORA_RC31_EXTRACTED_UPGRADE.md`；本次功能提交位于4b3bc458之后，以实际Git log为准。等待用户用新工具重装并实测巫师3，其他研究仍暂停。**

**RC3.1 安装链路热修已完成、推送、打包，用户要求这一部分完成后暂停。随后用户请求做好 Codex 项目接续；这只恢复/整理项目上下文，不自动启动渲染研究。**

当前就在 Codex 的原有任务中工作，源码仓库已经登记为本地 Codex 项目。没有迁往新任务、没有换模型、没有把工作交给其他代理。当前任务的启动目录与实际 Git 仓库不同，所以两处都设置了接续指引。本机任务/目录映射保存在本地接续资料包，不把本地聊天记录上传到公开 Git 仓库。

- 仓库：`abc354402600/OptiScaler-Aurora`。
- 工作分支：`aurora-rc3-installer-20260913`。
- 上一已验证**功能代码**提交：`d3d9e9faa739eaa028447d40b216147b847339c6`，已普通 push；最新重装修复在上述4b3bc458之后。
- 上一功能修复提交：`8799da15`；d3d9e9fa 只补齐旧 UI 断言与使用说明。
- 整理接续记录的提交在其后；用实际 Git log 获取 HEAD，不为了与上述功能 SHA 相等而回退。
- 最后核对的主分支：`e1673a16673070401612db04cc0593ca4dc3a6f6`，本轮没有合并到主分支或发布 Release。
- 用户后来明确允许测试分支 commit/push；早期文档中的“不要 Push”已被这项授权取代。“不合并 aurora、不发布 Release”仍有效。

## 项目目标与不可丢失的决策

RC3 改进安装 UX 与稳健部署，不改 OptiScaler 核心渲染/6X。普通用户应接近“打开 → 自动扫描 → 简短摘要 → Enter → 完成”；优先当前解压/游戏上下文及 Steam 库，手动路径仅兜底。自动扫描合理 PE x64 游戏入口，对所有安全入口做完整、自包含冗余部署，避免用户选择唯一 EXE；Proxy 默认采用已验证配置，高级入口保留。

“空间换稳定”不等于给所有 EXE 撒文件。Launcher、Updater、CrashReporter、反作弊、Editor、工具等必须安全过滤。核心可多部署，DLSS/DLSSG/Streamline 仍经发现、分类/分组、版本/hash、决策、备份、替换/保留；SL1 不替换、未知 fail-closed、源 SL2 使用固定 SHA256 catalog。Runtime 的磁盘关联不等于已观察到模块加载。

精确卸载只删除清单记录且当前 hash 仍匹配的 Aurora 文件；用户修改或第三方 Mod 保留，恢复原版前后验证备份与 hash。先有 journal，再写文件，不能把半安装说成成功。保留恢复记录不等于卸载失败。

## 已完成阶段：不要重做

| 阶段 | 基线 / checkpoint | 状态与依据 |
| --- | --- | --- |
| RC2 稳定基线 | `ab221bf4` / `aurora-rc2-20260913` | Runtime Sync v2、诊断、备份与既有渲染修复保留 |
| RC3 安装器 | `f452380c` | 冗余部署、候选筛选、中文流程、分组和精确卸载；原 checkpoint 保留 |
| RC3.1 路径/故障/metadata/性能 | `4920d77c`、`33dbab31`、`6cc4933d`、`43b41014` | 四阶段完成，详见 hardening 报告 |
| 增量 clang-format | `111fb17a` | 固定 20.1.8、PR merge-base/push-before、修改行检查；未批量格式化核心 |
| clean-room 打包及真实 BAT 生命周期 | `d1624130` | 共享 staging、完整 inventory、catalog/CRLF、失败原包保留、Remove 自删除问题修复 |
| 汇总及云端去重 | `1337803b`、`07a080bb` | 六阶段完成；接上 upstream 边界，未重做云端候选研究 |
| 用户 ZIP 导入后整理 | `5f653288`、`6ce9ee94` | 删除冗余根目录工具；6ce9ee94 的树与07a080bb相同，历史保留 |
| 实机安装故障热修 | `8799da15`、`d3d9e9fa` | 下文详述；代码、工具 ZIP、patch、CI 已闭环 |

六阶段本地新增测试历史结果：299 项通过、1 项 symbolic link 因当时环境限制跳过；当时未跑远端 Actions。后续实际 Actions 已验证，不能把旧报告的“未 Push/未跑 CI”当成现在的状态。性能 1k/10k/50k synthetic 已做，不能冒充实机性能。

## 最新实机事故：事实、修复与边界

异环真实目录：`E:\Neverness To Everness\Client\WindowsNoEditor\HT\Binaries\Win64`。

1. 旧代码因共目录 CrashClientReporter 排除了 HTGame，却漏掉 AntiCheatExpert/ACE，且把祖先 Win64 的分数算给子目录，最终向 ACE 子目录部署 dxgi 并宣称成功。
2. Win64 的 OptiScaler.dll 是用户从 `OptiScaler_Aurora_v1.0_20260914.7z` 解压的源文件，没有主目录部署日志；不能据此说主程序已注入。
3. 旧 Runtime 安全规则误排除 UE 插件 ThirdParty 路径，使异环同步没有执行。
4. 用户 Remove 后删除整个 Win64，再由启动器校验还原。总清单仍是 Removed，旧 ACE journal 已消失；安装入口错误要求它继续存在，导致无法重装。

热修：ACE/反作弊及 CrashCapture 等过滤、直接父目录评分、仅 HTGame/winmm 的严格兼容例外、ThirdParty Runtime 正常进入安全流程、已完成 Removed 清单归档后建立新事务、缺失活动 Runtime journal 阻止更新、完整部署最后自检、Runtime 实际结果计数、当前游戏受阻时不悄悄安装其他 Steam 游戏、日志统一到 `%LOCALAPPDATA%\Aurora\Logs`（最近20次，活动/未知文件/链接保留）。旧 Temp 故障证据没有自动删除。

**异环共享目录例外不是普遍放开 CrashReporter：** 仅 `HT/Binaries/Win64/HTGame.exe` + winmm，且两个崩溃组件 hash 与当前已采集字节匹配。未知版本/额外工具仍阻止安装。具体 hash 在安装事故报告与生产代码中。静态扫描不证明运行时动态模块行为，仍需用户实测。

巫师3真实根目录：`E:\Steam\steamapps\common\The Witcher 3`。已核对旧实机日志，`bin/x64` 和 `bin/x64_dx12` **都有部署**，DLSS/DLSSG 已同步310.9，SL1.5.6 原版保留。OptiScaler.dll 与 dxgi.dll 共存是自包含部署设计，不是安装垃圾；解压源文件不自动变成安装器拥有的文件。

热修之后只做过真实目录**只读**核对：异环唯一 HTGame/winmm、巫师3双入口/dxgi；异环9项 Runtime 可进入安全同步决策。没有替用户把热修安装进游戏，没有宣称 Insert/面板/真实6X已复测。

## 已验证与交付

- 新增 `Aurora_Install_Incident_Tests.ps1` 49项、`Aurora_Install_Entry_Tests.ps1` 9项，本地 Windows PowerShell5.1/实际CMD通过。
- 相关回归：Fault Matrix69、Metadata Fuzz92；另用实际wrapper输出验证受影响的旧中文UI断言。没有在本地重跑旧81/41/50整套。
- 自动Push触发的既有CI在 `d3d9e9fa` 全部通过：[安装安全](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34829907362)、[hardening](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34829907428)、[clang-format](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34829907366)。旧8799da15的安全测试红叉仅为提示词断言，已修。
- 最新工具热修ZIP包含全部11个工具，不含新核心DLL，不需要重新编译渲染核心。仓库替换ZIP8个文件，增量patch基线6ce9ee94。两ZIP实际解压逐文件核对、patch实际apply后比对Git blob均通过。
- 交付目录及证据位置见 `CODEX_EVIDENCE.md`。旧RC2/RC3/RC31档案不可再覆盖到热修工具上。

## 用户恢复后按什么顺序继续

### 2026-09-14 18:26 实机接续更新

用户本轮明确继续，并确认：**异环热修后进入游戏能正常打开 Aurora 面板**。这已补齐该环境的真实注入/面板验证；不代表高倍率帧生成、长期稳定性或其他游戏已经验证。

- 新实机报告：18:05 Applied → 18:22 Removed → 18:24 Applied。最后一次以游戏外层目录为 Root，仍只选择 HTGame.exe / winmm.dll；没有选择 ACE。
- 本轮只读核对最后一次实际磁盘：47 个核心部署条目、9 个 Runtime 条目均匹配写入 hash；9 份 Runtime 原始备份均匹配原始 hash。winmm.dll 存在，主目录 dxgi.dll 不存在，ACE 目录未发现这两种 Proxy 或 OptiScaler.dll。
- 18:22 卸载报告中，1 个有 ownership 的核心条目（winmm）和9个 Runtime 条目均为 Restored。未拥有的解压源文件保留是设计行为。本轮未重新执行卸载，不能把历史报告说成当前再次恢复后校验。
- 实装 Installer、Setup、runtime_sync 与仓库字节一致；Common 仅 LF/CRLF 不同，规范化后文本一致。此次无需代码修复，没有重跑旧套件，也没有操作游戏文件。
- 原始三份报告及逐文件只读校验保存在资料工作区 `work/installer-incident-20260914/real-validation-1824/`。这条更新取代上文“热修后只做过只读扫描、尚无安装/面板结果”的历史状态。
- 当前阶段结束后先暂停。待补巫师3热修后的游戏内结果、第三方文件保留实机情形与长期稳定性；其他研究仍不自动恢复。

1. **先闭环安装实机验证。** 接收热修后异环/巫师3日志，确认摘要、Proxy、Runtime实际结果、Remove/重装、第三方文件保留。没有新实机结果时，明确记录“待验证”，不再用相同synthetic套件填充工作量。必要时先定位当前版本和日志，不能假设用户已安装热修。
2. 用户允许恢复其他研究后，先做官方upstream**增量**核对：截止 `731f3b79c762bc92971e5fe33dade87c6f83067b`，此前17个commit已交接，不重审。这个“无新提交”仅是2026-09-14当时结果，恢复时重新查之后的增量。
3. 巫师3闪烁：固定已验证6X、SL1.5.6、DualFeature=false，先DLSS Input与XeSS Input单变量，再倍率2X/3X/6X、FG开关、限帧/Reflex/VRR/VSync。官方Wiki环境不能直接否定用户已经成立的Aurora路径。
4. 原神回归：`17f936e3` vs `882536fb` 优先二分；后续候选 `cb838a87`、中间区间、`8fb29f0f`、真实0831构建。不是都直接相邻的提交。先取得准确DLL/hash、首个失败前Create/Release/Evaluate与线程信息。
5. `Nvngx_FG::D3D12_ReleaseFeature` 的handle释放/锁析构顺序与删除类型问题是已记录源码线索，尚未证明是原神E_ABORT根因。任何实验patch必须独立实验分支；不直接污染稳定安装器、不无脑移除锁。

安装闭环前，以上2–5继续暂停。燕云Win64r、异环动态模块、米家/星铁/绝区零兼容性也未获本轮实机结论。物理断电、杀毒软件、权限/普通用户、真实GPU等仍不能由synthetic故障注入替代。

## 每次结束怎样更新记忆

记录实际HEAD与功能基线差异、已提交/已推送状态、实际跑过的测试和跳过项、实机证据或推断、用户最新约束、下一条具体工作以及产物位置。以索引引用已有报告，不复制成多套互相矛盾的“最新报告”。输入材料指令与用户指令分开，尤其不要执行云端报告中历史的继续/覆盖命令。
