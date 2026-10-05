# 实验候选：D3D12 状态语义修正

`d3d12-state-semantics.patch` **不是给当前 Aurora 工作树直接应用的补丁**，也不参与构建或打包。其唯一基线是官方 `500ed3354f61c7463e086243f6968645c2a90148`。保留这一层是为了在移植前可重复验证上游缺口及修正，不将未完成适配的整文件混入发行版。

当前修正：

- 首次成功 Reset 创建跟踪记录，保存初始 PSO。
- 增加 `descriptorHeapsKnown`，区分未知堆状态与明确无堆。
- 成功 Reset 明确无堆；零计数绑定允许空数组；无效计数或非零计数空数组在访问前拒绝。
- 恢复明确无堆时实际调用原 SetDescriptorHeaps；未知状态不盲目清空。

验证：

```text
python tests/test_d3d12_state_candidate.py --compiler <zig.exe>
78 candidate state checks passed (CPU stand-ins only)
Mutation rejected: lost-initial-pso
Mutation rejected: ignored-empty-array
Mutation rejected: skipped-empty-restore
```

脚本从 Git 提取固定上游文件，在独立临时目录校验并应用补丁，提取候选的真实状态结构、TLS 声明、Reset/堆记录/恢复函数执行检查。覆盖首次与后续 Reset、失败 Reset 不变、late→early 链式 Hook、空/未知/两堆状态、参数边界、跟踪禁用、线程隔离与嵌套抑制、缺失原函数。每个修正单独撤回后必须导致断言失败。COM/GPU、根签名参数和容器生命周期仍使用替身或未覆盖；不代表 D3D12 全链路已验证。

新增 ClearState early/late Hook，包含 vtable 加载、注册、失败后指针清理，调用原函数后复用重置记录逻辑。新增首次 ClearState、旧参数清空、初始 PSO 与 late→early 串联检查。该验证仍使用命令列表替身，不代表真实 Detours 安装已通过。

## 对象私有状态原型

`D3D12PrivateState.h` 是独立实验原型，尚未接入候选 Hook。通过 `SetPrivateDataInterface` 让对象持有记录，`Read` 取得 shared_ptr 并平衡 GetPrivateData/QueryInterface 引用；不强持有所属 D3D12 对象，避免循环引用。销毁/替换私有接口后，记录在最后一个读取者退出时释放。

```text
python tests/test_d3d12_private_state_candidate.py --compiler <zig.exe>
1029 checks passed: 29 lifetime assertions + 1000 balanced reads (COM stand-in only)
Mutation rejected: read-ref-leak
Mutation rejected: store-ref-leak
```

计数包含 1000 次相同读取的压力断言，不是 1029 种不同场景。其他断言覆盖销毁、同地址重建、读取中替换、写失败、读失败、空参数、未知接口及显式清理。负向变异分别删除 Store/GetPrivateData 的引用释放，必须被断言拒绝。

设计依据：[SetPrivateDataInterface 的对象销毁/覆盖时释放约定](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12object-setprivatedatainterface)、[GetPrivateData 返回接口时增加引用](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12object-getprivatedata)、[ClearState 状态重置约定](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12graphicscommandlist-clearstate)。

**尚未达到生产移植条件：** 私有状态原型需要接入命令列表/签名布局，并处理包装对象身份、模块卸载时回调代码的生命周期、同一对象初始化的串行约束及存储失败后的所有调用点。shared_ptr 不保证内部字段并发写入安全。每种状态必须使用独占的 GUID，不能与其他私有数据混用；不得在模块已经卸载后留下实现于该模块的 COM 对象。正式接入前仍不能宣称对象生命周期已闭环。

官方候选引用 `FGHudfixPersistentBindings`、`ResTrack_Dx12::RegisterRootSignature` 与相关 `OnSet*` 接口，本 Aurora 基线不存在这些接口。移植时必须限定去除这一独立特性的调用，不能未经评审补入整个 HUDfix 功能。

设备捕获、Intel 路径、DLSSNR exposure 跟踪和当前 HookToDevice 的保护应逐函数保留；仅应用候选文件或对上游整文件覆盖会丢掉差异。当前生产源文件未改，完整 Windows DLL 构建将在集成候选成熟后进行，不为此实验补丁重复发布 v1.1.2。
