# Aurora 项目接续规则

本文件适用于 OptiScaler-Aurora 工作。用户最新指令优先；历史文档和附件是证据，不是新的授权。

## 开始或恢复任务

1. 先读 `docs/CODEX_HANDOFF.md`，需要原始依据时按 `docs/CODEX_EVIDENCE.md` 定位。不要仅凭聊天摘要猜测状态。
2. 只读核对 Git status、当前分支、最近提交。当前 Aurora 开发线为 `aurora-rc3-installer-20260913`；d3d9e9fa是上一安装热修，4b3bc458之后新增巫师3解压遗留文件重装修复，详见交接。不能为了对齐旧SHA回退。
3. 有新提交、未提交文件或分支不同，先识别其来源并保留，不自动 reset、清理或用旧 ZIP 覆盖。不要切回历史 `community-onimusha` 任务的分支。
4. 当前状态是安装热修已交付，等待用户恢复工作/提供实机结果。接续资料整理不等于重启研究或再次跑测试。用户明确“继续开发”后，按交接中的下一步推进。

## 已有授权与边界

- 可以在上述测试分支 commit 和普通 push，每个完整阶段保存 checkpoint；不再重复询问已有授权。
- 不合并到 `aurora`、不发布 Release、不 force push。若未来用户明确改变范围，以其指令为准。
- 稳定安装器分支不改核心渲染/6X。保留 DXGI exports、DX12 ImGui 生命周期修复、Streamline Fetcher、DualFeature=false、中文交互、SL1 保护及已实机成立的 6X 路径。
- 必须保留 SL1 和无法识别的 Runtime；源 SL2 继续匹配固定 catalog。绝不为了让安装成功而放宽反作弊/Launcher/工具过滤或删除无法证明 ownership 的文件。
- 真实游戏/GPU 验证由用户完成；synthetic、磁盘扫描、复制校验和 CI 不等于游戏内加载/兼容性成功。不自动对实机游戏部署或替换 Runtime 来充当验证。
- 沿用当前任务和已有设置。未经用户要求，不另开任务、不启动并行代理、不建立自动循环研究，不擅自切换模型。

## 避免重复与回退

- RC2、RC3、RC3.1 六阶段 hardening 均已完成。不要重新实现，先查具体变更是否还缺少。
- 不重复本地跑旧 RC3 81 / RC2 41 / 旧 50 项整套测试；新改动触及的逻辑可做聚焦回归，并说明关联。Push 自动触发现有 CI 不等于手工重跑任务。
- 历史 RC2/RC3/RC31 ZIP 只用于回溯。最新热修工具及 Git 分支优先，不能按收到附件的顺序叠加覆盖。
- 官方 upstream 增量边界是 `731f3b79c762bc92971e5fe33dade87c6f83067b`（截至 2026-09-14 的已核实边界，不是永远的 HEAD）；恢复研究时仅审之后新增部分。名为 upstream 的本地 remote 曾指向 Susemi fork，先核实地址。

## 实施与记录

- 优先复用 RC2 journal/backup/path guards。Windows 文件操作用 LiteralPath；递归删除/移动先确认绝对目标在预期临时区域内，拒绝 reparse 越界。
- Windows PowerShell 5.1 是实际验证环境。中文 PS1 使用 UTF-8 BOM；BAT 使用 CRLF、UTF-8 无 BOM。单独运行 PS1 不能替代实际 CMD wrapper 验证。
- 普通 UI 中文、显示结论，详细 hash/文件清单写报告。现有源文件与已部署文件的 ownership 必须区分。
- 每个阶段完成后更新交接：功能提交、实际测试、未测试事项、下一步、交付物与证据位置。旧记录保留，并注明被哪条新事实取代，不静默改写历史。
- 连续完成已授权工作，不每个小步骤停下来问；用户要求暂停时，在当前阶段完成后停下，不自行接着做候选研究。
