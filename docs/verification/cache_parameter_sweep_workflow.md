# Cache 参数扫描与 RTL/资源筛选流程

最后更新：2026-04-25

本文档定义后续 cache/tile/prefetch 优化的固定流程。目标不是单纯追求 hit rate，而是让整帧处理周期数最小，并且保证 RTL 正确、参数合法、资源和时序可落地。

## 参数合法范围

所有自动扫参必须先满足以下硬约束：

| 参数 | 允许值 / 约束 |
| --- | --- |
| `BASE_TILE_W` | `4, 8, 16, 32`，必须是 2 的幂 |
| `BASE_TILE_H` | `4, 8, 16, 32`，必须是 2 的幂 |
| `SET_NUM` | `16, 32, 64, 128, 256`，必须是 2 的幂 |
| `WAY_NUM` | `2, 4, 8` |
| `MERGE_MAX_X` | `1, 2, 4, 8, 16` |
| `ANALYTIC_FIFO_DEPTH` | `8, 16, 32, 64, 128`，默认要求 `>= MERGE_MAX_X` |
| `ANALYTIC_LEAD_PIXELS` | `0, 8, 16, 32, 64, 128, 256, 512` |
| `IMAGE_GEO_RD_BURST_MAX_LEN` | `8, 16, 32, 64` |
| `IMAGE_GEO_RD_MAX_OUTSTANDING_BURSTS` | `2, 4, 8` |
| `IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS` | `16, 32, 64, 128` |
| `IMAGE_GEO_RD_FIFO_DEPTH_WORDS` | `64, 128, 256`，建议 `>= IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS` |
| `IMAGE_GEO_WR_BURST_MAX_LEN` | `8, 16, 32, 64`，首轮先不作为主变量 |
| `IMAGE_GEO_WR_FIFO_DEPTH_PIXELS` | `128, 256, 512, 1024`，首轮先不作为主变量 |

RTL 中 tile 坐标和 tile 内偏移必须用 shift/mask。禁止因为参数扫描重新引入运行时除法。

## 固定流水线

1. 生成参数头：

```powershell
python scripts\gen_param_header.py --out sim_out\cache_sweep\cache_param_override.svh --tile-w 8 --tile-h 8 --set-num 64 --way-num 4 --merge-max-x 8 --fifo-depth 32 --lead-pixels 64 --rd-burst-max-len 16 --rd-max-outstanding-bursts 4 --rd-max-outstanding-beats 16 --rd-fifo-depth-words 64
```

2. 快速模型粗扫：

```powershell
python scripts\run_cache_sweep.py --mode scan --out sim_out\cache_sweep\fast_model_summary.csv
```

3. RTL shortlist 验证。默认可以先 `--dry-run` 检查命令，不允许裸跑长仿真：

```powershell
python scripts\run_rtl_shortlist.py --input sim_out\cache_sweep\fast_model_summary.csv --top-n 5 --dry-run
```

4. 资源/时序筛选。默认先做估算，只有 shortlist 很小且需要最终确认时才使用 `--run-vivado`：

```powershell
python scripts\run_synth_shortlist.py --input sim_out\cache_sweep\rtl_shortlist.csv --out sim_out\cache_sweep\synth_shortlist.csv
```

5. 生成 Pareto 和推荐表：

```powershell
python scripts\report_pareto.py --fast sim_out\cache_sweep\fast_model_summary.csv --synth sim_out\cache_sweep\synth_shortlist.csv --out-dir sim_out\cache_sweep
```

输出重点文件：

| 文件 | 用途 |
| --- | --- |
| `fast_model_summary.csv` | 大规模扫参估算结果 |
| `rtl_shortlist.csv` | RTL 验证结果，包含 pass/fail、cycles、misses 等 |
| `synth_shortlist.csv` | 资源/时序估算或 Vivado 结果 |
| `pareto_summary.csv` | 全局 Pareto 候选 |
| `recommendations.csv` | 按 workload 分类的推荐参数 |

baseline 工作负载矩阵只生成、不自动跑：

```powershell
python scripts\gen_baseline_matrix.py --out sim_out\cache_baseline\baseline_workloads.csv
```

正式 baseline 执行前必须先确认：

- 每个 workload 一个独立进程和输出目录；
- 每条命令都设置 compile/elab/sim timeout；
- prefetch off/on 分开记录；
- 读取 `0x040` 起的扩展统计并写入 CSV；
- timeout、Fatal、AXI assertion fail 均记录为失败轮次，不能写成推荐。

## Workload Matrix

默认快速模型覆盖以下类别，后续可以用 CSV 扩展：

| 类别 | 典型输入 |
| --- | --- |
| 大图到小图 | `7200x7200 -> 600x600`，角度 `0/15/45/75` |
| 宽图/高图 | `7200x4096`、`4096x7200` |
| 中等图 | `1920x1080 -> 600x338` |
| 小图 | `1024x1024 -> 600x600` |
| 近似等比例 | `640x640 -> 600x600` |

## Score

快速模型当前使用的保守 score：

```text
score = total_cycles_est
      + 5 * sample_stall_cycles
      + 10 * replacement_fail_cycles
      + 2 * unused_prefetch_evict_count
```

功能错误、RTL timeout、输出不匹配、资源超过预算或 timing 不过，都必须直接淘汰，不能靠 score 排名保留。

## 执行纪律

- 每次只改一类机制，例如 replacement、scheduler、tile geometry、DDR 参数，不要混在一起。
- 每轮必须记录到 `docs/verification/cache_optimization_iteration_log.md`，这是避免重复犯错的经验文档。
- 任何 sweep 都要一组参数一个进程、一个 case 一个输出目录，并设置 timeout。
- 不允许 prefetch 抢 real miss。
- 不允许 fill 中旧 valid tile 被误命中。
- 所有结论必须能追到 CSV 或 RTL 日志，不能只凭直觉。
