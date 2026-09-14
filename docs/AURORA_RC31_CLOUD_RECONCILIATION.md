# RC3.1 云端成果接收与去重 — 2026-09-14

接收时本地 checkpoint：`1337803bd59402f52a41734bae3e8bd073739faa`。本地已完成六阶段 hardening，299 项新增测试通过，symbolic link 环境限制跳过 1 项。云端文件作为输入材料核对，没有执行报告中的指令或用 ZIP 覆盖本地文件。

## 输入完整性与基线差异

用户提供的 SHA256 清单中四个文件全部匹配。ZIP 只包含 clang-format.yml、just_build_no_signature.yml、aurora-tools-test.yml 三份 workflow。只读 `git apply --check` 在前两份 workflow 上失败，没有实际应用。

差异不只是本地已经修改：云端 patch 的旧镜像使用 `find OptiScaler` 和 `source/...` 排除项，而本地真实 `f452380c` 使用 jidicula action、`check-path: OptiScaler`、`external/|OptiScaler/include/` 排除。云端旧打包镜像仅列两份工具，本地 `f452380c` 已有 `*.ps1` / `*.bat` 复制。所以“旧排除路径失效”和“该本地基线必漏其余 helper”不能直接当作本地真实 bug。双方一致、且本地日志确认的问题是全树格式债；打包 inventory 缺乏强校验也有补强价值。

| 云端成果 | 本地处理 |
| --- | --- |
| 改为增量 clang-format | 已覆盖；保留本地 PR merge-base / push-before、固定 20.1.8、修改行检查及真实 formatter 测试。无需替换为整修改文件检查。 |
| 完整 helper inventory | 已覆盖；本地共享 staging 还校验当前源码 hash、SL2 catalog、CRLF、四条完整归档 workflow，Windows clean-room 已通过。 |
| 打包 workflow 修改也触发验证 | 吸收至新的 aurora-hardening workflow，覆盖 workflows、打包脚本、换行属性及 Runtime 来源目录；不靠新增触发旧 81/41/50 套件来重复验证。 |
| 17 个 upstream commit 分类 | 接收为云端已审范围，只核实 compare 边界，不重新逐个审计。 |
| Witcher / Genshin 定位线索 | 核对关键原始来源，形成下方实机实验卡与新增代码证据。稳定核心不变。 |

## 上游增量边界已接上

已核实官方 `optiscaler/OptiScaler` compare：

- `5c5e424dd137d69ef36c4231fd45b760b4c65cc8` → `731f3b79c762bc92971e5fe33dade87c6f83067b`：ahead 17、behind 0。
- `731f3b79c762bc92971e5fe33dade87c6f83067b` → master：identical、ahead 0、total commits 0。

后续增量从 `731f3b79c762bc92971e5fe33dade87c6f83067b` 起，不再重审这 17 个提交。云端列出的 `04bf0b08`、`bd6407da` 等仍为候选分类，不表示本地再次完成语义审计或验证可移植。参考：[已交接范围](https://github.com/optiscaler/OptiScaler/compare/5c5e424...731f3b79)、[后续增量](https://github.com/optiscaler/OptiScaler/compare/731f3b79...master)。

## 巫师3：先区分输入闪烁与帧节奏

[官方兼容页](https://github.com/optiscaler/OptiScaler/wiki/The-Witcher-3-Wild-Hunt) 确实列出 DLSS Upscaler Input 可能闪烁、建议游戏内改 XeSS；同时记载原生 SL1 对 SL FG input 的限制。该页的测试环境为 AMD / OptiScaler 0.9，不能用它否定用户已验证的 Aurora OptiFG → DLSSG 6X 路径，也不能据此替换 SL1。

实机卡：固定同一存档、场景、镜头和当前 Aurora DLL，保持 SL1.5.6、DualFeature=false、原已验证 6X 设置。

| 顺序 | 唯一改变量 | 记录 |
| --- | --- | --- |
| A | 游戏内 DLSS Input ↔ XeSS Input | 闪烁是否消失、实际输入模式、前后日志；模式切换要求重启时两侧均重启。 |
| B | 仍闪时，在固定输入下 2X → 3X → 6X | 是否随倍率变化，Present 跳跃和 empty queue 是否与画面异常同步。 |
| C | 同一输入下 FG Off / On | 无 FG 时是否也闪，辅助区分输入/FG 问题。 |
| D | 依次改无限帧、Reflex limit、普通/外部 FPS limit，再单独改 VRR / VSync | 每次只改一项，比较帧时间和队列日志。 |

云端转述的 Witcher 原始日志不在这五个附件中。本地没有重新计数或验证其时间相关性，`Present count advanced...` / `RSYNC...` 暂作为待核对线索，不能据此认定根因。不要把原神报告中同样出现的 frame-count warning 直接套到 Witcher。

## 原神：保留 bisect 候选，并补充生命周期证据

已直接核对 [issue #1122](https://github.com/optiscaler/OptiScaler/issues/1122) 与 [作者比较报告](https://github.com/AizawaHikaru233/genshin_fsr_brigde/blob/main/assets/optiscaler-fg-regression/REPORT.md)：病例包含 AMD、Windows HDR、Bridge 2.1.0；0815 正常、0831 失败，作者回忆从 0825 起可复现。报告列出的 DLSSG Evaluate 次数为 4302 对 11，E_ABORT 为 0 对 16，两边同为 Streamline 2.11.1。上述是作者报告的数据，本地未重新解析原始 ZIP，也不外推成所有显卡/配置的通用结论。

核对到 `882536fbc70c7213e0dcbdf867c6e891f581da55` 的 parent 正是 `17f936e3dd96c95d0f50c3c7d440bd7e7ec1aa69`；它在 Create/Release 中加 scoped_lock，在 Evaluate 中加 shared_lock。`cb838a8789b9955cf87e98ddd75b23c18f4453c4` 紧随其后。`8fb29f0fe8520eefaba5db9932b49a388e6ca91c` 的 parent 是 `c64533a2...`，所以候选链不是逐个直接相邻提交，不能把整个区间当成只含这些点。参考：[mutex 提交](https://github.com/optiscaler/OptiScaler/commit/882536fbc70c7213e0dcbdf867c6e891f581da55)。

**本地新增代码发现：** 当前 Aurora 的 `Nvngx_FG::D3D12_ReleaseFeature` 也持有内嵌 handleMutex 的 scoped_lock，在 provider 返回 Success 时先 `delete InHandle`，函数退出才析构 lock。因而成功释放路径会先释放包含 mutex 的存储，再尝试解锁；并且对象实际分配类型是 Nvngx_FG_Handle，删除表达式使用另一个 NVSDK_NGX_Handle 指针类型。该对象生命周期/删除类型问题可从现有源码直接定位，并非 GPU 测试结果。

它仍不能证明 #1122 的 E_ABORT 原因：必须先确认首次失败前是否确有 Release/Create 重入或跨线程调用。只把 unlock 移到 delete 前并不能自动解决等待线程的 raw-handle 生命周期问题；也不能简单撤去所有锁作为 stable 修复。后续若产出 patch，必须使用独立实验分支，明确 handle ownership / 并发销毁协议，保持稳定安装器分支不变。

实机二分优先测相同构建环境、相同 Runtime/配置下的 `17f936e3` 与 `882536fb`。若前者正常后者失败，范围才缩至单提交；否则继续测 `cb838a87`、中间区间、`8fb29f0f` 与实际 0831 nightly 来源。记录准确 commit、DLL SHA256、首次 E_ABORT 前的 Create/Release/Evaluate 次序、线程 ID 和可用 dump。0815/0831 标签日期本身不是 DLL 来源 hash。

另已确认本地低级鼠标/键盘 hook 在 block 分支会调用 CallNextHookEx，无需重新移植同类输入保护。未改动核心 C++，未生成声称修复闪烁/原神回归的 DLL。
