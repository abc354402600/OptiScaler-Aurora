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

## 5. clang-format CI

核实近期 10 次远端运行，9 次失败、1 次取消。RC2 `ab221bf4` 的 [真实失败日志](https://github.com/abc354402600/OptiScaler-Aurora/actions/runs/34755357249/job/103718694878) 中 checkout、容器和 Ubuntu clang-format 20.1.8 均成功，格式阶段报告 29 个文件、7,699 处 `code should be clang-formatted`，随后 exit 1。例子包括 OptiTypes.cpp、Config.cpp、menu_common.cpp 和生成的 shader headers。`e1673a16..ab221bf4` 没有 C/C++ 修改，只有安装器、文档、构建配置等；旧 workflow 每次检查整个 OptiScaler，历史格式债务导致安装器提交也必红。这是已查日志的确切原因，并非推断全部历史运行均只有同一个原因。

改用固定 clang-format 20.1.8，PR 比 merge-base，push 比 before，首次推送分支比默认分支 merge-base。只检查适用 C/C++ 的新增/修改行，继承 external/include 排除范围；重命名按新文件检查，删除行没有新增代码。完整解析文件生成 replacement XML，按字节偏移对应修改行，只读报告、不改源码。基线缺失/解析失败不能静默通过。无 C++ 变更明确显示检查 0 个文件。

新增 Python 测试 6 项通过，包含真实 clang-format 与临时 Git 仓库：继承格式问题不阻塞干净改动、新违规必须失败、非 C++/删除提交通过、新文件检查全文件、无效基线拒绝、中文空格路径、UTF-8 byte offset、PR/push/new-branch 基线选择。没有对上游 C++ 批量格式化。远端 CI 尚未执行，因为本轮不 Push。

## 6. 打包链 clean-room

发现并修复的实际问题：

- `package_release.ps1` 缺少核心 DLL 时只警告仍可生成 ZIP；现在核心、配置和依赖缺失即停止，旧的成功 ZIP 保持原样。
- Version 直接拼入递归删除路径；现在限制版本名，每次使用新 staging 目录，不再递归删除旧目录。发布目录及源 Runtime 的 junction、外部 Destination 均拒绝。
- 构建失败只按英文 `error ` 字符串判断；现在同时检查 MSBuild 退出码。
- 本地包依赖旧 build output 的 Runtime，Actions 只复制 helper；新增共享 staging/verification 脚本，刷新全部当前 RC3 工具、wrapper、DLSS 和固定 catalog 校验过的 SL2。四条完整归档 workflow 在压缩前调用它，归档命令非零退出不得上传成功；fast workflow 仍明确只提供两 DLL 的迭代补丁，不能作为完整安装包。
- 构建目录中的 RuntimeSync/AuroraSetup 备份、第三方 plugin 和调试文件可能混入本地包；复制时排除恢复状态与任意第三方 plugin，保留包内 OptiPatcher。
- 实际 CMD 启动发现 LF-only BAT 会被错误拆分命令；Git 属性固定 BAT CRLF，打包同时规范化 `git archive` 导出的 LF BAT。普通 `.ps1` 测试无法发现该问题。
- 已部署 Remove BAT 被卸载删除后，CMD 继续读取它会报 `The batch file cannot be found`。改为先退出 BAT 解释上下文再运行 PowerShell，正常/失败退出码均保留；交互结束提示由 PowerShell 负责。仅预解析括号块不足以修复，此方案已用真实 CMD 验证。
- Remove 部分完成后最终 index 写入失败，旧总清单仍可能显示 Applied。现在恢复前持久化 Pending；后续失败尽量登记 NeedsAttention，持续写入故障则保留 Pending，可从解压包重试。

新增验证：75 项 clean-room 断言、6 项 packaging boundary、12 项实际 BAT 入口断言全部通过；最后针对受影响的 journal 登记及 Remove 重新运行本轮新建的 69 项故障矩阵，也全部通过，未运行旧 81/41/50 套件。9 个 workflow YAML 均可解析，PowerShell 脚本语法检查通过。

clean-room 从含中文/空格/方括号的独立源码目录创建 ZIP：故意使用 LF BAT、陈旧 helper、用户备份、第三方 plugin、缺文件/错误 SL2 catalog 输入。实际运行包内 setup_windows.bat，通过输入 Enter 自动定位双 Witcher 入口、同步两个 Runtime Group、用重新打包的 fixture DLL 更新两个 Proxy、保留用户配置；注入最终卸载 index 持续失败后，从包内恢复入口重试；单独 SL1.5.6 游戏从部署目录运行 Remove_Aurora.bat 成功退出。

测试中的 core/DLSS/forwarder 是 synthetic fixture，SL2 使用仓库内固定 catalog 字节。没有编译新的渲染 DLL，也没有执行远端 Actions、签名、NR 下载或 GPU 游戏启动。forwarder 旧有导出名字符串检查不是完整 PE 导出表证明，本轮未把它当作 GPU 能力验证。

## 汇总与边界

299 项新增测试通过，symbolic link 环境限制跳过 1 项。重复执行的本轮受影响测试只计算一次。每阶段独立本地 checkpoint；不 Push、Merge 或 Release。

仍需真实环境核对：Witcher DX11/DX12 双入口、SL1.5.6、6X MFG 与轻微闪烁；燕云 Win64r、异环 winmm/检测行为；真实独占 DLL、杀毒软件/目录权限、管理员与普通用户、断电/系统重启中断恢复；支持创建符号链接的机器；实际构建/签名/下载链与 GPU 驱动。故障注入覆盖异常路径，不等价于物理断电持久化保证。

路径保护需要 Windows 桌面 .NET / Win32 能力；受限语言模式阻止 Add-Type 时会停止，未绕过系统策略。ownership 清单校验不等价于签名认证，无法防御同一权限主体完整伪造一致的文件和全部元数据；损坏或不能证明 ownership 时保留，恢复记录和备份也有意保留。

## 附加增量检查

**后续交接已更新：** 用户补充了两轮云端成果，现已核实截止为 `731f3b79c762bc92971e5fe33dade87c6f83067b`，官方 master 没有更新。下列记录是收到云端材料之前的状态；最终去重、采用内容、实机实验卡和新增生命周期发现见 [云端接收记录](AURORA_RC31_CLOUD_RECONCILIATION.md)。

上游 commit 审计没有擅自重新开始。此前交付报告已注明 `AURORA_RELEASE_AUDIT_updated_20260913.md` 附件不可读；当前仓库和既有交付物仍没有可核实的上次审计截止 SHA。`e1673a16` 只证明 Aurora 曾移植审计过的修复，不能代替上游截止 commit；Git remote 名为 upstream 的地址还是 Susemi fork，不能冒充官方 OptiScaler。因缺乏精确范围，本轮未声称完成新增 commit 审计，也未重复审历史。

2026-09-14 对官方 `optiscaler/OptiScaler` 的 issue/PR 做增量检索，限定 `updated:>=2026-09-13`，分别检索 `flicker`、`Witcher`、`Genshin`、`Zenless`，四组均返回空。这里只能说明这些检索未提供新证据，不能证明没有新问题或修复。没有据此生成推测性 MFG/Streamline patch，没有新增实验分支或修改当前渲染路径。既有兼容性记录保留，真实轻微闪烁和米家兼容性仍待复现证据。
