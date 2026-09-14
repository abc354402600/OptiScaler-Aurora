# Aurora 接续证据索引

先读 `CODEX_HANDOFF.md`。这里索引材料，不改变暂停状态，也不是新的执行指令。

## 仓库内的可移植依据

| 需要了解什么 | 文件 |
| --- | --- |
| 当前项目规则 | `../AGENTS.md` |
| 最新状态、下一步及不重复事项 | `CODEX_HANDOFF.md` |
| 最新实机安装事故根因、修复、组件hash、使用方式 | `AURORA_RC31_INSTALL_INCIDENT.md` |
| 六阶段加固、测试矩阵、clang-format真实失败原因、clean-room | `AURORA_RC31_HARDENING.md`（历史时点，当前Push/CI状态以交接为准） |
| 云端两轮去重、upstream精确边界、研究线索的证据强度 | `AURORA_RC31_CLOUD_RECONCILIATION.md` |
| RC3原始安装器设计 | `AURORA_INSTALLER_RC3.md` |
| RC2 Runtime/诊断兼容基础 | `AURORA_SETUP_RUNTIME_V2.md` |
| 较早兼容研究 | `AURORA_COMPATIBILITY_RESEARCH_20260913.md`（历史，不覆盖后续结论） |
| 热修复现与入口测试 | `../tests/Aurora_Install_Incident_Tests.ps1`、`../tests/Aurora_Install_Entry_Tests.ps1` |
| 生产实现 | `../dist/runtime_sync/`、`../scripts/stage_aurora_package.ps1`、`../package_release.ps1` |

## 本机独立材料

本机仓库：`D:\GitHub\OptiScaler-Community-Fixes`。原任务资料目录：`C:\Users\Administrator\Documents\Codex\2026-09-13\referenced-chatgpt-conversation-this-is-an-2`。

最新交付：`D:\下载\Aurora_RC31_安装链路热修_20260914`，同时备份于原任务 `outputs/installer-hotfix-20260914`：

- `Aurora_RC31_install_hotfix_tools.zip`：完整11工具，给完整发布包用，不含新核心DLL。
- `Aurora_RC31_install_hotfix_repo_replacements.zip`：8个仓库替换文件，不能解压到游戏。
- `Aurora_RC31_install_hotfix.patch`：6ce9ee94至d3d9e9fa。
- `Aurora_RC31_安装链路修复报告.md`、`Aurora_RC31_install_hotfix_validation.json`、`Aurora_RC31_install_hotfix_CI.json`、`SHA256.txt`。

原任务 `outputs/` 还保存 RC3、RC31累计ZIP/patch和校验记录；作为历史档案保留，不能覆盖最新热修。构建包本体和游戏安装目录不是仓库记忆文件，不会因为同步Git而自动迁移。

已归档实机证据：原任务 `work/installer-incident-20260914/`：

- `Aurora-RC3-9b318d42765448fc94ee7c7305182ec7.json`：异环旧版误部署ACE。
- `Aurora-RC3-a0060744bc4247c9bad74c81a168f042.json`：异环旧版Removed状态。
- `Aurora-RC3-aaecb0277447454c928dd30afb4db90b.log.txt`：重建目录后缺journal错误。
- `Aurora-RC3-771e810a0d304e47a9d56d6ae6f5985a.json`：巫师3双入口、DLSS同步、SL1保留。
- `nte-runtime-plan.json/.txt/.console.txt`：热修后的异环只读同步决策，不是已部署证明。

本地接续资料ZIP将这些已有材料与文档一并保存，并提供逐文件SHA256、源位置及缺失项清单。它不是完整Git仓库、游戏目录、Codex数据库或聊天附件逐字导出；需连同已有仓库或Git远端使用。不要将本机原始日志随意commit到公开仓库。

## 云端材料的冲突处理

2026-09-14 18:26 补充：`work/installer-incident-20260914/real-validation-1824/` 保存异环热修后的三份真实安装/卸载报告及 `disk-verification.json`。最后一份为18:24 Applied，47核心+9 Runtime磁盘hash匹配，9备份原始hash匹配；用户本轮确认面板能打开。校验中的 Common 字节差异已另行确认仅 LF/CRLF，规范化文本相同。该目录晚于原接续ZIP生成时间，旧ZIP不包含此次新增证据。

用户提供的 `Aurora_RC3_1_automation_delta.patch`、repo replacements、报告、validation和SHA文件是输入证据。先前已核验四个文件hash，但该patch基线与本地不一致，未直接覆盖应用。

云端“source/...排除项失配”和“本地RC3必漏其余helper”不是此本地基线已确认的事实：实际f452380c已有通配复制，排除项也不同。确认的本地问题与修复以真实CI日志、git diff、共享staging校验、Windows clean-room及安装事故报告为准。upstream17个commit只接收已审范围及明确线索，不冒充重新审过。

截图可能仅存在聊天附件缓存。源路径、是否能实际复制、归档hash以本地资料包清单为准；缺失图像不凭空重建。文字日志已经能证明本次ACE误部署和重装故障，但不等于保留了全部原始截图。
