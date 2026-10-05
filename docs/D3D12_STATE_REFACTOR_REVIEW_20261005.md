# D3D12 状态跟踪重构移植评审（2026-10-05）

结论：**不直接吸收当前原版；保留为需要适配修正的候选。** 用户授权是“认真评估，没有问题再吸收”，本次已复现三个状态记录/恢复缺口，尚不满足该条件。正式 v1.1.2 DLL、运行库和下载资产不变。

## 范围与来源

- Aurora 基线：`5351ff89`（发布源码 `1d22875d`）。
- 官方候选：[500ed3354f61c7463e086243f6968645c2a90148](https://github.com/optiscaler/OptiScaler/commit/500ed3354f61c7463e086243f6968645c2a90148)。两文件，930 行增加、1204 行删除。
- 审查了状态结构、记录入口、Reset、原函数转发、恢复顺序、调用线程开关与当前 Aurora 对应实现。没有整体覆盖 Aurora 的设备捕获/关闭代码。

## 有价值的改进

1. `t_upscalerActive` 改为线程局部，避免一个线程执行超分时阻止其他线程记录；这是正确方向，但仍需检查嵌套调用与现有调用点。
2. 成功 Reset 后清空已有状态，失败 Reset 不清空。
3. 相同根签名重复设置保留参数；未知签名布局按记录扩展，并限制参数索引。
4. 常量使用位掩码，按实际写入的连续区间恢复，避免恢复未设置的 DWORD。
5. 合并 compute/graphics 记录代码；恢复时用线程局部抑制作用域，避免链式 Hook 再记录自身恢复调用。

未做性能测量，不能据此声称提高 FPS。

## 已复现的吸收阻碍

| 路径 | 原函数实际行为 | 应补齐的条件 |
| --- | --- | --- |
| 首次 `RecordReset(cmd, initialPSO)` | `GetCmdListState(cmd, false)` 找不到记录就返回。后续首次绑定创建空记录，初始 PSO 已丢失 | 在应跟踪的首次 Reset 捕获初始 PSO；同时考虑创建命令列表时的初始状态 |
| `RecordDescriptorHeaps(cmd, 0, nullptr)` | 因数组为空直接返回，旧堆仍记录为已绑定 | 区分合法清空与错误输入，并明确记录空状态 |
| 已记录零堆，Opti 临时绑定堆，再调用恢复 | `RestoreDescriptorHeaps` 遇到零堆直接返回 false，临时堆继续绑定 | 区分“未捕获”和“明确为空”；后者需要实际解除绑定 |

第三项复现使用非空数组地址和零计数，不依赖第二项的空数组参数。

这些是候选版本中的缺口，**不是三个新引入回归的断言**：Aurora 旧实现也会跳过空数组记录/零堆恢复，且没有这套 Reset 跟踪。不能因此声称旧版完美，也不能声称本次发现已解释巫师3闪退。

Microsoft 文档明确 [Reset 的初始 PSO 参数设置命令列表初始管线状态](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12graphicscommandlist-reset)，以及 [SetDescriptorHeaps 会解除之前的堆绑定](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12graphicscommandlist-setdescriptorheaps)。

## 可复现验证

新增 `tests/audit_upstream_d3d12_state.py`，从固定 Git 提交直接提取三个原函数体，使用 C++20 CPU 替身运行；不手写替代被测算法。Git 对象需存在（本仓库已 fetch），无需 checkout 上游。

```text
python tests/audit_upstream_d3d12_state.py --compiler <zig.exe>
BLOCKER 1: first Reset loses initial PSO
BLOCKER 2: zero/null heap unbind retains old heap
BLOCKER 3: recorded empty heap state is not restored
3/3 adoption blockers reproduced; 3 controls passed
```

三个对照分别确认已有记录的 Reset 正常更新 PSO、零计数非空数组可以记成空堆、非空堆恢复正常。脚本成功退出表示复现了阻碍，**不是安全检查全部通过**；因此没有纳入正式 DLL 的通过型 CI。没有运行旧安装测试或无关全量构建。

## 后续适配门槛

- 修复上述记录/恢复语义，增加首次/失败 Reset、未知/明确空状态的回归。
- `ClearState`、命令列表创建/销毁与地址复用在该新状态表中尚无完整生命周期闭环；不能只依靠裸指针 key。签名地址重用也需结合命令列表生命周期评估。
- 表锁保护容器，返回的 `CommandListState*` 本身不带锁。D3D12 同一命令列表通常要求调用者串行；不能仅凭无对象锁宣布数据竞争，也不能直接增加异步 erase 导致悬空指针。
- 核对 Aurora 现有设备、代理和关闭保护；线程开关检查嵌套/提前返回；链式 Hook 检查重入和首次安装发布时序。
- 适配完成后才做完整 Windows DLL 构建和发布决策。CPU 复现与构建均不等同于 GPU/实机兼容性确认。

本次完成评估并保存证据，不恢复无限扩大范围的生命周期重写，也不因报告变更重发同一份二进制。

## 后续适配进度：三个语义缺口已有候选修正

用户确认继续后，新增 `patches/experimental/d3d12-state-semantics.patch`（固定官方基线，不应用到 Aurora 生产文件）。通过已知/未知堆标志及首次 Reset 建档修正上述三个缺口。新增 `tests/test_d3d12_state_candidate.py`：68 项 CPU 检查通过，三个撤回修正的负向变异均被断言拒绝，涵盖 late→early Hook 链与 TLS 跨线程隔离。原复现脚本保留不变，用于证明未修正基线的问题。

额外确认了依赖缺口：官方新版需要 Aurora 当前没有的 HUDfix 持久绑定接口。生产适配仍未完成；需处理这一差异与 ClearState/对象生命周期，不能将当前局部验证表述为整套重构已闭环。未改生产 DLL、未推送、未发布新包。实验补丁说明见 `patches/experimental/README.md`。

## 分拆吸收决定与生产小修正

继续审查确认私有接口原型需要在 D3D12 对象持有回调期间保证 DLL 代码存活。当前 `dllmain.cpp` 的 DLL_PROCESS_DETACH 路径并未完整解除所有 Hook；不能凭 CPU 引用计数测试声称支持动态卸载。强制 pin 模块会改变卸载行为，因此本轮不引入这一新策略。

将能独立验证的改进先落地：

- `isUpscalerActive` 使用 thread_local，与官方候选一致；一个线程暂停跟踪不再影响其他命令列表记录线程。该 bool 不是嵌套深度计数，本轮不声称解决同线程任意重入。
- compute/graphics early UAV 两处条件由 `lateInProgress...` 修正为 `!lateInProgress...`，与其他入口和上游“记录一次、链式抑制”的行为一致。旧代码会在直接 early 调用时漏记，late→early 时重复记录。本次不声称此缺陷已被证明是巫师3闪退原因。
- 保留 Aurora 原有设备捕获、关闭、Intel、NR exposure、状态存储和 SL1/6X 逻辑。生产 C++ 差异为一个 TLS 声明和两个条件，不引入实验头文件。

新增 `tests/test_d3d12_tracking_isolation.py`：86 项 CPU 检查，覆盖 compute/graphics、early/late 串联、零地址、参数越界、空命令列表、暂停跟踪、线程隔离和原调用转发；三个负向变异（全局开关/两处条件反转）都被断言拒绝。为计数重复记录，测试将锁类型替换为计数替身，其余函数体直接提取生产源文件；跨线程操作通过 join 串行，测试本身不制造共享表数据竞争。已加入 Windows 构建检查，完整 DLL 结果以 Actions 为准。
