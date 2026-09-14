# 巫师3动态 MFG / 6X 切换故障：实机证据更新

## 结论与范围

用户已稳定复现：保存动态 MFG 后再次启动，读图有概率闪退；进入地图后关闭动态 MFG、改为固定 6X 或开关 FG，会卡死/闪退。此反馈取代此前“面板和原6X正常”可能造成的稳定性误解：注入已成立，加载与切换稳定性尚未通过。

本轮分析五份用户日志、对应时间段的 Windows 事件和一份新 dump。五份日志实际只有四个独立会话，OptiScaler2.1.log 与 OptiScaler2.log 的 SHA256 完全一致。日志1/2明确记录 GPU DEVICE_HUNG；日志4对应游戏内部异常指针读。两类故障不能合并成同一个已知根因。

没有改游戏文件、SL1、配置、核心源码或安装器，没有生成已修复声明或实验 DLL。没有重跑旧测试。稳定源码基线仍为功能提交8c803a6d（本次开始时记录提交786bbc86）。本报告不推断未知的 UI 操作时点。

## 四次独立会话

时间均为2026-09-15本地时间（UTC+8），行号对应保留原件。

| 日志 | 可直接核实的顺序 | 结果 |
| --- | --- | --- |
| OptiScaler.log | 01:18:26.532946启用FG；26.757514帧号210→2323；26.757597却Dispatch第210帧；26.757751缺少第2323帧constants；32.839254选5生成帧；32.860670应用计数1→5 | 35.429747 DEVICE_HUNG（72979行）；选5生成帧后约2.6秒报告设备挂起 |
| OptiScaler2.log / 2.1 | 动态模式已启用；01:19:26.445744关闭FG；32.029616重新开启；32.750692计数1→5；32.899788运行库进入eOn/5生成帧；32.899802 Reflex未激活错误 | 34.200409 DEVICE_HUNG（66695行）；Reflex报错后约1.3秒 |
| OptiScaler3.log | 动态模式于01:20:22.757207启用；最后一行01:20:24.515039，日志中无[E] | 系统01:20:24.516701记录nvlddmkm事件153，紧邻日志结束；不能标记通过，具体用户操作仍待对应 |
| OptiScaler4.log | 本次日志01:21:38.622054开始；配置计数5；末段FG处于inactive/paused，01:22:01.091453结束，日志无[E] | 01:22:02.699346应用事件1000，PID0xBA08=47624，游戏+0x1f1f4ea，0xc0000005；对应新dump确认异常指针读 |

日志1没有记录动态checkbox改变的确切时刻，因此不能仅凭“计数1→5”断言当时已经进入固定6X。日志2有运行库eOn/numFramesToGenerate=5的独立证据。动态模式下numFramesToGenerate=0也不能单独判为非法。

## 比泛泛的 Flip queue 警告更具体的线索

### A：Present 与派发帧不同步，已实测

日志1第56207–56221行：游戏Reflex PresentStart带2323，Aurora的帧号被从210改为2323；随后GetDispatchIndex仍返回willDispatchFrame=210，Dispatch成功；Streamline接着查找第2323帧constants，只找到第210帧。

源码衔接：

- `Reflex_Hooks.cpp` 的PresentStart分支用游戏marker修改currentFG的FrameCount。
- `IFGFeature::GetDispatchIndex`在最新槽位没有资源时可能沿用_lastDispatchedFrame+1。更新帧号不意味着旧资源和constants已经重新对应新帧。
- `DLSSG_Dx12::Dispatch`用willDispatchFrame创建token并提交constants，而Present marker可以是另一个编号。

这是可观测的帧关联错误，但它距离随后GPU挂起有数秒；尚不能证明它单独导致GPU挂起。禁止简单把旧资源重标成新帧来“消除日志”。

### B：重启 FG 后 Reflex 状态失配，已实测

日志2第63249–63250行：运行库刚恢复固定5生成帧，立即报告 `eDLSSGStatusFailReflexNotDetectedAtRuntime`，附带2067 != 2272。错误在GPU挂起之前，不是仅在崩溃清理阶段出现。

源码中Deactivate关闭DLSSG及Reflex；游戏marker转发要求FG处于active且未paused。Dispatch当前先设置DLSSG options，再设置Reflex options，最后才提交本帧constants。该恢复路径值得优先审计，但两次options调用的顺序不等于完整的执行/Present顺序；只交换两行不能证明修复。

`FGHooks::FGPresent`当前未使用fg->Present()的bool结果控制后续Present；因此仅让Dispatch返回false，不能证明已阻止Streamline使用此前启用的FG状态。任何候选保护必须同时考虑SL实际状态、资源寿命、marker和游戏正常Present，不能直接跳过游戏Present。

### C：CPU异常签名与上述GPU错误分开保留

新dump47624：`witcher3.exe+0x1f1f4ea`，指令 `mov r8d, dword ptr [rcx + 0x358]`；RCX=0x023392e40b500000，为异常指针值；异常参数报告读0xffffffffffffffff。与此前09-12/13及本日00:55/00:56的相同游戏偏移崩溃一致。末段FGinactive并不能排除更早资源/内存错误，也不能证明此次与FG无关。

只解析了dump异常上下文、模块和指令，未获得完整符号化调用栈。栈内候选地址不是可靠展开帧。

## 系统事件旁证

nvlddmkm事件153分别出现在01:18:33.219642、01:19:34.196493、01:20:24.516701、01:21:24.237334。原始XML均有 `Error occurred on GPUID: 100`。第二、第三条紧邻日志2/3末段。第四条在日志4会话开始前，不强行归入该会话。

该事件来自系统进程，未提供游戏PID，不能独立完成进程归属或证明驱动自身有bug；只作为时间关联证据。Application1000则明确指向47624并与新dump匹配。

## 官方约束与候选修复边界

核对了[NVIDIA Streamline DLSS-G指南](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md)的6–8节：Present marker与constants需要匹配帧编号；动态模式不使用固定生成帧数量；options与Present需要确定的调用顺序。指南为当前2.14.1文档，不直接替代已部署版本的行为验证。

下一实验应首先验证“重新启用时等待资源、constants、marker属于同一帧，再恢复SL插帧”，并为动态/固定转换添加明确状态记录。先单独验证帧关联，再考虑Reflex恢复顺序，避免一次改多项导致无法归因。任何核心候选须独立实验分支、独立构建与实机验证，保持SL1原版和DualFeature=false；不移植进稳定安装器，不借机修改倍率解锁或全局锁。

当前还不具备完整GPU资源使用时间线、DRED/设备移除dump或可靠CPU调用栈，不提交猜测性行为补丁。本轮没有可宣称完成的运行时修复。

## 证据与复现状态

本地任务 `work/witcher-switch-20260915/` 保存五份日志原件副本、新dump、dump-analysis.json、gpu-events.json、application-events.json、timeline.json与只读提取脚本extract_timeline.py。SHA256用于去重和后续核对；原始日志/dump/含机器信息的事件仅留本地，不上传公开仓库。

提取器已实际执行：日志1/2各8条[E]，日志3/4为0；0条错误不代表成功。没有把这项文本核对称为GPU测试，也没有触发旧安装器套件。

用户不必继续重复制造同样崩溃；现有样本已足够推进下一阶段定位。此前“进图后再开启6X”的建议现已被新的切换复现否定，暂不作为可用规避方案。闪烁对比等到崩溃链路处理后再恢复。
