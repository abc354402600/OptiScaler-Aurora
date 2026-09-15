# 巫师3 MFG 帧关联实验（尚未实机验证）

用户补充存在轻微、快速闪烁，并授权持续推进。当前优先消除读图和切换崩溃；闪烁不视为同一根因，也不作为本实验修复承诺。

稳定安装器分支保留在b81942a4。本实验从该checkpoint建立独立分支 `experiment/witcher-mfg-frame-sync-20260915`。未更换SL1、DualFeature=false、Runtime或倍率解锁；没有改实机目录。不得直接合并稳定分支。

## 候选实现

1. 1188c757：记录每个资源环形槽实际开始捕获的64位帧号；清除失效记录。Upscaler→DLSSG路径只有捕获、派发、Present三者同帧时才继续。发现失配/资源未准备好时向SL明确发送eOff并保留资源，继续允许游戏Present和后续捕获；不能只依靠上层未处理的false返回值。恢复成功和暂停原因有日志，动态模式checkbox增加独立变化日志。
2. 后续checkpoint：将该路径的DLSSG启用选项提交延后到Reflex设置和本帧constants成功之后。Reflex设置失败、运动矢量对象缺失、启用options失败均尝试明确暂停插帧。其他FG输入保留原选项提交时点。捕获戳使用开始时的帧号快照，避免在NewFrame之后重新读取编号来标记旧槽位。

底层FrameCaptureHistory只是与现有资源生命周期一起维护的标记，不新增全局线程同步，不证明现有共享状态已无竞争。暂停API本身返回错误时会记录失败；不能保证一个已失效的设备仍能服从关闭指令。

## 已完成验证

- 新增22项C++用例，直接调用生产FrameCaptureHistory，覆盖2323/210失配、环形槽碰撞、正常恢复、关闭后的旧数据、倒退计数、64位高位差别和最大计数。Windows上用临时Zig0.14.1 C++驱动编译并运行成功；没有安装系统编译器。最初该驱动的-fsyntax-only返回FileNotFound，改为真实生成对象/EXE后通过；不把失败调用算作通过。
- 现有三个有派发记录的独立会话：日志1共233次，其中232次Present/Dispatch同号，1次相差2113；日志2为226/226同号；日志3为61/61同号。这里只核对编号，不是资源内容/GPU回放。此统计也表明帧号失配不能独自解释日志2/3故障。
- 仅格式化新增/修改的C++行及新文件；没有大范围格式diff，没有重跑旧安装器套件。

完整MSVC/DLL构建、实际Options API失败路径、GPU资源与Reflex重启状态、用户实机均须另外验证。22项策略测试不能被写成22项真实GPU测试。

## 构建与后续判定

未签名workflow仅增加本实验分支触发和专用策略测试，产物名附带EXPERIMENT_MFG及提交前8位；不发布Release。若普通Git连接失败，可在独立 `experiment/witcher-mfg-frame-sync-20260915-ci` 分支用GitHub连接器发布与本地checkpoint相同tree的构建快照。该快照commit可能不同，必须核对tree，不改写本地历史或稳定分支。

实机重点：保存动态设置后读图、动态→固定6X、FG关闭再开启；确认frame guard可恢复且没有持续把FG关闭。比较两类原错误是否仍出现：DEVICE_HUNG/ReflexNotDetected及游戏+0x1f1f4ea。一次进图成功不能算解决。CPU异常指针根因尚未解决，轻微闪烁仍待独立输入对比。

## 2026-09-15 构建交付更新

最终构建提交9a7b03949217c2f317244b2c9d2df4d8338f3042（包含1188c757及后续发布顺序保护）。[未签名构建34918559071](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34918559071)的完整MSVC、22项策略测试、打包及上传全部成功；clang-format34918559012和自动hardening34918559009也成功。此结果补齐上文此前待验的完整编译，不代表GPU实测通过。

Git网络故障已找到原因：WinINET已有127.0.0.1:7897代理，Git没有自动采用。仅本次命令指定http.proxy后普通atomic push成功，稳定安装器b81942a4与实验分支9a7b0394均核对远端ref；aurora保持e1673a1。没有改全局Git配置。GitHub连接器尝试创建blob返回403（集成无写权限），没有创建CI镜像分支或替代提交。

Artifact10377655931已下载到本机，52文件7z测试通过。压缩包SHA256为947926d7fc85659560f9bd5f61c0a359cacf10b9c0d84ec19d7db3cd5b619568，核心25988096字节，SHA256为ef6cd0ddb81c72667d192def8b52eaa657879fb0942413f8a3f4dce89e72ea68。

30项helper/Runtime用`git -c core.autocrlf=true cat-file --filters`读取9a7b0394的实际Windows检出内容，逐字节匹配；配置含DualFeature=false。直接调用stage VerifyOnly最初因审计目录位于资料工作区而被正常拒绝；移至仓库忽略目录后又因本地PS1的LF/混合换行与Actions CRLF不同而拒绝。没有放宽校验或重写包，改用上述Git过滤后的准确参照独立验证通过。源工作区和包的换行差异不能误报为漏打包。

本地交付：`D:\下载\Aurora_巫师3_MFG实验_20260915`。资料工作区`work/mfg-artifact-validation.json`保存逐文件hash，`work/verify_mfg_artifact.py`可重现比对。原始dump保留本地；新增只读DbgHelp尝试虽匹配181个模块PE元数据，但无法取得fault PC的runtime function table，停止于异常帧，**没有获得可靠完整调用栈**。因此CPU异常指针仍未解决，不从猜测调用栈制作补丁。
