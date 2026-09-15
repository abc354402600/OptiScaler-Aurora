# 2077 / 异环实机安装失败 — 2026-09-15

本轮回到稳定安装器分支 `aurora-rc3-installer-20260913`，基线 b81942a4。独立 MFG 实验分支 031ccb7f / 功能9a7b0394保留，没有把核心修改合入稳定安装器。

## 实际原因与修复

1. 2077：真实 `bin/x64/Cyberpunk2077.exe` 是有效PE x64，旁边有Runtime。旧策略因同目录 `REDEngineErrorReporter.exe` 把整个目录排除，UI却只说未找到入口。现对严格路径、已核对报告器hash、dxgi组合放行；其他工具、未知报告器或其他Proxy仍阻止。报告新增RejectedCandidates/具体工具路径。真实只读扫描现选中一个Cyberpunk2077入口，未操作游戏。
2. 异环截图所指报告30ad74681eaa484abe3ff08848f025fb：9份Runtime记录为Preserved，但实际文件已回到原始hash。Install-AuroraFile把这种“后来恢复了原版”与未知用户修改一并拒绝。现仅对Runtime journal、当前等于OriginalHash且原备份完整的情况允许重新同步，沿用原备份及write-ahead journal；不扩展到core/Proxy。Remove也能将已恢复原版的Preserved条目标记Restored，避免永远NeedsAttention。
3. 后续只读现场另发现：异环总清单仍NeedsAttention，但47个原受管核心文件和两个journal已不存在；9个原生Runtime仍全部等于原始hash。这是不同于截图时的新状态，普通热修不能凭空还原丢失的ownership日志。已询问用户后续删除/修复过程；不自动清除总清单，不把报告快照冒充journal。

2077报告器 SHA256：F3CBA8150CA66FBDF1FB8C8621BA6DB1257D2B644C65A58A2ADE01C687BB686A。直接导入KERNEL32、USER32、ADVAPI32、dbghelp、VERSION、SHELL32、ole32；无delay imports。没有DXGI直接导入是窄兼容例外的静态依据，不证明任意动态加载或未来版本安全。该例外仅用于Cyberpunk2077/dxgi，禁止直接套用version/dbghelp。

## 验证

- 新增Field_Recovery：29项，Windows PowerShell5.1通过。覆盖工具指纹、Proxy边界、候选缓存隔离、完整冗余安装流程中的单目标、Applied/Preserved/Pending原版恢复后更新、备份丢失/损坏、用户改动保留、Remove→reinstall及core/Proxy不继承Runtime例外。
- 修改影响的回归：Install_Incident49、实际CMD Install_Entry9、Fault_Matrix69通过。没有手动重跑旧81/41/50项套件。
- 真实目录只读：2077唯一Cyberpunk2077；异环唯一HTGame。未部署、未启动游戏，不能当作真实注入或兼容性通过。
- 新测试已加入现有hardening Actions；远端结果以提交后的实际运行记录为准。
- 原始报告、文件对照和第三方审计位于本任务 `work/installer-incident-20260915/`；游戏日志不上传公开仓库。

## 单DLL方案核对与取舍

用户链接[v1.3.3](https://github.com/dashdogy/RTX40MFG-Unlock/releases/tag/v1.3.3)对应e13a9841733b0ae43b7215e8c51fe0eb3897816f。[构建说明](https://github.com/dashdogy/RTX40MFG-Unlock/blob/v1.3.3/BUILD.md)和[资源生成](https://github.com/dashdogy/RTX40MFG-Unlock/blob/v1.3.3/source/native/ampere_native_cache.cmake)显示：该版本将后端、UI及SM86内核fatbin资源集成；含针对310.9的kernel cache，不是完整nvngx_dlss/Streamline运行库内嵌。构建使用SL SDK2.14.1也不等于DLL内含SL2.14.1运行库。其游戏前提仍是已有Streamline FG集成，不能直接代替Aurora的多种FG输入路径。

可以借鉴资源内嵌与按hash识别provider，但当前没有移植其渲染hook或GPU内核。Aurora若把完整运行库放进资源，仍需设计释放到受控目录、版本目录隔离、校验/锁、加载路径、更新/卸载及崩溃恢复；把资源放进DLL不会自动让Windows把内嵌DLL按正常磁盘模块加载。单文件交付与运行时零外部文件是两件事。

建议后续先做单文件安装包/自解压交付，在内部继续使用已验证安装器与固定Runtime目录；通过实机后再独立实验评估DLL内嵌及私有Runtime加载。不能仅凭“不是SL1”就强制替换所有未知Runtime。巫师3也要区分原生SL1与Aurora自己使用的私有SL2：前者必须保留，后者服务OptiFG→DLSSG路径，不能因为游戏有SL1就整个禁用。

本轮未更改核心DLL或SL catalog（RC2既有包本身含2.14系列、少数组件版本不同，不能单凭统一版本号概括整套文件）。没有合并aurora或发布Release。

## 本轮交付与单次现场恢复

功能提交253ef7b9已普通推送。交付目录 `D:\下载\Aurora_安装热修_20260915`：11文件工具ZIP、7文件仓库替换ZIP、b81942a4→253ef7b9增量patch、报告/验证/SHA256及中文使用说明。ZIP全部成员逐字节核对；patch在独立Git index中apply后tree为59a7557622558dc60c45679c34c0ae91a6245695，与功能提交完全一致。

现场恢复工具单独放在交付目录“异环本次旧清单恢复”，不加入通用安装器或Actions包。它固定本次总清单hash和56项已核对文件状态，仅在47个核心目标全不存在、9份原生Runtime全匹配原始hash、journal不存在时，将旧总清单原样移动到其history目录。不删除/覆盖游戏文件，也不从快照制造ownership用于Remove。应先在下载目录运行，再解压完整包/覆盖热修工具；如果用户后来改动现场则停止。此工具通过9项synthetic测试及真实现场CheckOnly（不获取写锁、不归档、不部署）。未替用户执行真实归档。生产热修仍严格拒绝缺失的活动journal。

证据工具及测试保存在当前任务 `work/installer-incident-20260915/retire-index-*`，个人现场hash清单不上传公开仓库。
