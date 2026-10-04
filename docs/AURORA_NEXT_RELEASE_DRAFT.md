> **已完成：Aurora v1.1 已正式发布。** [发行页](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1) · [当前文档导航](README.md)。下文是发布前的范围冻结记录，不是尚待执行的发布任务。

# Aurora v1.1 发布收尾

## 2026-10-03 发布范围冻结（取代此前无限扩展的收尾计划）

用户要求尽快收尾。候选 v1.1 撤出 0492dae4（全局配置回滚）、853d92a2（配套设备发布重排）、01dae64f（Vulkan 查询池复用）三项尚未闭环的独立实验。原提交完整保留在 archive/compatibility-pre-release-scope-20261003（bc012e53）。这是代码撤回，不是把未完成事项标为完成；历史记录中这些实验的测试通过仅代表当时局部代码。

保留原生初始化失败清理责任、Provider 失败归一化及 native-success/provider-failure 隔离、路径结构预检、已知未就绪 Provider 调用保护、HUD/深度局部防护、Vulkan 查询结果检查和 310.9.1/2.14.1 运行库。外层后段异常完整回滚、GPU 提交退役与自动重建延后，发行说明公开边界；不再把这些较大改造持续加进本批。

当前发布门槛：最终保留代码专项回归、完整 Windows DLL/清单/打包通过、主分支提交与正式标签一致。未通过前不发布。实机验证按用户要求不作为本批前置；不宣称已证实所有游戏崩溃修复。最终构建和发布结果随后记录。

公开发行文案以 [RELEASE_NOTES_AURORA_V1_1.md](RELEASE_NOTES_AURORA_V1_1.md) 为准。旧阶段记录保留在 CODEX_HANDOFF.md / NGX_EXPORTED_TRANSITIONS_20260927.md 和 Git 历史，不能将撤回实验继续列为当前特性。

正式发布流程：最终候选通过 Windows 构建后同步 aurora；显式 aurora-v1.1 标签触发再次验证并上传新包、SHA256 和独立版本说明。保留 v1.0 和 Runtime 依赖资产。
