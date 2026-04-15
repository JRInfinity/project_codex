# 时序优化记录入口

当前详细历史记录位于：

- [timing_optimization_log.md](/C:/Users/huawei/Desktop/project_codex/docs/verification/timing_optimization_log.md)

为兼容后续查看习惯，本文件保留最近一轮摘要，并作为后续可继续追加的入口。

## 最新一轮

### Round 58

目标热点：

- `image_geo_core_clk` 继续保持正 slack，不动它。
- `image_geo_axi_clk` 新一轮热点回到：
- `words_write_remaining_reg -> aw_prep_len_reg`
- `words_write_remaining_reg -> burst_words_reg`
- `next_write_words_to_4kb_reg -> aw_prep_len_reg`

本轮改动：

- 不动 `core_clk` 相关 RTL，优先保住当前正 slack。
- `axi_burst_writer` 改成两拍 burst planning：
- 新增 `S_PREP_LIMIT`
- 恢复 `words_write_remaining_limited_reg / next_write_words_to_4kb_limited_reg`
- 先限幅锁存，再下一拍生成 `burst_words_reg / aw_prep_len_reg`

验证：

- `ddr_write_engine`、`image_geo_top` 回归通过。

后续：

- 下一步重新跑 implementation，重点确认：
- 写侧 `aw_prep_len / burst_words` 热点是否重新回落
- `core_clk` 是否继续保持正 slack、不反弹
