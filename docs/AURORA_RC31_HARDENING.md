# RC3.1 Hardening 增量记录

基线 `f452380c`；完整保存在本地 `checkpoint/aurora-rc3-f452380c`。继续使用 `aurora-rc3-installer-20260913`，不修改核心渲染功能，不运行 RC3 81 / RC2 41 / 旧 50 项完整套件。

## 1. 文件系统与路径

实际缺口：路径解析接受 UNC、设备/驱动器相对路径、Windows 尾随点别名；metadata 相对路径依赖当前工作目录；日志比较未统一处理目录尾随分隔符；扫描队列与文件操作之间没有固定目录路径。

修复：拒绝非本地路径、ADS、保留设备名与歧义别名；metadata 仅接受无 `.`/`..` 的本地绝对路径，规范化大小写无关的目录比较；固定目录句柄使用 LIST_DIRECTORY 和禁止 delete sharing（仅 READ_ATTRIBUTES 实测不能阻止重命名）；文件读取使用 OPEN_REPARSE_POINT 并检查句柄类型，拒绝跟随叶节点链接。扫描、JSON 读取/写入、hash、备份/复制和删除使用相应路径保护。

聚焦测试 `Aurora_Path_Safety_Tests.ps1`：25 项通过。junction 扫描/读写、外部 Target/Backup、Root 不一致、路径别名、目录替换和外部哨兵均覆盖。当前 Windows PowerShell 环境不能创建 symbolic link，该分支明确 SKIP 1 项，未冒报通过。备份及报告的外部源/输出路径仍按既有显式用途使用；游戏目标不得逃出 GameRoot。

## 2. 文件占用与故障矩阵

实际问题：Remove 使用 Force 会删除被用户改为只读的受管文件；安装失败后再次写状态/报告失败会掩盖原始错误。现在尊重只读属性，保留原始异常，持久 Pending 状态不会冒充成功。

新增 Aurora_Fault_Matrix_Tests.ps1：12 个注入位置、69 项断言通过。覆盖 preflight、backup、copy、复制后 hash、Move 目标竞态、Pending/Applied journal、初始 index、仅有截断 temp、最终 index 持续失败、Runtime 已改但 Proxy 未写、第一 Proxy 成功第二失败；外部 powershell 进程独占 DLL、只读覆盖/删除及释放后恢复也通过。每个注入点必须确实触发，失败后逐一核对原版 Runtime、已知归属 core 和并发出现的用户文件。不是旧 interrupted-install 测试的重复调用。

## 3. Manifest / Journal corruption fuzz

新增 92 项定向损坏输入断言通过：32 个固定随机种子的截断点，空/null/错误对象，缺字段，重复/转义/大小写冲突 JSON key，重复路径，不正确类型或 hash，矛盾 Created/OriginalHash/BackupPath，外部目标，跨日志 ownership 冲突，缺失 Runtime 日志，总 index 丢失后的旧版回退，以及伪造 core entry 指向用户存档。

实际修复：Created=true 但仍有原始文件/备份的矛盾条目以前可能被当作新文件删除；恢复函数直接接收的内存对象以前没有重新校验；不同日志之间没有 ownership 去重；missing Runtime journal 被当作空日志；missing RC3 index 可能进入 RC2 单入口卸载。现在严格校验类型/字段/路径，读取拒绝重复 key，限制 JSON 为 8 MiB；新增 journal 登记位在写文件前持久化；core 恢复只接受 Aurora payload 范围，跨日志冲突在任何恢复前拒绝。

旧 RC3 记录如缺少 Runtime 日志且无法证明从未替换，保守停止，不能声称已经恢复原版。结构和 hash 校验不是数字签名：有权限同时伪造全部一致 metadata 与文件的同一用户不在认证边界内；任意外部 Root 逃逸仍禁止。

## 4. 扫描性能

保留 Content/Assets/Engine 全目录发现，不采用可能漏掉插件 Runtime 或备用 EXE 的名称剪枝，也不缓存跨事务候选。改为 .NET 原生按 *.exe / nvngx_dlss*.dll / sl.*.dll 枚举文件，再复用相同安全过滤；目录仍检查 junction。

14 项性能/一致性断言通过。单次本机 synthetic 测量（总耗时含候选识别，缓存/首次初始化会影响时间，非真实游戏加载时间）：

| 资产文件 | 原扫描 ms | 过滤枚举 ms | 原构造对象 | 新构造对象 | 目录数 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1k | 243.25 | 88.53 | 1021 | 21 | 15 |
| 10k | 202.08 | 51.85 | 10030 | 30 | 24 |
| 50k | 976.56 | 103.71 | 50070 | 70 | 64 |

对象数量指交给脚本的 FileInfo/DirectoryInfo，不声称 NTFS 内部完全不访问被筛掉的目录项。每个规模仍找到 3 个相同安全入口与全部原生 Runtime；新增共目录 Launcher 会立即撤掉相应候选，junction 不被遍历。结果保存在 scan-performance.json。
