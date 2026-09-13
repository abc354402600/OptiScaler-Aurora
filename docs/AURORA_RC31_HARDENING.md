# RC3.1 Hardening 增量记录

基线 `f452380c`；完整保存在本地 `checkpoint/aurora-rc3-f452380c`。继续使用 `aurora-rc3-installer-20260913`，不修改核心渲染功能，不运行 RC3 81 / RC2 41 / 旧 50 项完整套件。

## 1. 文件系统与路径

实际缺口：路径解析接受 UNC、设备/驱动器相对路径、Windows 尾随点别名；metadata 相对路径依赖当前工作目录；日志比较未统一处理目录尾随分隔符；扫描队列与文件操作之间没有固定目录路径。

修复：拒绝非本地路径、ADS、保留设备名与歧义别名；metadata 仅接受无 `.`/`..` 的本地绝对路径，规范化大小写无关的目录比较；固定目录句柄使用 LIST_DIRECTORY 和禁止 delete sharing（仅 READ_ATTRIBUTES 实测不能阻止重命名）；文件读取使用 OPEN_REPARSE_POINT 并检查句柄类型，拒绝跟随叶节点链接。扫描、JSON 读取/写入、hash、备份/复制和删除使用相应路径保护。

聚焦测试 `Aurora_Path_Safety_Tests.ps1`：25 项通过。junction 扫描/读写、外部 Target/Backup、Root 不一致、路径别名、目录替换和外部哨兵均覆盖。当前 Windows PowerShell 环境不能创建 symbolic link，该分支明确 SKIP 1 项，未冒报通过。备份及报告的外部源/输出路径仍按既有显式用途使用；游戏目标不得逃出 GameRoot。

## 2. 文件占用与故障矩阵

实际问题：Remove 使用 Force 会删除被用户改为只读的受管文件；安装失败后再次写状态/报告失败会掩盖原始错误。现在尊重只读属性，保留原始异常，持久 Pending 状态不会冒充成功。

新增 Aurora_Fault_Matrix_Tests.ps1：12 个注入位置、69 项断言通过。覆盖 preflight、backup、copy、复制后 hash、Move 目标竞态、Pending/Applied journal、初始 index、仅有截断 temp、最终 index 持续失败、Runtime 已改但 Proxy 未写、第一 Proxy 成功第二失败；外部 powershell 进程独占 DLL、只读覆盖/删除及释放后恢复也通过。每个注入点必须确实触发，失败后逐一核对原版 Runtime、已知归属 core 和并发出现的用户文件。不是旧 interrupted-install 测试的重复调用。
