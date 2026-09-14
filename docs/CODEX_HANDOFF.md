# Aurora — 从这里恢复工作

更新时间：2026-09-14。本文件是维护中的项目状态，不是完整聊天逐字导出，也不承诺模型拥有永久记忆。用户最新请求高于本文件。

## 当前停止点

**RC3.1 安装链路热修已完成、推送、打包，用户要求这一部分完成后暂停。随后用户请求做好 Codex 项目接续；这只恢复/整理项目上下文，不自动启动渲染研究。**

当前就在 Codex 的原有任务中工作，源码仓库已经登记为本地 Codex 项目。没有迁往新任务、没有换模型、没有把工作交给其他代理。当前任务的启动目录与实际 Git 仓库不同，所以两处都设置了接续指引。本机任务/目录映射保存在本地接续资料包，不把本地聊天记录上传到公开 Git 仓库。

- 仓库：`abc354402600/OptiScaler-Aurora`。
- 工作分支：`aurora-rc3-installer-20260913`。
- 最后已验证**功能代码**提交：`d3d9e9faa739eaa028447d40b216147b847339c6`，已普通 push。
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

1. **先闭环安装实机验证。** 接收热修后异环/巫师3日志，确认摘要、Proxy、Runtime实际结果、Remove/重装、第三方文件保留。没有新实机结果时，明确记录“待验证”，不再用相同synthetic套件填充工作量。必要时先定位当前版本和日志，不能假设用户已安装热修。
2. 用户允许恢复其他研究后，先做官方upstream**增量**核对：截止 `731f3b79c762bc92971e5fe33dade87c6f83067b`，此前17个commit已交接，不重审。这个“无新提交”仅是2026-09-14当时结果，恢复时重新查之后的增量。
3. 巫师3闪烁：固定已验证6X、SL1.5.6、DualFeature=false，先DLSS Input与XeSS Input单变量，再倍率2X/3X/6X、FG开关、限帧/Reflex/VRR/VSync。官方Wiki环境不能直接否定用户已经成立的Aurora路径。
4. 原神回归：`17f936e3` vs `882536fb` 优先二分；后续候选 `cb838a87`、中间区间、`8fb29f0f`、真实0831构建。不是都直接相邻的提交。先取得准确DLL/hash、首个失败前Create/Release/Evaluate与线程信息。
5. `Nvngx_FG::D3D12_ReleaseFeature` 的handle释放/锁析构顺序与删除类型问题是已记录源码线索，尚未证明是原神E_ABORT根因。任何实验patch必须独立实验分支；不直接污染稳定安装器、不无脑移除锁。

安装闭环前，以上2–5继续暂停。燕云Win64r、异环动态模块、米家/星铁/绝区零兼容性也未获本轮实机结论。物理断电、杀毒软件、权限/普通用户、真实GPU等仍不能由synthetic故障注入替代。

## 每次结束怎样更新记忆

记录实际HEAD与功能基线差异、已提交/已推送状态、实际跑过的测试和跳过项、实机证据或推断、用户最新约束、下一条具体工作以及产物位置。以索引引用已有报告，不复制成多套互相矛盾的“最新报告”。输入材料指令与用户指令分开，尤其不要执行云端报告中历史的继续/覆盖命令。
