# 巫师3高倍率进图偶发闪退：2026-09-15实机证据

## 当前结论

RC3.1安装修复已推送至测试分支，功能提交8c803a6d三项CI全通过。用户确认异环正常、巫师3面板和原6X能运行，随后补充：高倍率帧生成进图时偶发闪退，重启重试可以进入；轻微闪烁尚未仔细观察。因此安装/注入验证成功不等于进图稳定性已经通过。

本轮没有修改游戏配置、运行库、核心代码或正在运行的游戏。未产生声称修复此闪退的patch/DLL。

## 安装结果已核对

00:47真实安装报告为Applied，两入口分别47/46个完整payload文件自检通过。只读复核53条受管核心记录、2条原生DLSS/DLSSG条目和7份备份hash一致；5个原生SL1文件与安装前hash一致，均为1.5.6。受管条目数量不等于完整payload文件数量，已存在的相同解压源文件不自动取得ownership。

## 两次新崩溃

Windows Application事件1000：本地时间00:55:05与00:56:38，witcher3.exe 4.0.1.37654，异常0xc0000005，偏移0x1f1f4ea。两份对应dump（22916、21388）均保留于本地证据目录。

从dump的ExceptionStream、AMD64 Context、ModuleList、MemoryList读取后，二者一致：

- 异常指令：`witcher3.exe+0x1f1f4ea`，字节`44 8b 81 58 03 00 00`。
- 指令：`mov r8d, dword ptr [rcx + 0x358]`。
- 异常参数：读访问，报告地址0xffffffffffffffff；RCX分别为0x0b50000002e702f6与0x0b500000012eed0b，非有效的规范指针值。不能把0xffffffffffffffff直接当成实际对象地址。
- 这是游戏代码读取异常指针的证据，不是已证明的SL1、驱动或Aurora根因。错误指针可能早于出错指令形成；尚无完整符号化调用栈或分配/释放时间线。

诊断脚本仅扫描少量栈内指针作为候选，**没有完成栈展开**。这些候选不能被写成调用链，栈内出现驱动地址也不能归因驱动。

## 与旧dump的对比

| 本地时间 | 游戏内出错位置 | 出错指令/读取地址 | 分类 |
| --- | --- | --- | --- |
| 09-12 11:25 | witcher3.exe+0x1f1f4ea | 同上rcx+0x358，异常参数地址全1 | 与本次同一崩溃签名 |
| 09-13 15:36 | witcher3.exe+0x1f1f4ea | 同上 | 与本次同一崩溃签名 |
| 09-12 11:07 | witcher3.exe+0xfcfbbc | vmovdqu，读取0x2 | 不同签名 |
| 09-12 16:00、09-13 12:14 | sl.dlss_g.dll+0x57b10 | mov eax,[rax+0x110]，读取0x110 | 不同签名，不能与本次合并归因 |

同一签名早于RC3.1重装修复存在，因此当前证据不支持“重装修复首次引入此崩溃”。旧dump的完整配置、倍率、DLL来源尚未建立可比较的控制条件；这不排除旧核心、Mod、帧生成或游戏本身的问题，也不能证明仅高倍率才会发生。

## 用户提供的OptiScaler.log属于哪一轮

捕获副本从00:56:53开始，此时已晚于两次崩溃；对应游戏进程仍存活。配置是Upscaler→DLSSG、InterpolationCount=5，日志显示5生成帧patch成功及Dynamic MFG支持。捕获结束在新一轮启动后约11秒，不能作为此前崩溃的最后日志，也不能据此判定该轮已稳定进入地图。

Logger.cpp使用basic_file_sink并传入truncate=true，新一轮启动会覆盖旧日志。下一次若闪退，先保留OptiScaler.log再启动游戏；现有dump已保留，不需要用户重新制造崩溃。未更改全局日志行为或建立无人值守监控。

## 下一步

1. 优先用匹配EXE/模块和dump做可靠栈展开，确定出错函数及上游调用者；不依据未经展开的栈字值制作补丁。
2. 若需要实机对比，固定同一存档/画质/输入，分别记录进图前启用6X与进图后再启用6X；再比较较低倍率。只改一个变量，记录成功/失败次数；单次成功不证明已修复。用户当前继续观察闪烁，不要求现在重复折腾设置。
3. 闪烁仍存在时再沿既有DLSS/XeSS输入单变量卡验证。SL1原版、DualFeature=false保持。
4. 原神原始ZIP下载未完成（API取commit超时），没有重新解析原作者原始日志。其Create/Release生命周期候选不能套用到此次Witcher异常。

## 证据位置与方法

本任务 `work/witcher-crash-20260915/`：两份新dump、Windows事件、重启后的日志副本、dump-analysis.json、older-dumps.json、comparison.json、SHA256.txt。旧dump原件位于本机CrashDumps；只读解析，未修改。分析脚本 `work/read_witcher_dump.py`，只读mmap+struct解析，Capstone5.0.6反汇编，依赖只安装在本任务work/debug-python-libs，没有安装系统调试器。

格式依据：[微软ExceptionStream](https://learn.microsoft.com/en-us/windows/win32/api/minidumpapiset/ns-minidumpapiset-minidump_exception_stream)、[AMD64 CONTEXT](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-context)。原始dump及本机日志只留本地，不提交公开仓库。
