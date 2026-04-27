# RTL 与说明文档同步机制

## 目标

以后每次修改 `rtl/**/*.sv`、`rtl/**/*.svh` 或 `axi/rtl/*.sv` 时，同步提醒维护对应中文说明文档，避免 RTL 行为已经变化但 `docs/modules/*.md`、接口专题或验证状态仍停留在旧版本。

## 检查脚本

手动检查当前工作区：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-rtl-doc-sync.ps1
```

检查本次准备提交的 staged 文件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-rtl-doc-sync.ps1 -Staged
```

## 规则

- 修改普通 RTL 模块时，必须同步修改 `docs/modules/<module_name>.md`。
- 修改 `rtl/top/*` 时，还应同步检查 `docs/README.md` 和 `docs/image_pipeline.md`。
- 修改 `rtl/axi/*` 时，还应同步检查 `docs/interfaces/axi_ddr.md`；CDC/reset 相关模块还应检查 `docs/interfaces/cdc_reset.md`。
- 修改 `rtl/buffer/src_tile_cache.sv` 时，还应同步检查 `docs/cache_and_prefetch.md`。
- 修改 `rtl/sim/tb_*.sv` 时，应同步修改对应 `docs/modules/tb_*.md`，并视情况更新 `docs/verification_status.md`。
- 修改 `axi/rtl/taxi_*.sv` 时，不生成逐模块文档，只同步 `docs/module_index.md` 和接口专题引用。

## Git Hook

仓库提供 `.githooks/pre-commit`，调用 `tools/check-rtl-doc-sync.ps1 -Staged`。启用方式：

```powershell
git config core.hooksPath .githooks
```

启用后，如果 staged RTL 发生变化但对应文档没有 staged 修改，提交会被阻止，并打印需要更新的文档路径。

## 例外处理

如果某次 RTL 修改确实不影响说明文档，也不要空过检查；请在对应模块文档的“维护建议”或“待确认问题”中补一句原因，例如“本次仅调整注释/仿真打印，不改变接口、状态机和时序行为”。这样提交历史中仍然能追溯到文档审阅动作。
