`timescale 1ns/1ps

`ifndef SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS
`define SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS 64
`endif

`ifndef SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH
`define SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH 32
`endif

`ifndef SRC_TILE_CACHE_BASE_TILE_W
`define SRC_TILE_CACHE_BASE_TILE_W 8
`endif

`ifndef SRC_TILE_CACHE_BASE_TILE_H
`define SRC_TILE_CACHE_BASE_TILE_H 8
`endif

`ifndef SRC_TILE_CACHE_SECTOR_SET_NUM
`define SRC_TILE_CACHE_SECTOR_SET_NUM 64
`endif

`ifndef SRC_TILE_CACHE_SECTOR_WAY_NUM
`define SRC_TILE_CACHE_SECTOR_WAY_NUM 4
`endif

`ifndef SRC_TILE_CACHE_MERGE_MAX_X
`define SRC_TILE_CACHE_MERGE_MAX_X 8
`endif

`ifndef SRC_TILE_CACHE_ENABLE_MERGE_MIN
`define SRC_TILE_CACHE_ENABLE_MERGE_MIN 0
`endif

`ifndef SRC_TILE_CACHE_MERGE_MIN_X
`define SRC_TILE_CACHE_MERGE_MIN_X 1
`endif

`ifndef SRC_TILE_CACHE_FIFO_AGE_LIMIT
`define SRC_TILE_CACHE_FIFO_AGE_LIMIT 0
`endif

`ifndef SRC_TILE_CACHE_ENABLE_PREFETCH_THROTTLE
`define SRC_TILE_CACHE_ENABLE_PREFETCH_THROTTLE 0
`endif

`ifndef SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES
`define SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES 0
`endif

`ifndef SRC_TILE_CACHE_ENABLE_ROW_BUCKET_MERGE
`define SRC_TILE_CACHE_ENABLE_ROW_BUCKET_MERGE 0
`endif

`ifndef SRC_TILE_CACHE_ROW_BUCKET_MIN_X
`define SRC_TILE_CACHE_ROW_BUCKET_MIN_X 3
`endif

module src_tile_cache #(
    parameter int PIXEL_W   = 8,
    parameter int ADDR_W    = 32,
    parameter int MAX_SRC_W = 7200,
    parameter int MAX_SRC_H = 7200,
    parameter int MAX_DST_W = 600,
    parameter int MAX_DST_H = 600,
    parameter int COORD_W   = 48,
    parameter int TILE_W    = 16,
    parameter int TILE_H    = 16,
    parameter int TILE_NUM  = 4
) (
    input  logic clk,
    input  logic sys_rst,

    input  logic                           start,
    input  logic [ADDR_W-1:0]              src_base_addr,
    input  logic [ADDR_W-1:0]              src_stride,
    input  logic [$clog2(MAX_SRC_W+1)-1:0] src_w,
    input  logic [$clog2(MAX_SRC_H+1)-1:0] src_h,
    input  logic [$clog2(MAX_DST_W+1)-1:0] dst_w,
    input  logic [$clog2(MAX_DST_H+1)-1:0] dst_h,
    input  logic signed [31:0]             rot_sin_q16,
    input  logic signed [31:0]             rot_cos_q16,
    input  logic                           geom_ready,
    input  logic                           geom_error,
    input  logic signed [COORD_W-1:0]      geom_step_x_x,
    input  logic signed [COORD_W-1:0]      geom_step_y_x,
    input  logic signed [COORD_W-1:0]      geom_step_x_y,
    input  logic signed [COORD_W-1:0]      geom_step_y_y,
    input  logic signed [COORD_W-1:0]      geom_row0_x,
    input  logic signed [COORD_W-1:0]      geom_row0_y,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] geom_src_x_last,
    input  logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] geom_src_y_last,
    input  logic signed [COORD_W-1:0]      geom_src_x_max_q16,
    input  logic signed [COORD_W-1:0]      geom_src_y_max_q16,
    input  logic                           prefetch_enable,
    input  logic [15:0]                    runtime_lead_pixels,
    input  logic [7:0]                     runtime_merge_max_x_eff,
    input  logic [7:0]                     runtime_merge_min_x,
    input  logic [15:0]                    runtime_fifo_depth_eff,
    input  logic [15:0]                    runtime_fifo_age_limit,
    input  logic [15:0]                    runtime_prefetch_throttle_cycles,
    input  logic [1:0]                     runtime_scheduler_policy,
    input  logic signed [1:0]              scan_dir_x,
    input  logic signed [1:0]              scan_dir_y,
    input  logic                           scan_dir_valid,
    output logic                           busy,
    output logic                           error,

    output logic              read_start,
    output logic [ADDR_W-1:0] read_addr,
    output logic [31:0]       read_row_stride,
    output logic [31:0]       read_byte_count,
    output logic [15:0]       read_row_count,
    input  logic              read_start_ready,
    input  logic              read_busy,
    input  logic              read_done,
    input  logic              read_error,
    input  logic [PIXEL_W-1:0] in_data,
    input  logic               in_valid,
    input  logic               in_row_last,
    output logic               in_ready,

    input  logic                                              sample_req_valid,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x0,
    input  logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y0,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x1,
    input  logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y1,
    output logic                                              sample_req_ready,
    output logic [PIXEL_W-1:0]                                sample_p00,
    output logic [PIXEL_W-1:0]                                sample_p01,
    output logic [PIXEL_W-1:0]                                sample_p10,
    output logic [PIXEL_W-1:0]                                sample_p11,
    output logic                                              sample_rsp_valid,
    output logic [31:0]                                       stat_read_starts,
    output logic [31:0]                                       stat_misses,
    output logic [31:0]                                       stat_prefetch_starts,
    output logic [31:0]                                       stat_prefetch_hits,
    output logic [31:0]                                       stat_analytic_candidates,
    output logic [31:0]                                       stat_analytic_duplicates,
    output logic [31:0]                                       stat_analytic_blocked,
    output logic [31:0]                                       stat_analytic_fills,
    output logic [31:0]                                       stat_prefetch_evicted_unused,
    output logic [31:0]                                       stat_total_cycles,
    output logic [31:0]                                       stat_sample_req_count,
    output logic [31:0]                                       stat_sample_accept_count,
    output logic [31:0]                                       stat_sample_stall_cycles,
    output logic [31:0]                                       stat_normal_prefetch_fills,
    output logic [31:0]                                       stat_fifo_max_occupancy,
    output logic [31:0]                                       stat_read_busy_cycles,
    output logic [31:0]                                       stat_read_bytes_total_low,
    output logic [31:0]                                       stat_read_bytes_total_high,
    output logic [31:0]                                       stat_useful_source_sectors,
    output logic [31:0]                                       stat_replacement_fail_cycles,
    output logic [31:0]                                       stat_miss_service_latency_min,
    output logic [31:0]                                       stat_miss_service_latency_max,
    output logic [31:0]                                       stat_miss_service_latency_sum_low,
    output logic [31:0]                                       stat_miss_service_latency_sum_high,
    output logic [31:0]                                       stat_miss_service_latency_count,
    output logic [(17*32)-1:0]                                stat_merge_len_hist_flat,
    output logic [31:0]                                       stat_fifo_head_run_len,
    output logic [31:0]                                       stat_fifo_same_row_adjacent_count,
    output logic [31:0]                                       stat_fifo_reverse_x_adjacent_count,
    output logic [31:0]                                       stat_merge_opportunity_missed_count
);

    localparam int SRC_X_W = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int SRC_Y_W = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;
    localparam int SRC_CFG_W = $clog2(MAX_SRC_W+1);
    localparam int SRC_CFG_H = $clog2(MAX_SRC_H+1);
    localparam int DST_CFG_W = $clog2(MAX_DST_W+1);
    localparam int DST_CFG_H = $clog2(MAX_DST_H+1);
    localparam int FRAC_W = 16;
    localparam int TOUCH_W = 32;

    localparam int BASE_TILE_W = `SRC_TILE_CACHE_BASE_TILE_W;
    localparam int BASE_TILE_H = `SRC_TILE_CACHE_BASE_TILE_H;
    localparam int SET_NUM = `SRC_TILE_CACHE_SECTOR_SET_NUM;
    localparam int WAY_NUM = `SRC_TILE_CACHE_SECTOR_WAY_NUM;
    localparam int MERGE_MAX_X = `SRC_TILE_CACHE_MERGE_MAX_X;
    localparam int ANALYTIC_FIFO_DEPTH = `SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH;
    localparam int ANALYTIC_LEAD_PIXELS = `SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS;
    localparam int RUNTIME_LEAD_MAX = (ANALYTIC_LEAD_PIXELS > 512) ? ANALYTIC_LEAD_PIXELS : 512;
    localparam int ENABLE_MERGE_MIN = `SRC_TILE_CACHE_ENABLE_MERGE_MIN;
    localparam int MERGE_MIN_X = `SRC_TILE_CACHE_MERGE_MIN_X;
    localparam int FIFO_AGE_LIMIT = `SRC_TILE_CACHE_FIFO_AGE_LIMIT;
    localparam int ENABLE_PREFETCH_THROTTLE = `SRC_TILE_CACHE_ENABLE_PREFETCH_THROTTLE;
    localparam int PREFETCH_THROTTLE_CYCLES = `SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES;
    localparam int ENABLE_ROW_BUCKET_MERGE = `SRC_TILE_CACHE_ENABLE_ROW_BUCKET_MERGE;
    localparam int ROW_BUCKET_MIN_X = `SRC_TILE_CACHE_ROW_BUCKET_MIN_X;
    localparam int TILE_X_SHIFT = (BASE_TILE_W > 1) ? $clog2(BASE_TILE_W) : 0;
    localparam int TILE_Y_SHIFT = (BASE_TILE_H > 1) ? $clog2(BASE_TILE_H) : 0;

    function automatic bit is_power_of_two(input int value);
        begin
            is_power_of_two = (value > 0) && ((value & (value - 1)) == 0);
        end
    endfunction

    initial begin
        if (!is_power_of_two(BASE_TILE_W)) begin
            $error("SRC_TILE_CACHE_BASE_TILE_W must be a power of two, got %0d", BASE_TILE_W);
        end
        if (!is_power_of_two(BASE_TILE_H)) begin
            $error("SRC_TILE_CACHE_BASE_TILE_H must be a power of two, got %0d", BASE_TILE_H);
        end
        if (!is_power_of_two(SET_NUM)) begin
            $error("SRC_TILE_CACHE_SECTOR_SET_NUM must be a power of two, got %0d", SET_NUM);
        end
        if (WAY_NUM < 1) begin
            $error("SRC_TILE_CACHE_SECTOR_WAY_NUM must be >= 1, got %0d", WAY_NUM);
        end
        if (MERGE_MAX_X < 1) begin
            $error("SRC_TILE_CACHE_MERGE_MAX_X must be >= 1, got %0d", MERGE_MAX_X);
        end
        if ((ENABLE_ROW_BUCKET_MERGE != 0) && (ENABLE_ROW_BUCKET_MERGE != 1)) begin
            $error("SRC_TILE_CACHE_ENABLE_ROW_BUCKET_MERGE must be 0 or 1, got %0d",
                   ENABLE_ROW_BUCKET_MERGE);
        end
        if ((ENABLE_ROW_BUCKET_MERGE != 0) && (ROW_BUCKET_MIN_X < 2)) begin
            $error("SRC_TILE_CACHE_ROW_BUCKET_MIN_X must be >= 2, got %0d", ROW_BUCKET_MIN_X);
        end
        if ((ENABLE_ROW_BUCKET_MERGE != 0) && (ROW_BUCKET_MIN_X > MERGE_MAX_X)) begin
            $error("SRC_TILE_CACHE_ROW_BUCKET_MIN_X (%0d) must be <= MERGE_MAX_X (%0d)",
                   ROW_BUCKET_MIN_X, MERGE_MAX_X);
        end
        if (MERGE_MIN_X < 1) begin
            $error("SRC_TILE_CACHE_MERGE_MIN_X must be >= 1, got %0d", MERGE_MIN_X);
        end
        if (MERGE_MIN_X > MERGE_MAX_X) begin
            $error("SRC_TILE_CACHE_MERGE_MIN_X (%0d) must be <= MERGE_MAX_X (%0d)",
                   MERGE_MIN_X, MERGE_MAX_X);
        end
        if (FIFO_AGE_LIMIT < 0) begin
            $error("SRC_TILE_CACHE_FIFO_AGE_LIMIT must be >= 0, got %0d", FIFO_AGE_LIMIT);
        end
        if (PREFETCH_THROTTLE_CYCLES < 0) begin
            $error("SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES must be >= 0, got %0d", PREFETCH_THROTTLE_CYCLES);
        end
        if (ANALYTIC_FIFO_DEPTH < MERGE_MAX_X) begin
            $error("SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH (%0d) must be >= MERGE_MAX_X (%0d)",
                   ANALYTIC_FIFO_DEPTH, MERGE_MAX_X);
        end
    end

    localparam int SECTOR_COUNT_X = (MAX_SRC_W + BASE_TILE_W - 1) >> TILE_X_SHIFT;
    localparam int SECTOR_COUNT_Y = (MAX_SRC_H + BASE_TILE_H - 1) >> TILE_Y_SHIFT;
    localparam int SECTOR_X_W = (SECTOR_COUNT_X > 1) ? $clog2(SECTOR_COUNT_X) : 1;
    localparam int SECTOR_Y_W = (SECTOR_COUNT_Y > 1) ? $clog2(SECTOR_COUNT_Y) : 1;
    localparam int SECTOR_COUNT_X_W = (SECTOR_COUNT_X + 1 > 1) ? $clog2(SECTOR_COUNT_X + 1) : 1;
    localparam int SECTOR_COUNT_Y_W = (SECTOR_COUNT_Y + 1 > 1) ? $clog2(SECTOR_COUNT_Y + 1) : 1;
    localparam int BASE_COL_W = (BASE_TILE_W > 1) ? $clog2(BASE_TILE_W) : 1;
    localparam int BASE_ROW_W = (BASE_TILE_H > 1) ? $clog2(BASE_TILE_H) : 1;
    localparam int SET_W = (SET_NUM > 1) ? $clog2(SET_NUM) : 1;
    localparam int WAY_W = (WAY_NUM > 1) ? $clog2(WAY_NUM) : 1;
    localparam int RUN_LEN_W = (MERGE_MAX_X > 1) ? $clog2(MERGE_MAX_X+1) : 1;
    localparam int FIFO_COUNT_W = (ANALYTIC_FIFO_DEPTH > 1) ? $clog2(ANALYTIC_FIFO_DEPTH+1) : 1;
    localparam int STREAM_COL_W = (MERGE_MAX_X*BASE_TILE_W > 1) ? $clog2(MERGE_MAX_X*BASE_TILE_W+1) : 1;
    localparam int STREAM_ROW_W = (BASE_TILE_H > 1) ? $clog2(BASE_TILE_H+1) : 1;
    localparam int PIX_COUNT_W = (MAX_DST_W*MAX_DST_H + RUNTIME_LEAD_MAX + 1 > 1) ?
                                 $clog2(MAX_DST_W*MAX_DST_H + RUNTIME_LEAD_MAX + 1) : 1;
    localparam int FIFO_AGE_W = 16;
    localparam int THROTTLE_W = 16;
    localparam int SLOT_NUM = SET_NUM * WAY_NUM;
    localparam int SLOT_W = (SLOT_NUM > 1) ? $clog2(SLOT_NUM) : 1;
    localparam int SECTOR_PIXELS = BASE_TILE_W * BASE_TILE_H;
    localparam int SECTOR_MEM_W = SECTOR_PIXELS * PIXEL_W;

    typedef enum logic [2:0] {
        REPL_IDLE     = 3'd0,
        REPL_PRECHECK = 3'd1,
        REPL_PROTECT  = 3'd2,
        REPL_INVALID  = 3'd3,
        REPL_PREFETCH = 3'd4,
        REPL_OLDEST   = 3'd5,
        REPL_COMMIT   = 3'd6
    } repl_state_t;

    logic [SECTOR_MEM_W-1:0] sector_mem [0:SLOT_NUM-1];
    logic               sector_valid_reg [0:SLOT_NUM-1];
    logic               sector_prefetched_reg [0:SLOT_NUM-1];
    logic               sector_prefetch_fill_reg [0:SLOT_NUM-1];
    logic               sector_used_reg [0:SLOT_NUM-1];
    logic [SECTOR_X_W-1:0] sector_tag_x_reg [0:SLOT_NUM-1];
    logic [SECTOR_Y_W-1:0] sector_tag_y_reg [0:SLOT_NUM-1];
    logic [TOUCH_W-1:0]    sector_last_touch_reg [0:SLOT_NUM-1];
    logic [TOUCH_W-1:0]    touch_counter_reg;

    logic [ADDR_W-1:0]              cfg_src_base_addr_reg;
    logic [ADDR_W-1:0]              cfg_src_stride_reg;
    logic [SRC_CFG_W-1:0]           cfg_src_w_reg;
    logic [SRC_CFG_H-1:0]           cfg_src_h_reg;
    logic [DST_CFG_W-1:0]           cfg_dst_w_reg;
    logic [DST_CFG_H-1:0]           cfg_dst_h_reg;
    logic signed [31:0]             cfg_rot_sin_q16_reg;
    logic signed [31:0]             cfg_rot_cos_q16_reg;
    logic                           cfg_prefetch_enable_reg;
    logic [SECTOR_COUNT_X_W-1:0]    cfg_sector_count_x_reg;
    logic [SECTOR_COUNT_Y_W-1:0]    cfg_sector_count_y_reg;
    logic [SRC_X_W-1:0]             cfg_src_x_last_reg;
    logic [SRC_Y_W-1:0]             cfg_src_y_last_reg;
    logic signed [COORD_W-1:0]      cfg_src_x_max_q16_reg;
    logic signed [COORD_W-1:0]      cfg_src_y_max_q16_reg;
    logic                           cfg_geom_init_pending_reg;

    logic                           error_reg;
    logic                           sample_rsp_valid_reg;
    logic [PIXEL_W-1:0]             sample_p00_reg;
    logic [PIXEL_W-1:0]             sample_p01_reg;
    logic [PIXEL_W-1:0]             sample_p10_reg;
    logic [PIXEL_W-1:0]             sample_p11_reg;

    logic [31:0] stat_read_starts_reg;
    logic [31:0] stat_misses_reg;
    logic [31:0] stat_prefetch_starts_reg;
    logic [31:0] stat_prefetch_hits_reg;
    logic [31:0] stat_analytic_candidates_reg;
    logic [31:0] stat_analytic_duplicates_reg;
    logic [31:0] stat_analytic_blocked_reg;
    logic [31:0] stat_analytic_fills_reg;
    logic [31:0] stat_prefetch_evicted_unused_reg;
    logic [31:0] stat_total_cycles_reg;
    logic [31:0] stat_sample_req_count_reg;
    logic [31:0] stat_sample_stall_cycles_reg;
    logic [31:0] stat_normal_prefetch_fills_reg;
    logic [31:0] stat_fifo_max_occupancy_reg;
    logic [31:0] stat_merge_len_hist_reg [0:MERGE_MAX_X];
    logic [31:0] stat_read_busy_cycles_reg;
    logic [63:0] stat_read_bytes_total_reg;
    logic [31:0] stat_useful_source_sectors_reg;
    logic        stat_useful_source_pending_valid_reg;
    logic [31:0] stat_useful_source_pending_count_reg;
    logic [31:0] stat_replacement_fail_cycles_reg;
    logic [31:0] stat_miss_service_latency_min_reg;
    logic [31:0] stat_miss_service_latency_max_reg;
    logic [63:0] stat_miss_service_latency_sum_reg;
    logic [31:0] stat_miss_service_latency_count_reg;
    logic [31:0] stat_fifo_head_run_len_reg;
    logic [31:0] stat_fifo_same_row_adjacent_count_reg;
    logic [31:0] stat_fifo_reverse_x_adjacent_count_reg;
    logic [31:0] stat_merge_opportunity_missed_count_reg;
    logic        miss_service_active_reg;
    logic [31:0] miss_service_latency_reg;

    logic [SECTOR_X_W-1:0] fifo_tile_x_reg [0:ANALYTIC_FIFO_DEPTH-1];
    logic [SECTOR_Y_W-1:0] fifo_tile_y_reg [0:ANALYTIC_FIFO_DEPTH-1];
    logic [FIFO_COUNT_W-1:0] fifo_count_reg;
    logic [FIFO_AGE_W-1:0] fifo_head_age_reg;
    logic                    fifo_update_pending_reg;
    logic [FIFO_COUNT_W-1:0] fifo_compact_scan_idx_reg;
    logic [FIFO_COUNT_W-1:0] fifo_compact_write_idx_reg;
    logic [FIFO_COUNT_W-1:0] fifo_pop_pending_count_reg;
    logic                    fifo_delete_pending_valid_reg;
    logic [SECTOR_X_W-1:0]   fifo_delete_pending_tile_x_reg;
    logic [SECTOR_Y_W-1:0]   fifo_delete_pending_tile_y_reg;
    logic                    fifo_delete_req_valid_reg;
    logic [SECTOR_X_W-1:0]   fifo_delete_req_tile_x_reg;
    logic [SECTOR_Y_W-1:0]   fifo_delete_req_tile_y_reg;
    logic                    fifo_enqueue_pending_valid_reg;
    logic [SECTOR_X_W-1:0]   fifo_enqueue_pending_tile_x_reg;
    logic [SECTOR_Y_W-1:0]   fifo_enqueue_pending_tile_y_reg;
    logic [THROTTLE_W-1:0] miss_throttle_count_reg;

    logic                           fill_plan_valid_reg;
    logic [SECTOR_X_W-1:0]          fill_plan_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          fill_plan_tile_y_reg;
    logic [RUN_LEN_W-1:0]           fill_plan_run_len_reg;
    logic                           fill_plan_is_prefetch_reg;
    logic                           fill_plan_is_analytic_reg;
    logic [SET_W-1:0]               fill_plan_set_reg [0:MERGE_MAX_X-1];
    logic [WAY_W-1:0]               fill_plan_way_reg [0:MERGE_MAX_X-1];
    logic                           fill_plan_evict_unused_reg [0:MERGE_MAX_X-1];

    logic                           fill_active_reg;
    logic [SECTOR_X_W-1:0]          fill_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          fill_tile_y_reg;
    logic [RUN_LEN_W-1:0]           fill_run_len_reg;
    logic                           fill_is_prefetch_reg;
    logic                           fill_is_analytic_reg;
    logic [SET_W-1:0]               fill_set_reg [0:MERGE_MAX_X-1];
    logic [WAY_W-1:0]               fill_way_reg [0:MERGE_MAX_X-1];
    logic [31:0]                    fill_read_width_reg;
    logic [15:0]                    fill_read_rows_reg;
    logic [STREAM_COL_W-1:0]        fill_stream_col_reg;
    logic [STREAM_ROW_W-1:0]        fill_stream_row_reg;
    logic                           row_inflight_reg;
    logic                           read_issue_pending_reg;
    logic [ADDR_W-1:0]              read_addr_reg;
    logic [31:0]                    read_row_stride_reg;
    logic [31:0]                    read_byte_count_reg;
    logic [15:0]                    read_row_count_reg;

    logic                           last_sample_valid_reg;
    logic [SECTOR_X_W-1:0]          last_sample_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          last_sample_tile_y_reg;
    logic signed [1:0]              last_scan_dir_x_reg;
    logic signed [1:0]              last_scan_dir_y_reg;
    logic                           last_scan_dir_valid_reg;
    logic                           normal_prefetch_pending_reg;
    logic [SECTOR_X_W-1:0]          normal_prefetch_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          normal_prefetch_tile_y_reg;

    logic                           planner_active_reg;
    logic [DST_CFG_W-1:0]           planner_dst_x_reg;
    logic [DST_CFG_H-1:0]           planner_dst_y_reg;
    logic [1:0]                     planner_phase_reg;
    logic signed [COORD_W-1:0]      planner_row_x_reg;
    logic signed [COORD_W-1:0]      planner_row_y_reg;
    logic signed [COORD_W-1:0]      planner_cur_x_reg;
    logic signed [COORD_W-1:0]      planner_cur_y_reg;
    logic signed [COORD_W-1:0]      planner_step_x_x_reg;
    logic signed [COORD_W-1:0]      planner_step_y_x_reg;
    logic signed [COORD_W-1:0]      planner_step_x_y_reg;
    logic signed [COORD_W-1:0]      planner_step_y_y_reg;
    logic [PIX_COUNT_W-1:0]         planner_pixel_count_reg;
    logic [PIX_COUNT_W-1:0]         sample_accept_count_reg;
    logic                           planner_init_busy;

    logic [SECTOR_X_W-1:0] sample_tile_x [0:3];
    logic [SECTOR_Y_W-1:0] sample_tile_y [0:3];
    logic [BASE_COL_W-1:0] sample_col [0:3];
    logic [BASE_ROW_W-1:0] sample_row [0:3];
    logic [SET_W-1:0]      sample_set [0:3];
    logic [WAY_W-1:0]      sample_way [0:3];
    logic                  sample_hit [0:3];
    logic                  sample_hit_prefetched [0:3];
    logic                  all_sample_hit;
    logic                  any_sample_prefetch_hit;
    logic [1:0]            first_miss_idx;
    logic                  sample_miss_present;
    logic [SECTOR_X_W-1:0] sample_miss_tile_x;
    logic [SECTOR_Y_W-1:0] sample_miss_tile_y;
    logic                  sample_miss_pending_reg;
    logic [SECTOR_X_W-1:0] sample_miss_pending_tile_x_reg;
    logic [SECTOR_Y_W-1:0] sample_miss_pending_tile_y_reg;
    logic                  sample_miss_probe_valid_reg;
    logic [SECTOR_X_W-1:0] sample_miss_probe_tile_x_reg [0:3];
    logic [SECTOR_Y_W-1:0] sample_miss_probe_tile_y_reg [0:3];
    logic                  sample_miss_probe_present;
    logic [SECTOR_X_W-1:0] sample_miss_probe_tile_x;
    logic [SECTOR_Y_W-1:0] sample_miss_probe_tile_y;
    logic                  sample_miss_eval_valid_reg;
    logic                  sample_miss_eval_present_reg;
    logic [SECTOR_X_W-1:0] sample_miss_eval_tile_x_reg;
    logic [SECTOR_Y_W-1:0] sample_miss_eval_tile_y_reg;

    logic signed [COORD_W-1:0] planner_clamped_x_calc;
    logic signed [COORD_W-1:0] planner_clamped_y_calc;
    logic [SRC_X_W-1:0]        planner_src_x0_calc;
    logic [SRC_Y_W-1:0]        planner_src_y0_calc;
    logic [SRC_X_W-1:0]        planner_src_x1_calc;
    logic [SRC_Y_W-1:0]        planner_src_y1_calc;
    logic [SECTOR_X_W-1:0]     planner_candidate_tile_x;
    logic [SECTOR_Y_W-1:0]     planner_candidate_tile_y;
    logic                      planner_candidate_valid;
    logic                      planner_candidate_duplicate;
    logic                      planner_candidate_blocked;
    logic                      planner_candidate_enqueue;
    logic                      planner_advance_phase;
    logic                      planner_tile_pending_reg;
    logic [SECTOR_X_W-1:0]     planner_tile_x_reg;
    logic [SECTOR_Y_W-1:0]     planner_tile_y_reg;
    logic                      planner_tile_blocked_reported_reg;
    logic                      planner_lead_ok;
    logic                      planner_flush_ok;
    logic                      prefetch_throttle_active;
    logic [15:0]               runtime_lead_pixels_eff;
    logic [RUN_LEN_W-1:0]      runtime_merge_max_x_eff_clamped;
    logic [RUN_LEN_W-1:0]      runtime_merge_min_x_eff_clamped;
    logic [FIFO_COUNT_W-1:0]   runtime_fifo_depth_eff_clamped;
    logic [FIFO_AGE_W-1:0]     runtime_fifo_age_limit_eff;
    logic [THROTTLE_W-1:0]     runtime_prefetch_throttle_cycles_eff;
    logic                      runtime_merge_min_enable;
    logic                      runtime_prefetch_throttle_enable;
    logic [RUN_LEN_W-1:0]      fifo_head_run_len_calc;
    logic [31:0]               fifo_same_row_adjacent_count_calc;
    logic [31:0]               fifo_reverse_x_adjacent_count_calc;
    logic                      merge_opportunity_missed_calc;

    repl_state_t                    repl_state_reg;
    logic                           repl_capture_present;
    logic                           repl_capture_is_prefetch;
    logic                           repl_capture_is_analytic;
    logic [SECTOR_X_W-1:0]          repl_capture_tile_x [0:MERGE_MAX_X-1];
    logic [SECTOR_Y_W-1:0]          repl_capture_tile_y [0:MERGE_MAX_X-1];
    logic [RUN_LEN_W-1:0]           repl_capture_run_len;
    logic [FIFO_COUNT_W-1:0]        repl_capture_fifo_pop_count;
    logic                           repl_is_prefetch_reg;
    logic                           repl_is_analytic_reg;
    logic [SECTOR_X_W-1:0]          repl_tile_x_reg [0:MERGE_MAX_X-1];
    logic [SECTOR_Y_W-1:0]          repl_tile_y_reg [0:MERGE_MAX_X-1];
    logic [SET_W-1:0]               repl_set_reg [0:MERGE_MAX_X-1];
    logic [RUN_LEN_W-1:0]           repl_run_len_reg;
    logic [FIFO_COUNT_W-1:0]        repl_fifo_pop_count_reg;
    logic                           repl_lane_valid_reg [0:MERGE_MAX_X-1];
    logic                           repl_victim_found_reg [0:MERGE_MAX_X-1];
    logic [WAY_W-1:0]               repl_victim_way_reg [0:MERGE_MAX_X-1];
    logic                           repl_evict_unused_reg [0:MERGE_MAX_X-1];
    logic                           repl_protected_mask_reg [0:MERGE_MAX_X-1][0:WAY_NUM-1];
    logic                           repl_precheck_drop;
    logic                           repl_precheck_wait_fifo_update;
    logic [FIFO_COUNT_W-1:0]        repl_precheck_fifo_pop_count;
    logic                           repl_abort_speculative;

    logic                           fill_request_present;
    logic                           fill_request_is_prefetch;
    logic                           fill_request_is_analytic;
    logic [SECTOR_X_W-1:0]          fill_request_tile_x;
    logic [SECTOR_Y_W-1:0]          fill_request_tile_y;
    logic [RUN_LEN_W-1:0]           fill_request_run_len;
    logic [SET_W-1:0]               fill_request_set [0:MERGE_MAX_X-1];
    logic [WAY_W-1:0]               fill_request_way [0:MERGE_MAX_X-1];
    logic                           fill_request_evict_unused [0:MERGE_MAX_X-1];
    logic                           fill_req_valid_reg;
    logic                           fill_req_is_prefetch_reg;
    logic                           fill_req_is_analytic_reg;
    logic [SECTOR_X_W-1:0]          fill_req_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          fill_req_tile_y_reg;
    logic [RUN_LEN_W-1:0]           fill_req_run_len_reg;
    logic [SET_W-1:0]               fill_req_set_reg [0:MERGE_MAX_X-1];
    logic [WAY_W-1:0]               fill_req_way_reg [0:MERGE_MAX_X-1];
    logic                           fill_req_evict_unused_reg [0:MERGE_MAX_X-1];
    logic [31:0]                    useful_sector_count_calc;
    logic [FIFO_COUNT_W-1:0]        fifo_pop_count;
    logic                           scheduler_analytic_blocked;
    logic                           scheduler_replacement_fail;
    logic                           normal_prefetch_drop;
    logic                           stat_scheduler_analytic_blocked_pulse_reg;
    logic                           stat_replacement_fail_pulse_reg;

    logic [STREAM_ROW_W-1:0]        fill_row_idx_reg;
    logic [STREAM_COL_W-1:0]        fill_col_idx_reg;
    logic                           read_start_reg;
    logic                           hit00;
    logic                           hit01;
    logic                           hit10;
    logic                           hit11;
    logic                           miss_present;
    logic [SECTOR_X_W-1:0]          miss_tile_x;
    logic [SECTOR_Y_W-1:0]          miss_tile_y;
    logic                           sample_decode_valid_reg;
    logic                           sample_issue_valid_reg;
    logic                           prefetch_pending0_valid_reg;
    logic                           prefetch_pending1_valid_reg;
    logic                           prefetch_pending2_valid_reg;
    logic                           prefetch_dom0_valid_reg;
    logic                           prefetch_dom1_valid_reg;
    logic [SECTOR_X_W-1:0]          prefetch_dom0_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_dom0_tile_y_reg;
    logic [SECTOR_X_W-1:0]          prefetch_dom1_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_dom1_tile_y_reg;
    logic                           prefetch_geom_valid_reg;
    logic                           prefetch_eval_valid_reg;
    logic                           prefetch_eval_dual_axis_reg;
    logic                           prefetch_eval_dual_frontier_reg;
    logic                           prefetch_eval_aggressive_reg;
    logic                           hold_prefetched_hit_now;
    logic                           prefetch_primary_usable;
    logic                           prefetch_secondary_usable;
    logic                           prefetch_tertiary_usable;
    logic                           prefetch_eval_primary_valid_reg;
    logic                           prefetch_eval_secondary_valid_reg;
    logic                           prefetch_eval_tertiary_valid_reg;
    logic [SECTOR_X_W-1:0]          prefetch_eval_primary_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_eval_primary_tile_y_reg;
    logic [SECTOR_X_W-1:0]          prefetch_eval_secondary_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_eval_secondary_tile_y_reg;
    logic [SECTOR_X_W-1:0]          prefetch_eval_tertiary_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_eval_tertiary_tile_y_reg;
    logic [SECTOR_X_W-1:0]          prefetch_eval_req_tile_x00_reg;
    logic [SECTOR_X_W-1:0]          prefetch_eval_req_tile_x01_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_eval_req_tile_y00_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_eval_req_tile_y10_reg;
    logic                           prefetch_select_valid_reg;
    logic                           prefetch_select2_valid_reg;
    logic                           prefetch_select_valid_next;
    logic                           prefetch_select2_valid_next;
    logic                           prefetch_geom_scheduler_x_valid_reg;
    logic                           prefetch_geom_scheduler_y_valid_reg;
    logic                           prefetch_geom_scheduler_diag_valid_reg;
    logic [SECTOR_X_W-1:0]          prefetch_geom_scheduler_x_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_geom_scheduler_x_tile_y_reg;
    logic [SECTOR_X_W-1:0]          prefetch_geom_scheduler_y_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_geom_scheduler_y_tile_y_reg;
    logic [SECTOR_X_W-1:0]          prefetch_geom_scheduler_diag_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_geom_scheduler_diag_tile_y_reg;
    logic                           prefetch_geom_primary_valid_reg;
    logic                           prefetch_geom_secondary_valid_reg;
    logic                           prefetch_geom_tertiary_valid_reg;
    logic [SECTOR_X_W-1:0]          prefetch_geom_primary_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_geom_primary_tile_y_reg;
    logic [SECTOR_X_W-1:0]          prefetch_geom_secondary_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_geom_secondary_tile_y_reg;
    logic [SECTOR_X_W-1:0]          prefetch_geom_tertiary_tile_x_reg;
    logic [SECTOR_Y_W-1:0]          prefetch_geom_tertiary_tile_y_reg;
    logic [WAY_W-1:0]               prefetch_secondary_hit_slot_unused;
    logic [WAY_W-1:0]               prefetch_tertiary_hit_slot_unused;

    function automatic [SET_W-1:0] sector_set(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        int b;
        logic [SET_W-1:0] sx;
        logic [SET_W-1:0] sy;
        begin
            sx = '0;
            sy = '0;
            for (b = 0; b < SET_W; b = b + 1) begin
                if (b < SECTOR_X_W) begin
                    sx[b] = tile_x[b];
                end
                if (b < SECTOR_Y_W) begin
                    sy[b] = tile_y[b];
                end
            end
            sector_set = sx ^ sy;
        end
    endfunction

    function automatic [SLOT_W-1:0] sector_slot(
        input logic [SET_W-1:0] set_idx,
        input logic [WAY_W-1:0] way_idx
    );
        begin
            sector_slot = SLOT_W'(int'(set_idx) * WAY_NUM + int'(way_idx));
        end
    endfunction

    function automatic int sector_pixel_lsb(
        input logic [BASE_ROW_W-1:0] row_idx,
        input logic [BASE_COL_W-1:0] col_idx
    );
        begin
            sector_pixel_lsb = ((int'(row_idx) * BASE_TILE_W) + int'(col_idx)) * PIXEL_W;
        end
    endfunction

    function automatic logic coord_equal(
        input logic [SECTOR_X_W-1:0] ax,
        input logic [SECTOR_Y_W-1:0] ay,
        input logic [SECTOR_X_W-1:0] bx,
        input logic [SECTOR_Y_W-1:0] by
    );
        begin
            coord_equal = (ax == bx) && (ay == by);
        end
    endfunction

    function automatic logic coord_valid(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        begin
            coord_valid = (tile_x < cfg_sector_count_x_reg) && (tile_y < cfg_sector_count_y_reg);
        end
    endfunction

    function automatic logic cache_lookup(
        input  logic [SECTOR_X_W-1:0] tile_x,
        input  logic [SECTOR_Y_W-1:0] tile_y,
        output logic [SET_W-1:0]      set_sel,
        output logic [WAY_W-1:0]      way_sel
    );
        int w;
        logic found;
        logic [SLOT_W-1:0] slot_idx;
        begin
            set_sel = sector_set(tile_x, tile_y);
            way_sel = '0;
            found = 1'b0;
            for (w = 0; w < WAY_NUM; w = w + 1) begin
                slot_idx = sector_slot(set_sel, WAY_W'(w));
                if (!found &&
                    sector_valid_reg[slot_idx] &&
                    (sector_tag_x_reg[slot_idx] == tile_x) &&
                    (sector_tag_y_reg[slot_idx] == tile_y)) begin
                    found = 1'b1;
                    way_sel = WAY_W'(w);
                end
            end
            cache_lookup = found;
        end
    endfunction

    function automatic logic coord_in_fifo(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        int i;
        logic found;
        begin
            found = 1'b0;
            for (i = 0; i < ANALYTIC_FIFO_DEPTH; i = i + 1) begin
                if ((i < fifo_count_reg) && coord_equal(fifo_tile_x_reg[i], fifo_tile_y_reg[i], tile_x, tile_y)) begin
                    found = 1'b1;
                end
            end
            coord_in_fifo = found;
        end
    endfunction

    function automatic logic coord_in_fill_active(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        begin
            coord_in_fill_active = fill_active_reg &&
                                   (tile_y == fill_tile_y_reg) &&
                                   (tile_x >= fill_tile_x_reg) &&
                                   (tile_x < (fill_tile_x_reg + SECTOR_X_W'(fill_run_len_reg)));
        end
    endfunction

    function automatic logic coord_in_fill_plan(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        begin
            coord_in_fill_plan = fill_plan_valid_reg &&
                                 (tile_y == fill_plan_tile_y_reg) &&
                                 (tile_x >= fill_plan_tile_x_reg) &&
                                 (tile_x < (fill_plan_tile_x_reg + SECTOR_X_W'(fill_plan_run_len_reg)));
        end
    endfunction

    function automatic logic coord_in_fill_req(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        begin
            coord_in_fill_req = fill_req_valid_reg &&
                                (tile_y == fill_req_tile_y_reg) &&
                                (tile_x >= fill_req_tile_x_reg) &&
                                (tile_x < (fill_req_tile_x_reg + SECTOR_X_W'(fill_req_run_len_reg)));
        end
    endfunction

    function automatic logic coord_pending(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        begin
            coord_pending = coord_in_fill_active(tile_x, tile_y) ||
                            coord_in_fill_plan(tile_x, tile_y) ||
                            coord_in_fill_req(tile_x, tile_y);
        end
    endfunction

    function automatic logic protected_coord(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        logic hit_sample;
        logic hit_req;
        logic hit_active;
        logic hit_plan;
        begin
            hit_sample = sample_req_valid &&
                (coord_equal(sample_tile_x[0], sample_tile_y[0], tile_x, tile_y) ||
                 coord_equal(sample_tile_x[1], sample_tile_y[1], tile_x, tile_y) ||
                 coord_equal(sample_tile_x[2], sample_tile_y[2], tile_x, tile_y) ||
                 coord_equal(sample_tile_x[3], sample_tile_y[3], tile_x, tile_y));
            hit_req = fill_req_valid_reg &&
                      (tile_y == fill_req_tile_y_reg) &&
                      (tile_x >= fill_req_tile_x_reg) &&
                      (tile_x < (fill_req_tile_x_reg + SECTOR_X_W'(fill_req_run_len_reg)));
            hit_active = fill_active_reg &&
                         (tile_y == fill_tile_y_reg) &&
                         (tile_x >= fill_tile_x_reg) &&
                         (tile_x < (fill_tile_x_reg + SECTOR_X_W'(fill_run_len_reg)));
            hit_plan = fill_plan_valid_reg &&
                       (tile_y == fill_plan_tile_y_reg) &&
                       (tile_x >= fill_plan_tile_x_reg) &&
                       (tile_x < (fill_plan_tile_x_reg + SECTOR_X_W'(fill_plan_run_len_reg)));
            protected_coord = hit_sample || hit_req || hit_active || hit_plan;
        end
    endfunction

    function automatic logic choose_way(
        input  logic [SECTOR_X_W-1:0] tile_x,
        input  logic [SECTOR_Y_W-1:0] tile_y,
        output logic [SET_W-1:0]      set_sel,
        output logic [WAY_W-1:0]      way_sel,
        output logic                  evict_unused
    );
        int w;
        logic found;
        logic [TOUCH_W-1:0] oldest_touch;
        logic [SET_W-1:0] set_idx;
        logic [SLOT_W-1:0] slot_idx;
        begin
            set_idx = sector_set(tile_x, tile_y);
            set_sel = set_idx;
            way_sel = '0;
            evict_unused = 1'b0;
            found = 1'b0;

            for (w = 0; w < WAY_NUM; w = w + 1) begin
                slot_idx = sector_slot(set_idx, WAY_W'(w));
                if (!found && !sector_valid_reg[slot_idx]) begin
                    found = 1'b1;
                    way_sel = WAY_W'(w);
                end
            end

            for (w = 0; w < WAY_NUM; w = w + 1) begin
                slot_idx = sector_slot(set_idx, WAY_W'(w));
                if (!found &&
                    !protected_coord(sector_tag_x_reg[slot_idx], sector_tag_y_reg[slot_idx]) &&
                    sector_prefetch_fill_reg[slot_idx] &&
                    sector_used_reg[slot_idx]) begin
                    found = 1'b1;
                    way_sel = WAY_W'(w);
                end
            end

            oldest_touch = {TOUCH_W{1'b1}};
            for (w = 0; w < WAY_NUM; w = w + 1) begin
                slot_idx = sector_slot(set_idx, WAY_W'(w));
                if (!found &&
                    !protected_coord(sector_tag_x_reg[slot_idx], sector_tag_y_reg[slot_idx]) &&
                    (sector_last_touch_reg[slot_idx] <= oldest_touch)) begin
                    oldest_touch = sector_last_touch_reg[slot_idx];
                    way_sel = WAY_W'(w);
                end
            end
            if (!found && (oldest_touch != {TOUCH_W{1'b1}})) begin
                found = 1'b1;
            end

            slot_idx = sector_slot(set_idx, way_sel);
            if (found && sector_valid_reg[slot_idx] &&
                sector_prefetch_fill_reg[slot_idx] &&
                !sector_used_reg[slot_idx]) begin
                evict_unused = 1'b1;
            end
            choose_way = found;
        end
    endfunction

    function automatic logic tile_is_current_request(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        begin
            tile_is_current_request = sample_req_valid &&
                (coord_equal(sample_tile_x[0], sample_tile_y[0], tile_x, tile_y) ||
                 coord_equal(sample_tile_x[1], sample_tile_y[1], tile_x, tile_y) ||
                 coord_equal(sample_tile_x[2], sample_tile_y[2], tile_x, tile_y) ||
                 coord_equal(sample_tile_x[3], sample_tile_y[3], tile_x, tile_y));
        end
    endfunction

    function automatic logic hit_tile(
        input  logic [SECTOR_X_W-1:0] tile_x,
        input  logic [SECTOR_Y_W-1:0] tile_y,
        output logic [WAY_W-1:0]      hit_slot
    );
        logic [SET_W-1:0] set_unused;
        begin
            hit_tile = cache_lookup(tile_x, tile_y, set_unused, hit_slot);
        end
    endfunction

    function automatic logic tile_is_pending(
        input logic [SECTOR_X_W-1:0] tile_x,
        input logic [SECTOR_Y_W-1:0] tile_y
    );
        begin
            tile_is_pending = coord_pending(tile_x, tile_y) || coord_in_fifo(tile_x, tile_y);
        end
    endfunction

    assign read_start = read_issue_pending_reg;
    assign read_addr = read_addr_reg;
    assign read_row_stride = read_row_stride_reg;
    assign read_byte_count = read_byte_count_reg;
    assign read_row_count = read_row_count_reg;
    assign in_ready = fill_active_reg && row_inflight_reg;

    assign sample_rsp_valid = sample_rsp_valid_reg;
    assign sample_p00 = sample_p00_reg;
    assign sample_p01 = sample_p01_reg;
    assign sample_p10 = sample_p10_reg;
    assign sample_p11 = sample_p11_reg;
    assign error = error_reg;

    assign stat_read_starts = stat_read_starts_reg;
    assign stat_misses = stat_misses_reg;
    assign stat_prefetch_starts = stat_prefetch_starts_reg;
    assign stat_prefetch_hits = stat_prefetch_hits_reg;
    assign stat_analytic_candidates = stat_analytic_candidates_reg;
    assign stat_analytic_duplicates = stat_analytic_duplicates_reg;
    assign stat_analytic_blocked = stat_analytic_blocked_reg;
    assign stat_analytic_fills = stat_analytic_fills_reg;
    assign stat_prefetch_evicted_unused = stat_prefetch_evicted_unused_reg;
    assign stat_total_cycles = stat_total_cycles_reg;
    assign stat_sample_req_count = stat_sample_req_count_reg;
    assign stat_sample_accept_count = sample_accept_count_reg;
    assign stat_sample_stall_cycles = stat_sample_stall_cycles_reg;
    assign stat_normal_prefetch_fills = stat_normal_prefetch_fills_reg;
    assign stat_fifo_max_occupancy = stat_fifo_max_occupancy_reg;
    assign stat_read_busy_cycles = stat_read_busy_cycles_reg;
    assign stat_read_bytes_total_low = stat_read_bytes_total_reg[31:0];
    assign stat_read_bytes_total_high = stat_read_bytes_total_reg[63:32];
    assign stat_useful_source_sectors = stat_useful_source_sectors_reg;
    assign stat_replacement_fail_cycles = stat_replacement_fail_cycles_reg;
    assign stat_miss_service_latency_min = (stat_miss_service_latency_count_reg == '0) ? '0 :
                                           stat_miss_service_latency_min_reg;
    assign stat_miss_service_latency_max = stat_miss_service_latency_max_reg;
    assign stat_miss_service_latency_sum_low = stat_miss_service_latency_sum_reg[31:0];
    assign stat_miss_service_latency_sum_high = stat_miss_service_latency_sum_reg[63:32];
    assign stat_miss_service_latency_count = stat_miss_service_latency_count_reg;
    assign stat_fifo_head_run_len = stat_fifo_head_run_len_reg;
    assign stat_fifo_same_row_adjacent_count = stat_fifo_same_row_adjacent_count_reg;
    assign stat_fifo_reverse_x_adjacent_count = stat_fifo_reverse_x_adjacent_count_reg;
    assign stat_merge_opportunity_missed_count = stat_merge_opportunity_missed_count_reg;

    genvar hist_g;
    generate
        for (hist_g = 0; hist_g < 17; hist_g = hist_g + 1) begin : gen_stat_merge_hist_flat
            if (hist_g <= MERGE_MAX_X) begin : gen_hist_used
                assign stat_merge_len_hist_flat[hist_g*32 +: 32] = stat_merge_len_hist_reg[hist_g];
            end else begin : gen_hist_unused
                assign stat_merge_len_hist_flat[hist_g*32 +: 32] = '0;
            end
        end
    endgenerate

    assign fill_row_idx_reg = fill_stream_row_reg;
    assign fill_col_idx_reg = fill_stream_col_reg;
    assign read_start_reg = read_issue_pending_reg;
    assign hit00 = sample_hit[0];
    assign hit01 = sample_hit[1];
    assign hit10 = sample_hit[2];
    assign hit11 = sample_hit[3];
    assign miss_present = sample_req_valid && sample_miss_present;
    assign miss_tile_x = sample_miss_tile_x;
    assign miss_tile_y = sample_miss_tile_y;
    assign sample_decode_valid_reg = 1'b0;
    assign sample_issue_valid_reg = 1'b0;
    assign prefetch_pending0_valid_reg = (fifo_count_reg > 0);
    assign prefetch_pending1_valid_reg = (fifo_count_reg > 1);
    assign prefetch_pending2_valid_reg = (fifo_count_reg > 2);
    assign prefetch_dom0_valid_reg = 1'b0;
    assign prefetch_dom1_valid_reg = 1'b0;
    assign prefetch_dom0_tile_x_reg = (fifo_count_reg > 0) ? fifo_tile_x_reg[0] : '0;
    assign prefetch_dom0_tile_y_reg = (fifo_count_reg > 0) ? fifo_tile_y_reg[0] : '0;
    assign prefetch_dom1_tile_x_reg = (fifo_count_reg > 1) ? fifo_tile_x_reg[1] : '0;
    assign prefetch_dom1_tile_y_reg = (fifo_count_reg > 1) ? fifo_tile_y_reg[1] : '0;
    assign prefetch_geom_valid_reg = planner_candidate_valid;
    assign prefetch_eval_valid_reg = planner_candidate_valid;
    assign prefetch_eval_dual_axis_reg = 1'b0;
    assign prefetch_eval_dual_frontier_reg = 1'b0;
    assign prefetch_eval_aggressive_reg = 1'b1;
    assign hold_prefetched_hit_now = any_sample_prefetch_hit;
    assign prefetch_primary_usable = planner_candidate_enqueue;
    assign prefetch_secondary_usable = 1'b0;
    assign prefetch_tertiary_usable = 1'b0;
    assign prefetch_eval_primary_valid_reg = planner_candidate_valid;
    assign prefetch_eval_secondary_valid_reg = 1'b0;
    assign prefetch_eval_tertiary_valid_reg = 1'b0;
    assign prefetch_eval_primary_tile_x_reg = planner_candidate_tile_x;
    assign prefetch_eval_primary_tile_y_reg = planner_candidate_tile_y;
    assign prefetch_eval_secondary_tile_x_reg = '0;
    assign prefetch_eval_secondary_tile_y_reg = '0;
    assign prefetch_eval_tertiary_tile_x_reg = '0;
    assign prefetch_eval_tertiary_tile_y_reg = '0;
    assign prefetch_eval_req_tile_x00_reg = sample_tile_x[0];
    assign prefetch_eval_req_tile_x01_reg = sample_tile_x[1];
    assign prefetch_eval_req_tile_y00_reg = sample_tile_y[0];
    assign prefetch_eval_req_tile_y10_reg = sample_tile_y[2];
    assign prefetch_select_valid_reg = fill_request_present && fill_request_is_prefetch;
    assign prefetch_select2_valid_reg = 1'b0;
    assign prefetch_select_valid_next = fill_request_present && fill_request_is_prefetch;
    assign prefetch_select2_valid_next = 1'b0;
    assign prefetch_geom_scheduler_x_valid_reg = (fifo_count_reg > 0);
    assign prefetch_geom_scheduler_y_valid_reg = (fifo_count_reg > 1);
    assign prefetch_geom_scheduler_diag_valid_reg = 1'b0;
    assign prefetch_geom_scheduler_x_tile_x_reg = (fifo_count_reg > 0) ? fifo_tile_x_reg[0] : '0;
    assign prefetch_geom_scheduler_x_tile_y_reg = (fifo_count_reg > 0) ? fifo_tile_y_reg[0] : '0;
    assign prefetch_geom_scheduler_y_tile_x_reg = (fifo_count_reg > 1) ? fifo_tile_x_reg[1] : '0;
    assign prefetch_geom_scheduler_y_tile_y_reg = (fifo_count_reg > 1) ? fifo_tile_y_reg[1] : '0;
    assign prefetch_geom_scheduler_diag_tile_x_reg = '0;
    assign prefetch_geom_scheduler_diag_tile_y_reg = '0;
    assign prefetch_geom_primary_valid_reg = planner_candidate_valid;
    assign prefetch_geom_secondary_valid_reg = 1'b0;
    assign prefetch_geom_tertiary_valid_reg = 1'b0;
    assign prefetch_geom_primary_tile_x_reg = planner_candidate_tile_x;
    assign prefetch_geom_primary_tile_y_reg = planner_candidate_tile_y;
    assign prefetch_geom_secondary_tile_x_reg = '0;
    assign prefetch_geom_secondary_tile_y_reg = '0;
    assign prefetch_geom_tertiary_tile_x_reg = '0;
    assign prefetch_geom_tertiary_tile_y_reg = '0;
    assign prefetch_secondary_hit_slot_unused = '0;
    assign prefetch_tertiary_hit_slot_unused = '0;

    assign planner_init_busy = cfg_geom_init_pending_reg && !geom_ready && !geom_error;

    assign busy = cfg_geom_init_pending_reg ||
                  planner_init_busy ||
                  fill_active_reg ||
                  row_inflight_reg ||
                  read_busy ||
                  read_issue_pending_reg ||
                  (repl_state_reg != REPL_IDLE) ||
                  fill_req_valid_reg ||
                  fill_plan_valid_reg ||
                  sample_decode_valid_reg ||
                  sample_issue_valid_reg ||
                  sample_rsp_valid_reg ||
                  sample_miss_probe_valid_reg ||
                  sample_miss_eval_valid_reg ||
                  sample_miss_pending_reg ||
                  planner_active_reg ||
                  prefetch_pending0_valid_reg ||
                  prefetch_pending1_valid_reg ||
                  prefetch_pending2_valid_reg ||
                  fifo_update_pending_reg ||
                  fifo_delete_req_valid_reg ||
                  (fifo_count_reg != '0);

    always_comb begin
        runtime_lead_pixels_eff = runtime_lead_pixels;
        if (runtime_lead_pixels_eff > 16'(RUNTIME_LEAD_MAX)) begin
            runtime_lead_pixels_eff = 16'(RUNTIME_LEAD_MAX);
        end

        if (runtime_merge_max_x_eff == 8'd0) begin
            runtime_merge_max_x_eff_clamped = RUN_LEN_W'(1);
        end else if (runtime_merge_max_x_eff > 8'(MERGE_MAX_X)) begin
            runtime_merge_max_x_eff_clamped = RUN_LEN_W'(MERGE_MAX_X);
        end else begin
            runtime_merge_max_x_eff_clamped = RUN_LEN_W'(runtime_merge_max_x_eff);
        end

        if (runtime_merge_min_x == 8'd0) begin
            runtime_merge_min_x_eff_clamped = RUN_LEN_W'(1);
        end else if (runtime_merge_min_x > 8'(MERGE_MAX_X)) begin
            runtime_merge_min_x_eff_clamped = RUN_LEN_W'(MERGE_MAX_X);
        end else if (runtime_merge_min_x > runtime_merge_max_x_eff) begin
            runtime_merge_min_x_eff_clamped = runtime_merge_max_x_eff_clamped;
        end else begin
            runtime_merge_min_x_eff_clamped = RUN_LEN_W'(runtime_merge_min_x);
        end

        if (runtime_fifo_depth_eff == 16'd0) begin
            runtime_fifo_depth_eff_clamped = FIFO_COUNT_W'(1);
        end else if (runtime_fifo_depth_eff > 16'(ANALYTIC_FIFO_DEPTH)) begin
            runtime_fifo_depth_eff_clamped = FIFO_COUNT_W'(ANALYTIC_FIFO_DEPTH);
        end else begin
            runtime_fifo_depth_eff_clamped = FIFO_COUNT_W'(runtime_fifo_depth_eff);
        end

        runtime_fifo_age_limit_eff = runtime_fifo_age_limit;
        runtime_prefetch_throttle_cycles_eff = runtime_prefetch_throttle_cycles;
        runtime_merge_min_enable = runtime_scheduler_policy[0];
        runtime_prefetch_throttle_enable = runtime_scheduler_policy[1];
    end

    always_comb begin
        int i;
        logic [SET_W-1:0] unused_set;
        logic [WAY_W-1:0] unused_way;

        sample_tile_x[0] = SECTOR_X_W'(sample_x0 >> TILE_X_SHIFT);
        sample_tile_y[0] = SECTOR_Y_W'(sample_y0 >> TILE_Y_SHIFT);
        sample_tile_x[1] = SECTOR_X_W'(sample_x1 >> TILE_X_SHIFT);
        sample_tile_y[1] = SECTOR_Y_W'(sample_y0 >> TILE_Y_SHIFT);
        sample_tile_x[2] = SECTOR_X_W'(sample_x0 >> TILE_X_SHIFT);
        sample_tile_y[2] = SECTOR_Y_W'(sample_y1 >> TILE_Y_SHIFT);
        sample_tile_x[3] = SECTOR_X_W'(sample_x1 >> TILE_X_SHIFT);
        sample_tile_y[3] = SECTOR_Y_W'(sample_y1 >> TILE_Y_SHIFT);

        sample_col[0] = BASE_COL_W'(sample_x0 & (BASE_TILE_W - 1));
        sample_row[0] = BASE_ROW_W'(sample_y0 & (BASE_TILE_H - 1));
        sample_col[1] = BASE_COL_W'(sample_x1 & (BASE_TILE_W - 1));
        sample_row[1] = BASE_ROW_W'(sample_y0 & (BASE_TILE_H - 1));
        sample_col[2] = BASE_COL_W'(sample_x0 & (BASE_TILE_W - 1));
        sample_row[2] = BASE_ROW_W'(sample_y1 & (BASE_TILE_H - 1));
        sample_col[3] = BASE_COL_W'(sample_x1 & (BASE_TILE_W - 1));
        sample_row[3] = BASE_ROW_W'(sample_y1 & (BASE_TILE_H - 1));

        all_sample_hit = 1'b1;
        any_sample_prefetch_hit = 1'b0;
        sample_miss_present = 1'b0;
        first_miss_idx = '0;
        sample_miss_tile_x = sample_tile_x[0];
        sample_miss_tile_y = sample_tile_y[0];

        for (i = 0; i < 4; i = i + 1) begin
            sample_hit[i] = cache_lookup(sample_tile_x[i], sample_tile_y[i], sample_set[i], sample_way[i]);
            sample_hit_prefetched[i] = sample_hit[i] && sector_prefetched_reg[sector_slot(sample_set[i], sample_way[i])];
            if (!sample_hit[i]) begin
                all_sample_hit = 1'b0;
                if (!sample_miss_present) begin
                    sample_miss_present = 1'b1;
                    first_miss_idx = i[1:0];
                    sample_miss_tile_x = sample_tile_x[i];
                    sample_miss_tile_y = sample_tile_y[i];
                end
            end
            if (sample_hit_prefetched[i]) begin
                any_sample_prefetch_hit = 1'b1;
            end
        end

        unused_set = '0;
        unused_way = '0;
    end

    always_comb begin
        int i;
        logic [SET_W-1:0] probe_lookup_set;
        logic [WAY_W-1:0] probe_lookup_way;

        sample_miss_probe_present = 1'b0;
        sample_miss_probe_tile_x = sample_miss_probe_tile_x_reg[0];
        sample_miss_probe_tile_y = sample_miss_probe_tile_y_reg[0];
        for (i = 0; i < 4; i = i + 1) begin
            if (!sample_miss_probe_present &&
                !cache_lookup(sample_miss_probe_tile_x_reg[i],
                              sample_miss_probe_tile_y_reg[i],
                              probe_lookup_set,
                              probe_lookup_way)) begin
                sample_miss_probe_present = 1'b1;
                sample_miss_probe_tile_x = sample_miss_probe_tile_x_reg[i];
                sample_miss_probe_tile_y = sample_miss_probe_tile_y_reg[i];
            end
        end
    end

    assign sample_req_ready = sample_req_valid && all_sample_hit && !sample_rsp_valid_reg;
    always_comb begin
        logic [SET_W-1:0] lookup_set;
        logic [WAY_W-1:0] lookup_way;

        planner_clamped_x_calc = planner_cur_x_reg;
        planner_clamped_y_calc = planner_cur_y_reg;
        if (planner_cur_x_reg < 0) begin
            planner_clamped_x_calc = '0;
        end else if (planner_cur_x_reg > cfg_src_x_max_q16_reg) begin
            planner_clamped_x_calc = cfg_src_x_max_q16_reg;
        end
        if (planner_cur_y_reg < 0) begin
            planner_clamped_y_calc = '0;
        end else if (planner_cur_y_reg > cfg_src_y_max_q16_reg) begin
            planner_clamped_y_calc = cfg_src_y_max_q16_reg;
        end

        planner_src_x0_calc = SRC_X_W'(planner_clamped_x_calc >>> FRAC_W);
        planner_src_y0_calc = SRC_Y_W'(planner_clamped_y_calc >>> FRAC_W);
        planner_src_x1_calc = (planner_src_x0_calc >= cfg_src_x_last_reg) ? cfg_src_x_last_reg : (planner_src_x0_calc + 1'b1);
        planner_src_y1_calc = (planner_src_y0_calc >= cfg_src_y_last_reg) ? cfg_src_y_last_reg : (planner_src_y0_calc + 1'b1);

        case (planner_phase_reg)
            2'd0: begin
                planner_candidate_tile_x = SECTOR_X_W'(planner_src_x0_calc >> TILE_X_SHIFT);
                planner_candidate_tile_y = SECTOR_Y_W'(planner_src_y0_calc >> TILE_Y_SHIFT);
            end
            2'd1: begin
                planner_candidate_tile_x = SECTOR_X_W'(planner_src_x1_calc >> TILE_X_SHIFT);
                planner_candidate_tile_y = SECTOR_Y_W'(planner_src_y0_calc >> TILE_Y_SHIFT);
            end
            2'd2: begin
                planner_candidate_tile_x = SECTOR_X_W'(planner_src_x0_calc >> TILE_X_SHIFT);
                planner_candidate_tile_y = SECTOR_Y_W'(planner_src_y1_calc >> TILE_Y_SHIFT);
            end
            default: begin
                planner_candidate_tile_x = SECTOR_X_W'(planner_src_x1_calc >> TILE_X_SHIFT);
                planner_candidate_tile_y = SECTOR_Y_W'(planner_src_y1_calc >> TILE_Y_SHIFT);
            end
        endcase

        planner_lead_ok = (planner_pixel_count_reg < (sample_accept_count_reg + PIX_COUNT_W'(runtime_lead_pixels_eff)));
        planner_flush_ok = !planner_active_reg;
        prefetch_throttle_active = runtime_prefetch_throttle_enable &&
                                   ((sample_req_valid && sample_miss_present) ||
                                    (miss_throttle_count_reg != '0));
        planner_candidate_valid = planner_active_reg &&
                                  !planner_init_busy &&
                                  !planner_tile_pending_reg &&
                                  cfg_prefetch_enable_reg &&
                                  planner_lead_ok;
        planner_candidate_duplicate = 1'b0;
        if (planner_tile_pending_reg) begin
            planner_candidate_duplicate =
                cache_lookup(planner_tile_x_reg, planner_tile_y_reg, lookup_set, lookup_way) ||
                coord_in_fifo(planner_tile_x_reg, planner_tile_y_reg) ||
                coord_pending(planner_tile_x_reg, planner_tile_y_reg);
        end
        planner_candidate_blocked = planner_tile_pending_reg &&
                                    !planner_candidate_duplicate &&
                                    ((fifo_count_reg >= runtime_fifo_depth_eff_clamped) ||
                                     fifo_update_pending_reg);
        planner_candidate_enqueue = planner_tile_pending_reg &&
                                    !planner_candidate_duplicate &&
                                    !planner_candidate_blocked;
        planner_advance_phase = planner_candidate_valid;
    end

    always_comb begin
        int k;
        int q;
        logic merge_keep;
        logic fifo_head_age_ready;
        logic analytic_flush_ready;
        logic row_bucket_found;
        logic row_bucket_used;
        logic row_bucket_tile_found;

        repl_capture_present = 1'b0;
        repl_capture_is_prefetch = 1'b0;
        repl_capture_is_analytic = 1'b0;
        repl_capture_run_len = '0;
        repl_capture_fifo_pop_count = '0;
        row_bucket_used = 1'b0;
        for (k = 0; k < MERGE_MAX_X; k = k + 1) begin
            repl_capture_tile_x[k] = '0;
            repl_capture_tile_y[k] = '0;
        end

        if ((repl_state_reg == REPL_IDLE) &&
            !fill_req_valid_reg && !fill_active_reg && !fill_plan_valid_reg &&
            !read_issue_pending_reg && !row_inflight_reg) begin
            if (sample_miss_pending_reg) begin
                repl_capture_present = 1'b1;
                repl_capture_is_prefetch = 1'b0;
                repl_capture_is_analytic = 1'b0;
                repl_capture_run_len = RUN_LEN_W'(1);
                repl_capture_fifo_pop_count = FIFO_COUNT_W'(0);
                repl_capture_tile_x[0] = sample_miss_pending_tile_x_reg;
                repl_capture_tile_y[0] = sample_miss_pending_tile_y_reg;
            end else if (!(sample_req_valid && sample_miss_present) &&
                         !prefetch_throttle_active &&
                         !fifo_update_pending_reg &&
                         (fifo_count_reg != '0) &&
                         (!runtime_merge_min_enable ?
                            ((fifo_count_reg >= FIFO_COUNT_W'(runtime_merge_max_x_eff_clamped)) ||
                             !planner_active_reg || !planner_lead_ok) :
                            ((fifo_count_reg >= FIFO_COUNT_W'(runtime_merge_min_x_eff_clamped)) ||
                             ((runtime_fifo_age_limit_eff != '0) &&
                              (fifo_head_age_reg >= runtime_fifo_age_limit_eff)) ||
                             !planner_active_reg || !planner_lead_ok || planner_flush_ok))) begin
                fifo_head_age_ready = (runtime_fifo_age_limit_eff != '0) &&
                                      (fifo_head_age_reg >= runtime_fifo_age_limit_eff);
                analytic_flush_ready = !planner_active_reg || !planner_lead_ok || planner_flush_ok;
                merge_keep = 1'b1;
                for (k = 0; k < MERGE_MAX_X; k = k + 1) begin
                    if (merge_keep &&
                        (k < runtime_merge_max_x_eff_clamped) &&
                        (k < fifo_count_reg) &&
                        (fifo_tile_y_reg[k] == fifo_tile_y_reg[0]) &&
                        (fifo_tile_x_reg[k] == (fifo_tile_x_reg[0] + SECTOR_X_W'(k)))) begin
                        repl_capture_tile_x[k] = fifo_tile_x_reg[k];
                        repl_capture_tile_y[k] = fifo_tile_y_reg[k];
                        repl_capture_run_len = RUN_LEN_W'(k + 1);
                    end else begin
                        merge_keep = 1'b0;
                    end
                end
                if ((ENABLE_ROW_BUCKET_MERGE != 0) &&
                    (repl_capture_run_len <= RUN_LEN_W'(1)) &&
                    (runtime_merge_max_x_eff_clamped > RUN_LEN_W'(1))) begin
                    row_bucket_found = 1'b0;
                    merge_keep = 1'b1;
                    repl_capture_tile_x[0] = fifo_tile_x_reg[0];
                    repl_capture_tile_y[0] = fifo_tile_y_reg[0];
                    repl_capture_run_len = RUN_LEN_W'(1);
                    for (k = 1; k < MERGE_MAX_X; k = k + 1) begin
                        row_bucket_tile_found = 1'b0;
                        if (merge_keep && (k < runtime_merge_max_x_eff_clamped)) begin
                            for (q = 1; q < ANALYTIC_FIFO_DEPTH; q = q + 1) begin
                                if ((q < fifo_count_reg) &&
                                    (fifo_tile_y_reg[q] == fifo_tile_y_reg[0]) &&
                                    (fifo_tile_x_reg[q] == (fifo_tile_x_reg[0] + SECTOR_X_W'(k)))) begin
                                    row_bucket_tile_found = 1'b1;
                                end
                            end
                            if (row_bucket_tile_found) begin
                                repl_capture_tile_x[k] = fifo_tile_x_reg[0] + SECTOR_X_W'(k);
                                repl_capture_tile_y[k] = fifo_tile_y_reg[0];
                                repl_capture_run_len = RUN_LEN_W'(k + 1);
                                row_bucket_found = 1'b1;
                                row_bucket_used = 1'b1;
                            end else begin
                                merge_keep = 1'b0;
                            end
                        end
                    end
                    if (!row_bucket_found ||
                        (repl_capture_run_len < RUN_LEN_W'(ROW_BUCKET_MIN_X))) begin
                        repl_capture_run_len = RUN_LEN_W'(1);
                        row_bucket_used = 1'b0;
                    end
                end
                if (repl_capture_run_len == '0) begin
                    repl_capture_tile_x[0] = fifo_tile_x_reg[0];
                    repl_capture_tile_y[0] = fifo_tile_y_reg[0];
                    repl_capture_run_len = RUN_LEN_W'(1);
                end
                repl_capture_fifo_pop_count = row_bucket_used ?
                                              FIFO_COUNT_W'(1) :
                                              FIFO_COUNT_W'(repl_capture_run_len);
                if (!runtime_merge_min_enable ||
                    (repl_capture_run_len >= runtime_merge_min_x_eff_clamped) ||
                    fifo_head_age_ready || analytic_flush_ready) begin
                    repl_capture_present = 1'b1;
                    repl_capture_is_prefetch = 1'b1;
                    repl_capture_is_analytic = 1'b1;
                end
            end else if (!prefetch_throttle_active &&
                         (fifo_count_reg == '0) &&
                         cfg_prefetch_enable_reg &&
                         normal_prefetch_pending_reg) begin
                repl_capture_present = 1'b1;
                repl_capture_is_prefetch = 1'b1;
                repl_capture_is_analytic = 1'b0;
                repl_capture_run_len = RUN_LEN_W'(1);
                repl_capture_fifo_pop_count = FIFO_COUNT_W'(0);
                repl_capture_tile_x[0] = normal_prefetch_tile_x_reg;
                repl_capture_tile_y[0] = normal_prefetch_tile_y_reg;
            end
        end
    end

    assign repl_abort_speculative =
        (repl_state_reg != REPL_IDLE) &&
        repl_is_prefetch_reg &&
        (sample_miss_pending_reg || (sample_req_valid && sample_miss_present));

    always_comb begin
        int k;
        int r;
        logic way_reserved;
        logic [SET_W-1:0] precheck_lookup_set;
        logic [WAY_W-1:0] precheck_lookup_way;

        fill_request_present = 1'b0;
        fill_request_is_prefetch = repl_is_prefetch_reg;
        fill_request_is_analytic = repl_is_analytic_reg;
        fill_request_tile_x = repl_tile_x_reg[0];
        fill_request_tile_y = repl_tile_y_reg[0];
        fill_request_run_len = '0;
        fifo_pop_count = '0;
        scheduler_analytic_blocked = 1'b0;
        scheduler_replacement_fail = 1'b0;
        normal_prefetch_drop = 1'b0;
        repl_precheck_drop = 1'b0;
        repl_precheck_wait_fifo_update = 1'b0;
        repl_precheck_fifo_pop_count = '0;

        for (k = 0; k < MERGE_MAX_X; k = k + 1) begin
            fill_request_set[k] = repl_set_reg[k];
            fill_request_way[k] = repl_victim_way_reg[k];
            fill_request_evict_unused[k] = repl_evict_unused_reg[k];
        end

        if ((repl_state_reg == REPL_PRECHECK) && repl_is_analytic_reg) begin
            if (!coord_valid(repl_tile_x_reg[0], repl_tile_y_reg[0]) ||
                cache_lookup(repl_tile_x_reg[0], repl_tile_y_reg[0],
                             precheck_lookup_set, precheck_lookup_way) ||
                coord_pending(repl_tile_x_reg[0], repl_tile_y_reg[0])) begin
                repl_precheck_drop = 1'b1;
                repl_precheck_fifo_pop_count = FIFO_COUNT_W'(1);
                if (fifo_update_pending_reg) begin
                    repl_precheck_wait_fifo_update = 1'b1;
                end
                fifo_pop_count = repl_precheck_fifo_pop_count;
            end
        end

        if ((repl_state_reg == REPL_COMMIT) &&
            !repl_abort_speculative &&
            !(repl_is_analytic_reg && fifo_update_pending_reg)) begin
            for (k = 0; k < MERGE_MAX_X; k = k + 1) begin
                if ((k < repl_run_len_reg) && repl_lane_valid_reg[k] && repl_victim_found_reg[k]) begin
                    way_reserved = 1'b0;
                    for (r = 0; r < k; r = r + 1) begin
                        if ((r < fill_request_run_len) &&
                            (fill_request_set[r] == repl_set_reg[k]) &&
                            (fill_request_way[r] == repl_victim_way_reg[k])) begin
                            way_reserved = 1'b1;
                        end
                    end
                    if (!way_reserved) begin
                        fill_request_set[k] = repl_set_reg[k];
                        fill_request_way[k] = repl_victim_way_reg[k];
                        fill_request_evict_unused[k] = repl_evict_unused_reg[k];
                        fill_request_run_len = RUN_LEN_W'(k + 1);
                    end else if (repl_is_analytic_reg) begin
                        scheduler_analytic_blocked = 1'b1;
                        scheduler_replacement_fail = 1'b1;
                    end
                end else if (k == fill_request_run_len) begin
                    if (repl_is_analytic_reg) begin
                        scheduler_analytic_blocked = 1'b1;
                        scheduler_replacement_fail = 1'b1;
                    end else begin
                        scheduler_replacement_fail = 1'b1;
                    end
                end
            end

            if (fill_request_run_len != '0) begin
                fill_request_present = 1'b1;
                if (repl_is_analytic_reg) begin
                    if (repl_fifo_pop_count_reg > FIFO_COUNT_W'(fill_request_run_len)) begin
                        fifo_pop_count = FIFO_COUNT_W'(fill_request_run_len);
                    end else begin
                        fifo_pop_count = repl_fifo_pop_count_reg;
                    end
                end
            end else if (repl_is_prefetch_reg && !repl_is_analytic_reg) begin
                normal_prefetch_drop = 1'b1;
            end
        end
    end

    always_comb begin
        int k;

        fifo_head_run_len_calc = '0;
        fifo_same_row_adjacent_count_calc = '0;
        fifo_reverse_x_adjacent_count_calc = '0;
        merge_opportunity_missed_calc = 1'b0;

        if (fifo_count_reg != '0) begin
            for (k = 0; k < MERGE_MAX_X; k = k + 1) begin
                if ((k < fifo_count_reg) &&
                    (k < runtime_merge_max_x_eff_clamped) &&
                    (fifo_tile_y_reg[k] == fifo_tile_y_reg[0]) &&
                    (fifo_tile_x_reg[k] == (fifo_tile_x_reg[0] + SECTOR_X_W'(k)))) begin
                    fifo_head_run_len_calc = RUN_LEN_W'(k + 1);
                end
            end
            for (k = 1; k < ANALYTIC_FIFO_DEPTH; k = k + 1) begin
                if ((k < fifo_count_reg) &&
                    (fifo_tile_y_reg[k] == fifo_tile_y_reg[0]) &&
                    ((fifo_tile_x_reg[k] + 1'b1) == fifo_tile_x_reg[k-1])) begin
                    fifo_reverse_x_adjacent_count_calc = fifo_reverse_x_adjacent_count_calc + 1'b1;
                end
                if ((k < fifo_count_reg) &&
                    (fifo_tile_y_reg[k] == fifo_tile_y_reg[0]) &&
                    (fifo_tile_x_reg[k] != (fifo_tile_x_reg[0] + SECTOR_X_W'(k)))) begin
                    fifo_same_row_adjacent_count_calc = fifo_same_row_adjacent_count_calc + 1'b1;
                end
            end
            merge_opportunity_missed_calc =
                (fifo_same_row_adjacent_count_calc != '0 || fifo_reverse_x_adjacent_count_calc != '0) &&
                (fifo_head_run_len_calc <= RUN_LEN_W'(1));
        end
    end

    always_comb begin
        int k;
        int m;
        logic duplicate_sector;

        useful_sector_count_calc = '0;
        for (k = 0; k < 4; k = k + 1) begin
            duplicate_sector = 1'b0;
            for (m = 0; m < k; m = m + 1) begin
                if ((sample_set[k] == sample_set[m]) && (sample_way[k] == sample_way[m])) begin
                    duplicate_sector = 1'b1;
                end
            end
            if (sample_hit[k] && !duplicate_sector && !sector_used_reg[sector_slot(sample_set[k], sample_way[k])]) begin
                useful_sector_count_calc = useful_sector_count_calc + 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        int s;
        int w;
        int r;
        int c;
        int i;
        logic [STREAM_COL_W-1:0] next_stream_col;
        logic [STREAM_ROW_W-1:0] next_stream_row;
        logic [RUN_LEN_W-1:0] stream_sector_idx;
        logic [BASE_COL_W-1:0] stream_local_col;
        logic [BASE_ROW_W-1:0] stream_local_row;
        logic [31:0] start_x_byte;
        logic [31:0] start_y_row;
        logic [31:0] rem_width;
        logic [31:0] rem_rows;
        logic [31:0] plan_width;
        logic [31:0] plan_evict_unused_count;
        logic [15:0] plan_rows;
        logic [SECTOR_X_W-1:0] normal_prefetch_x;
        logic [SECTOR_Y_W-1:0] normal_prefetch_y;
        logic [SECTOR_X_W-1:0] plan_tile_x_i;
        logic [SLOT_W-1:0] slot_idx;
        logic [SET_W-1:0] repl_lookup_set;
        logic [WAY_W-1:0] repl_lookup_way;
        logic [RUN_LEN_W-1:0] repl_prefix_len;
        logic repl_keep_prefix;
        logic repl_victim_found;
        logic [WAY_W-1:0] repl_victim_way;
        logic repl_victim_evict_unused;
        logic [TOUCH_W-1:0] repl_oldest_touch;
        logic fifo_compact_keep;
        logic [FIFO_COUNT_W-1:0] fifo_compact_write_next;
    begin
        if (sys_rst) begin
            for (s = 0; s < SLOT_NUM; s = s + 1) begin
                sector_valid_reg[s] <= 1'b0;
                sector_prefetched_reg[s] <= 1'b0;
                sector_prefetch_fill_reg[s] <= 1'b0;
                sector_used_reg[s] <= 1'b0;
                sector_tag_x_reg[s] <= '0;
                sector_tag_y_reg[s] <= '0;
                sector_last_touch_reg[s] <= '0;
            end
            for (i = 0; i < ANALYTIC_FIFO_DEPTH; i = i + 1) begin
                fifo_tile_x_reg[i] <= '0;
                fifo_tile_y_reg[i] <= '0;
            end
            fifo_head_age_reg <= '0;
            for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                fill_plan_set_reg[i] <= '0;
                fill_plan_way_reg[i] <= '0;
                fill_plan_evict_unused_reg[i] <= 1'b0;
                fill_req_set_reg[i] <= '0;
                fill_req_way_reg[i] <= '0;
                fill_req_evict_unused_reg[i] <= 1'b0;
                fill_set_reg[i] <= '0;
                fill_way_reg[i] <= '0;
                repl_tile_x_reg[i] <= '0;
                repl_tile_y_reg[i] <= '0;
                repl_set_reg[i] <= '0;
                repl_lane_valid_reg[i] <= 1'b0;
                repl_victim_found_reg[i] <= 1'b0;
                repl_victim_way_reg[i] <= '0;
                repl_evict_unused_reg[i] <= 1'b0;
                for (w = 0; w < WAY_NUM; w = w + 1) begin
                    repl_protected_mask_reg[i][w] <= 1'b0;
                end
            end

            touch_counter_reg <= '0;
            cfg_src_base_addr_reg <= '0;
            cfg_src_stride_reg <= '0;
            cfg_src_w_reg <= '0;
            cfg_src_h_reg <= '0;
            cfg_dst_w_reg <= '0;
            cfg_dst_h_reg <= '0;
            cfg_rot_sin_q16_reg <= '0;
            cfg_rot_cos_q16_reg <= '0;
            cfg_prefetch_enable_reg <= 1'b0;
            cfg_sector_count_x_reg <= '0;
            cfg_sector_count_y_reg <= '0;
            cfg_src_x_last_reg <= '0;
            cfg_src_y_last_reg <= '0;
            cfg_src_x_max_q16_reg <= '0;
            cfg_src_y_max_q16_reg <= '0;
            cfg_geom_init_pending_reg <= 1'b0;
            error_reg <= 1'b0;

            sample_rsp_valid_reg <= 1'b0;
            sample_p00_reg <= '0;
            sample_p01_reg <= '0;
            sample_p10_reg <= '0;
            sample_p11_reg <= '0;
            sample_miss_pending_reg <= 1'b0;
            sample_miss_pending_tile_x_reg <= '0;
            sample_miss_pending_tile_y_reg <= '0;
            sample_miss_probe_valid_reg <= 1'b0;
            sample_miss_eval_valid_reg <= 1'b0;
            sample_miss_eval_present_reg <= 1'b0;
            sample_miss_eval_tile_x_reg <= '0;
            sample_miss_eval_tile_y_reg <= '0;
            for (i = 0; i < 4; i = i + 1) begin
                sample_miss_probe_tile_x_reg[i] <= '0;
                sample_miss_probe_tile_y_reg[i] <= '0;
            end
            last_sample_valid_reg <= 1'b0;
            last_sample_tile_x_reg <= '0;
            last_sample_tile_y_reg <= '0;
            last_scan_dir_x_reg <= '0;
            last_scan_dir_y_reg <= '0;
            last_scan_dir_valid_reg <= 1'b0;
            normal_prefetch_pending_reg <= 1'b0;
            normal_prefetch_tile_x_reg <= '0;
            normal_prefetch_tile_y_reg <= '0;

            fifo_count_reg <= '0;
            fifo_update_pending_reg <= 1'b0;
            fifo_compact_scan_idx_reg <= '0;
            fifo_compact_write_idx_reg <= '0;
            fifo_pop_pending_count_reg <= '0;
            fifo_delete_pending_valid_reg <= 1'b0;
            fifo_delete_pending_tile_x_reg <= '0;
            fifo_delete_pending_tile_y_reg <= '0;
            fifo_delete_req_valid_reg <= 1'b0;
            fifo_delete_req_tile_x_reg <= '0;
            fifo_delete_req_tile_y_reg <= '0;
            fifo_enqueue_pending_valid_reg <= 1'b0;
            fifo_enqueue_pending_tile_x_reg <= '0;
            fifo_enqueue_pending_tile_y_reg <= '0;
            fifo_head_age_reg <= '0;
            miss_throttle_count_reg <= '0;
            fill_plan_valid_reg <= 1'b0;
            fill_plan_tile_x_reg <= '0;
            fill_plan_tile_y_reg <= '0;
            fill_plan_run_len_reg <= '0;
            fill_plan_is_prefetch_reg <= 1'b0;
            fill_plan_is_analytic_reg <= 1'b0;
            fill_req_valid_reg <= 1'b0;
            fill_req_tile_x_reg <= '0;
            fill_req_tile_y_reg <= '0;
            fill_req_run_len_reg <= '0;
            fill_req_is_prefetch_reg <= 1'b0;
            fill_req_is_analytic_reg <= 1'b0;
            repl_state_reg <= REPL_IDLE;
            repl_run_len_reg <= '0;
            repl_fifo_pop_count_reg <= '0;
            repl_is_prefetch_reg <= 1'b0;
            repl_is_analytic_reg <= 1'b0;
            fill_active_reg <= 1'b0;
            fill_tile_x_reg <= '0;
            fill_tile_y_reg <= '0;
            fill_run_len_reg <= '0;
            fill_is_prefetch_reg <= 1'b0;
            fill_is_analytic_reg <= 1'b0;
            fill_read_width_reg <= '0;
            fill_read_rows_reg <= '0;
            fill_stream_col_reg <= '0;
            fill_stream_row_reg <= '0;
            row_inflight_reg <= 1'b0;
            read_issue_pending_reg <= 1'b0;
            read_addr_reg <= '0;
            read_row_stride_reg <= '0;
            read_byte_count_reg <= '0;
            read_row_count_reg <= '0;

            planner_active_reg <= 1'b0;
            planner_dst_x_reg <= '0;
            planner_dst_y_reg <= '0;
            planner_phase_reg <= '0;
            planner_row_x_reg <= '0;
            planner_row_y_reg <= '0;
            planner_cur_x_reg <= '0;
            planner_cur_y_reg <= '0;
            planner_step_x_x_reg <= '0;
            planner_step_y_x_reg <= '0;
            planner_step_x_y_reg <= '0;
            planner_step_y_y_reg <= '0;
            planner_pixel_count_reg <= '0;
            planner_tile_pending_reg <= 1'b0;
            planner_tile_x_reg <= '0;
            planner_tile_y_reg <= '0;
            planner_tile_blocked_reported_reg <= 1'b0;
            sample_accept_count_reg <= '0;
            stat_read_starts_reg <= '0;
            stat_misses_reg <= '0;
            stat_prefetch_starts_reg <= '0;
            stat_prefetch_hits_reg <= '0;
            stat_analytic_candidates_reg <= '0;
            stat_analytic_duplicates_reg <= '0;
            stat_analytic_blocked_reg <= '0;
            stat_analytic_fills_reg <= '0;
            stat_prefetch_evicted_unused_reg <= '0;
            stat_total_cycles_reg <= '0;
            stat_sample_req_count_reg <= '0;
            stat_sample_stall_cycles_reg <= '0;
            stat_normal_prefetch_fills_reg <= '0;
            stat_fifo_max_occupancy_reg <= '0;
            stat_read_busy_cycles_reg <= '0;
            stat_read_bytes_total_reg <= '0;
            stat_useful_source_sectors_reg <= '0;
            stat_useful_source_pending_valid_reg <= 1'b0;
            stat_useful_source_pending_count_reg <= '0;
            stat_replacement_fail_cycles_reg <= '0;
            stat_miss_service_latency_min_reg <= 32'hffff_ffff;
            stat_miss_service_latency_max_reg <= '0;
            stat_miss_service_latency_sum_reg <= '0;
            stat_miss_service_latency_count_reg <= '0;
            stat_fifo_head_run_len_reg <= '0;
            stat_fifo_same_row_adjacent_count_reg <= '0;
            stat_fifo_reverse_x_adjacent_count_reg <= '0;
            stat_merge_opportunity_missed_count_reg <= '0;
            stat_scheduler_analytic_blocked_pulse_reg <= 1'b0;
            stat_replacement_fail_pulse_reg <= 1'b0;
            miss_service_active_reg <= 1'b0;
            miss_service_latency_reg <= '0;
            for (i = 0; i <= MERGE_MAX_X; i = i + 1) begin
                stat_merge_len_hist_reg[i] <= '0;
            end
        end else begin
            sample_rsp_valid_reg <= 1'b0;

            if (fifo_update_pending_reg) begin
                if (fifo_compact_scan_idx_reg < fifo_count_reg) begin
                    fifo_compact_keep =
                        (fifo_compact_scan_idx_reg >= fifo_pop_pending_count_reg);
                    if (fifo_compact_keep && fifo_delete_pending_valid_reg &&
                        coord_equal(fifo_tile_x_reg[fifo_compact_scan_idx_reg],
                                    fifo_tile_y_reg[fifo_compact_scan_idx_reg],
                                    fifo_delete_pending_tile_x_reg,
                                    fifo_delete_pending_tile_y_reg)) begin
                        fifo_compact_keep = 1'b0;
                    end
                    if (fifo_compact_keep &&
                        (fifo_compact_write_idx_reg < FIFO_COUNT_W'(ANALYTIC_FIFO_DEPTH))) begin
                        fifo_tile_x_reg[fifo_compact_write_idx_reg] <=
                            fifo_tile_x_reg[fifo_compact_scan_idx_reg];
                        fifo_tile_y_reg[fifo_compact_write_idx_reg] <=
                            fifo_tile_y_reg[fifo_compact_scan_idx_reg];
                        fifo_compact_write_idx_reg <= fifo_compact_write_idx_reg + 1'b1;
                    end
                    fifo_compact_scan_idx_reg <= fifo_compact_scan_idx_reg + 1'b1;
                end else begin
                    fifo_compact_write_next = fifo_compact_write_idx_reg;
                    if (fifo_enqueue_pending_valid_reg &&
                        (fifo_compact_write_idx_reg < runtime_fifo_depth_eff_clamped) &&
                        (fifo_compact_write_idx_reg < FIFO_COUNT_W'(ANALYTIC_FIFO_DEPTH))) begin
                        fifo_tile_x_reg[fifo_compact_write_idx_reg] <= fifo_enqueue_pending_tile_x_reg;
                        fifo_tile_y_reg[fifo_compact_write_idx_reg] <= fifo_enqueue_pending_tile_y_reg;
                        fifo_compact_write_next = fifo_compact_write_idx_reg + 1'b1;
                    end
                    fifo_count_reg <= fifo_compact_write_next;
                    fifo_update_pending_reg <= 1'b0;
                    fifo_compact_scan_idx_reg <= '0;
                    fifo_compact_write_idx_reg <= '0;
                    fifo_pop_pending_count_reg <= '0;
                    fifo_delete_pending_valid_reg <= 1'b0;
                    fifo_enqueue_pending_valid_reg <= 1'b0;
                end
            end
            if (fifo_count_reg == '0) begin
                fifo_head_age_reg <= '0;
            end else if (fifo_head_age_reg != {FIFO_AGE_W{1'b1}}) begin
                fifo_head_age_reg <= fifo_head_age_reg + 1'b1;
            end
            if (miss_throttle_count_reg != '0) begin
                miss_throttle_count_reg <= miss_throttle_count_reg - 1'b1;
            end

            if (start) begin
                for (s = 0; s < SLOT_NUM; s = s + 1) begin
                    sector_valid_reg[s] <= 1'b0;
                    sector_prefetched_reg[s] <= 1'b0;
                    sector_prefetch_fill_reg[s] <= 1'b0;
                    sector_used_reg[s] <= 1'b0;
                    sector_tag_x_reg[s] <= '0;
                    sector_tag_y_reg[s] <= '0;
                    sector_last_touch_reg[s] <= '0;
                end
                for (i = 0; i < ANALYTIC_FIFO_DEPTH; i = i + 1) begin
                    fifo_tile_x_reg[i] <= '0;
                    fifo_tile_y_reg[i] <= '0;
                end
                fifo_head_age_reg <= '0;
                fifo_count_reg <= '0;
                fifo_update_pending_reg <= 1'b0;
                fifo_compact_scan_idx_reg <= '0;
                fifo_compact_write_idx_reg <= '0;
                fifo_pop_pending_count_reg <= '0;
                fifo_delete_pending_valid_reg <= 1'b0;
                fifo_delete_pending_tile_x_reg <= '0;
                fifo_delete_pending_tile_y_reg <= '0;
                fifo_delete_req_valid_reg <= 1'b0;
                fifo_delete_req_tile_x_reg <= '0;
                fifo_delete_req_tile_y_reg <= '0;
                fifo_enqueue_pending_valid_reg <= 1'b0;
                fifo_enqueue_pending_tile_x_reg <= '0;
                fifo_enqueue_pending_tile_y_reg <= '0;
                miss_throttle_count_reg <= '0;

                touch_counter_reg <= '0;
                cfg_src_base_addr_reg <= src_base_addr;
                cfg_src_stride_reg <= src_stride;
                cfg_src_w_reg <= src_w;
                cfg_src_h_reg <= src_h;
                cfg_dst_w_reg <= dst_w;
                cfg_dst_h_reg <= dst_h;
                cfg_rot_sin_q16_reg <= rot_sin_q16;
                cfg_rot_cos_q16_reg <= rot_cos_q16;
                cfg_prefetch_enable_reg <= prefetch_enable;
                cfg_sector_count_x_reg <= (src_w == '0) ? '0 : SECTOR_COUNT_X_W'((src_w + BASE_TILE_W - 1) >> TILE_X_SHIFT);
                cfg_sector_count_y_reg <= (src_h == '0) ? '0 : SECTOR_COUNT_Y_W'((src_h + BASE_TILE_H - 1) >> TILE_Y_SHIFT);
                cfg_src_x_last_reg <= (src_w == '0) ? '0 : SRC_X_W'(src_w - 1'b1);
                cfg_src_y_last_reg <= (src_h == '0) ? '0 : SRC_Y_W'(src_h - 1'b1);
                cfg_src_x_max_q16_reg <= (src_w == '0) ? '0 : (($signed({1'b0, src_w}) - 1) <<< FRAC_W);
                cfg_src_y_max_q16_reg <= (src_h == '0) ? '0 : (($signed({1'b0, src_h}) - 1) <<< FRAC_W);
                cfg_geom_init_pending_reg <= prefetch_enable &&
                                             (src_w != '0) &&
                                             (src_h != '0) &&
                                             (dst_w != '0) &&
                                             (dst_h != '0);
                error_reg <= 1'b0;

                fill_plan_valid_reg <= 1'b0;
                fill_req_valid_reg <= 1'b0;
                fill_req_tile_x_reg <= '0;
                fill_req_tile_y_reg <= '0;
                fill_req_run_len_reg <= '0;
                fill_req_is_prefetch_reg <= 1'b0;
                fill_req_is_analytic_reg <= 1'b0;
                repl_state_reg <= REPL_IDLE;
                repl_run_len_reg <= '0;
                repl_fifo_pop_count_reg <= '0;
                repl_is_prefetch_reg <= 1'b0;
                repl_is_analytic_reg <= 1'b0;
                for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                    repl_tile_x_reg[i] <= '0;
                    repl_tile_y_reg[i] <= '0;
                    repl_set_reg[i] <= '0;
                    repl_lane_valid_reg[i] <= 1'b0;
                    repl_victim_found_reg[i] <= 1'b0;
                    repl_victim_way_reg[i] <= '0;
                    repl_evict_unused_reg[i] <= 1'b0;
                    for (w = 0; w < WAY_NUM; w = w + 1) begin
                        repl_protected_mask_reg[i][w] <= 1'b0;
                    end
                end
                fill_active_reg <= 1'b0;
                row_inflight_reg <= 1'b0;
                read_issue_pending_reg <= 1'b0;
                read_addr_reg <= '0;
                read_row_stride_reg <= '0;
                read_byte_count_reg <= '0;
                read_row_count_reg <= '0;
                sample_rsp_valid_reg <= 1'b0;
                sample_miss_pending_reg <= 1'b0;
                sample_miss_pending_tile_x_reg <= '0;
                sample_miss_pending_tile_y_reg <= '0;
                sample_miss_probe_valid_reg <= 1'b0;
                sample_miss_eval_valid_reg <= 1'b0;
                sample_miss_eval_present_reg <= 1'b0;
                sample_miss_eval_tile_x_reg <= '0;
                sample_miss_eval_tile_y_reg <= '0;
                for (i = 0; i < 4; i = i + 1) begin
                    sample_miss_probe_tile_x_reg[i] <= '0;
                    sample_miss_probe_tile_y_reg[i] <= '0;
                end
                last_sample_valid_reg <= 1'b0;
                last_scan_dir_valid_reg <= 1'b0;
                normal_prefetch_pending_reg <= 1'b0;
                normal_prefetch_tile_x_reg <= '0;
                normal_prefetch_tile_y_reg <= '0;
                sample_accept_count_reg <= '0;

                planner_step_x_x_reg <= '0;
                planner_step_y_x_reg <= '0;
                planner_step_x_y_reg <= '0;
                planner_step_y_y_reg <= '0;
                planner_row_x_reg <= '0;
                planner_row_y_reg <= '0;
                planner_cur_x_reg <= '0;
                planner_cur_y_reg <= '0;
                planner_dst_x_reg <= '0;
                planner_dst_y_reg <= '0;
                planner_phase_reg <= '0;
                planner_pixel_count_reg <= '0;
                planner_tile_pending_reg <= 1'b0;
                planner_tile_x_reg <= '0;
                planner_tile_y_reg <= '0;
                planner_tile_blocked_reported_reg <= 1'b0;
                planner_active_reg <= 1'b0;
                stat_read_starts_reg <= '0;
                stat_misses_reg <= '0;
                stat_prefetch_starts_reg <= '0;
                stat_prefetch_hits_reg <= '0;
                stat_analytic_candidates_reg <= '0;
                stat_analytic_duplicates_reg <= '0;
                stat_analytic_blocked_reg <= '0;
                stat_analytic_fills_reg <= '0;
                stat_prefetch_evicted_unused_reg <= '0;
                stat_total_cycles_reg <= '0;
                stat_sample_req_count_reg <= '0;
                stat_sample_stall_cycles_reg <= '0;
                stat_normal_prefetch_fills_reg <= '0;
                stat_fifo_max_occupancy_reg <= '0;
                stat_read_busy_cycles_reg <= '0;
                stat_read_bytes_total_reg <= '0;
                stat_useful_source_sectors_reg <= '0;
                stat_useful_source_pending_valid_reg <= 1'b0;
                stat_useful_source_pending_count_reg <= '0;
                stat_replacement_fail_cycles_reg <= '0;
                stat_miss_service_latency_min_reg <= 32'hffff_ffff;
                stat_miss_service_latency_max_reg <= '0;
                stat_miss_service_latency_sum_reg <= '0;
                stat_miss_service_latency_count_reg <= '0;
                stat_fifo_head_run_len_reg <= '0;
                stat_fifo_same_row_adjacent_count_reg <= '0;
                stat_fifo_reverse_x_adjacent_count_reg <= '0;
                stat_merge_opportunity_missed_count_reg <= '0;
                stat_scheduler_analytic_blocked_pulse_reg <= 1'b0;
                stat_replacement_fail_pulse_reg <= 1'b0;
                miss_service_active_reg <= 1'b0;
                miss_service_latency_reg <= '0;
                for (i = 0; i <= MERGE_MAX_X; i = i + 1) begin
                    stat_merge_len_hist_reg[i] <= '0;
                end
            end else if (read_error) begin
                error_reg <= 1'b1;
                fill_plan_valid_reg <= 1'b0;
                fill_req_valid_reg <= 1'b0;
                repl_state_reg <= REPL_IDLE;
                repl_run_len_reg <= '0;
                repl_fifo_pop_count_reg <= '0;
                repl_is_prefetch_reg <= 1'b0;
                repl_is_analytic_reg <= 1'b0;
                fill_active_reg <= 1'b0;
                row_inflight_reg <= 1'b0;
                read_issue_pending_reg <= 1'b0;
                read_addr_reg <= '0;
                read_row_stride_reg <= '0;
                read_byte_count_reg <= '0;
                read_row_count_reg <= '0;
                fill_read_width_reg <= '0;
                fill_read_rows_reg <= '0;
                fill_stream_col_reg <= '0;
                fill_stream_row_reg <= '0;
                fill_run_len_reg <= '0;
                fill_is_prefetch_reg <= 1'b0;
                fill_is_analytic_reg <= 1'b0;
                planner_active_reg <= 1'b0;
                planner_tile_pending_reg <= 1'b0;
                planner_tile_x_reg <= '0;
                planner_tile_y_reg <= '0;
                planner_tile_blocked_reported_reg <= 1'b0;
                cfg_geom_init_pending_reg <= 1'b0;
                sample_miss_pending_reg <= 1'b0;
                sample_miss_probe_valid_reg <= 1'b0;
                sample_miss_eval_valid_reg <= 1'b0;
                sample_miss_eval_present_reg <= 1'b0;
                sample_miss_eval_tile_x_reg <= '0;
                sample_miss_eval_tile_y_reg <= '0;
                for (i = 0; i < 4; i = i + 1) begin
                    sample_miss_probe_tile_x_reg[i] <= '0;
                    sample_miss_probe_tile_y_reg[i] <= '0;
                end
                normal_prefetch_pending_reg <= 1'b0;
                stat_scheduler_analytic_blocked_pulse_reg <= 1'b0;
                stat_replacement_fail_pulse_reg <= 1'b0;
                stat_useful_source_pending_valid_reg <= 1'b0;
                stat_useful_source_pending_count_reg <= '0;
                fifo_count_reg <= '0;
                fifo_update_pending_reg <= 1'b0;
                fifo_compact_scan_idx_reg <= '0;
                fifo_compact_write_idx_reg <= '0;
                fifo_pop_pending_count_reg <= '0;
                fifo_delete_pending_valid_reg <= 1'b0;
                fifo_delete_pending_tile_x_reg <= '0;
                fifo_delete_pending_tile_y_reg <= '0;
                fifo_delete_req_valid_reg <= 1'b0;
                fifo_delete_req_tile_x_reg <= '0;
                fifo_delete_req_tile_y_reg <= '0;
                fifo_enqueue_pending_valid_reg <= 1'b0;
                fifo_enqueue_pending_tile_x_reg <= '0;
                fifo_enqueue_pending_tile_y_reg <= '0;
                miss_throttle_count_reg <= '0;
                for (i = 0; i < ANALYTIC_FIFO_DEPTH; i = i + 1) begin
                    fifo_tile_x_reg[i] <= '0;
                    fifo_tile_y_reg[i] <= '0;
                end
                fifo_head_age_reg <= '0;
                for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                    repl_tile_x_reg[i] <= '0;
                    repl_tile_y_reg[i] <= '0;
                    repl_set_reg[i] <= '0;
                    repl_lane_valid_reg[i] <= 1'b0;
                    repl_victim_found_reg[i] <= 1'b0;
                    repl_victim_way_reg[i] <= '0;
                    repl_evict_unused_reg[i] <= 1'b0;
                    for (w = 0; w < WAY_NUM; w = w + 1) begin
                        repl_protected_mask_reg[i][w] <= 1'b0;
                    end
                    if (i < fill_run_len_reg) begin
                        slot_idx = sector_slot(fill_set_reg[i], fill_way_reg[i]);
                        sector_valid_reg[slot_idx] <= 1'b0;
                        sector_prefetched_reg[slot_idx] <= 1'b0;
                        sector_prefetch_fill_reg[slot_idx] <= 1'b0;
                        sector_used_reg[slot_idx] <= 1'b0;
                    end
                end
            end else begin
                if (busy) begin
                    stat_total_cycles_reg <= stat_total_cycles_reg + 1'b1;
                end

                if (sample_req_valid) begin
                    stat_sample_req_count_reg <= stat_sample_req_count_reg + 1'b1;
                    if (!sample_req_ready) begin
                        stat_sample_stall_cycles_reg <= stat_sample_stall_cycles_reg + 1'b1;
                    end
                end
                if (read_busy) begin
                    stat_read_busy_cycles_reg <= stat_read_busy_cycles_reg + 1'b1;
                end
                if (stat_useful_source_pending_valid_reg) begin
                    stat_useful_source_sectors_reg <=
                        stat_useful_source_sectors_reg + stat_useful_source_pending_count_reg;
                    stat_useful_source_pending_valid_reg <= 1'b0;
                    stat_useful_source_pending_count_reg <= '0;
                end
                if (sample_miss_probe_valid_reg) begin
                    sample_miss_eval_valid_reg <= 1'b1;
                    sample_miss_eval_present_reg <= sample_miss_probe_present;
                    sample_miss_eval_tile_x_reg <= sample_miss_probe_tile_x;
                    sample_miss_eval_tile_y_reg <= sample_miss_probe_tile_y;
                    sample_miss_probe_valid_reg <= 1'b0;
                end else if (sample_miss_eval_valid_reg) begin
                    if (sample_miss_eval_present_reg &&
                        !coord_pending(sample_miss_eval_tile_x_reg, sample_miss_eval_tile_y_reg) &&
                        !sample_miss_pending_reg) begin
                        sample_miss_pending_reg <= 1'b1;
                        sample_miss_pending_tile_x_reg <= sample_miss_eval_tile_x_reg;
                        sample_miss_pending_tile_y_reg <= sample_miss_eval_tile_y_reg;
                    end
                    sample_miss_eval_valid_reg <= 1'b0;
                end else if (!sample_miss_pending_reg &&
                             sample_req_valid &&
                             !sample_rsp_valid_reg) begin
                    sample_miss_probe_valid_reg <= 1'b1;
                    for (i = 0; i < 4; i = i + 1) begin
                        sample_miss_probe_tile_x_reg[i] <= sample_tile_x[i];
                        sample_miss_probe_tile_y_reg[i] <= sample_tile_y[i];
                    end
                end
                if (fifo_count_reg > stat_fifo_max_occupancy_reg[FIFO_COUNT_W-1:0]) begin
                    stat_fifo_max_occupancy_reg <= 32'(fifo_count_reg);
                end
                if (stat_replacement_fail_pulse_reg) begin
                    stat_replacement_fail_cycles_reg <= stat_replacement_fail_cycles_reg + 1'b1;
                end
                if (fifo_head_run_len_calc > stat_fifo_head_run_len_reg[RUN_LEN_W-1:0]) begin
                    stat_fifo_head_run_len_reg <= 32'(fifo_head_run_len_calc);
                end
                if (fifo_same_row_adjacent_count_calc != '0) begin
                    stat_fifo_same_row_adjacent_count_reg <=
                        stat_fifo_same_row_adjacent_count_reg + fifo_same_row_adjacent_count_calc;
                end
                if (fifo_reverse_x_adjacent_count_calc != '0) begin
                    stat_fifo_reverse_x_adjacent_count_reg <=
                        stat_fifo_reverse_x_adjacent_count_reg + fifo_reverse_x_adjacent_count_calc;
                end
                if (merge_opportunity_missed_calc) begin
                    stat_merge_opportunity_missed_count_reg <= stat_merge_opportunity_missed_count_reg + 1'b1;
                end
                if (sample_req_valid && sample_miss_present && !sample_req_ready && !miss_service_active_reg) begin
                    miss_service_active_reg <= 1'b1;
                    miss_service_latency_reg <= '0;
                end else if (miss_service_active_reg && !sample_req_ready) begin
                    miss_service_latency_reg <= miss_service_latency_reg + 1'b1;
                end

                if (cfg_geom_init_pending_reg && geom_error) begin
                    cfg_geom_init_pending_reg <= 1'b0;
                    planner_active_reg <= 1'b0;
                    planner_tile_pending_reg <= 1'b0;
                    planner_tile_blocked_reported_reg <= 1'b0;
                    error_reg <= 1'b1;
                end else if (cfg_geom_init_pending_reg && geom_ready) begin
                    planner_step_x_x_reg <= geom_step_x_x;
                    planner_step_y_x_reg <= geom_step_y_x;
                    planner_step_x_y_reg <= geom_step_x_y;
                    planner_step_y_y_reg <= geom_step_y_y;
                    planner_row_x_reg <= geom_row0_x;
                    planner_row_y_reg <= geom_row0_y;
                    planner_cur_x_reg <= geom_row0_x;
                    planner_cur_y_reg <= geom_row0_y;
                    planner_dst_x_reg <= '0;
                    planner_dst_y_reg <= '0;
                    planner_phase_reg <= '0;
                    planner_pixel_count_reg <= '0;
                    planner_tile_pending_reg <= 1'b0;
                    planner_tile_x_reg <= '0;
                    planner_tile_y_reg <= '0;
                    planner_tile_blocked_reported_reg <= 1'b0;
                    cfg_src_x_last_reg <= geom_src_x_last;
                    cfg_src_y_last_reg <= geom_src_y_last;
                    cfg_src_x_max_q16_reg <= geom_src_x_max_q16;
                    cfg_src_y_max_q16_reg <= geom_src_y_max_q16;
                    planner_active_reg <= 1'b1;
                    cfg_geom_init_pending_reg <= 1'b0;
                end

                if (sample_req_ready) begin
                    sample_p00_reg <= sector_mem[sector_slot(sample_set[0], sample_way[0])][sector_pixel_lsb(sample_row[0], sample_col[0]) +: PIXEL_W];
                    sample_p01_reg <= sector_mem[sector_slot(sample_set[1], sample_way[1])][sector_pixel_lsb(sample_row[1], sample_col[1]) +: PIXEL_W];
                    sample_p10_reg <= sector_mem[sector_slot(sample_set[2], sample_way[2])][sector_pixel_lsb(sample_row[2], sample_col[2]) +: PIXEL_W];
                    sample_p11_reg <= sector_mem[sector_slot(sample_set[3], sample_way[3])][sector_pixel_lsb(sample_row[3], sample_col[3]) +: PIXEL_W];
                    sample_rsp_valid_reg <= 1'b1;
                    sample_accept_count_reg <= sample_accept_count_reg + 1'b1;
                    touch_counter_reg <= touch_counter_reg + 1'b1;
                    last_sample_valid_reg <= 1'b1;
                    last_sample_tile_x_reg <= sample_tile_x[0];
                    last_sample_tile_y_reg <= sample_tile_y[0];
                    last_scan_dir_x_reg <= scan_dir_x;
                    last_scan_dir_y_reg <= scan_dir_y;
                    last_scan_dir_valid_reg <= scan_dir_valid;
                    normal_prefetch_x = sample_tile_x[0];
                    normal_prefetch_y = sample_tile_y[0];
                    if (scan_dir_valid) begin
                        if (scan_dir_x > 0) begin
                            normal_prefetch_x = sample_tile_x[0] + 1'b1;
                        end else if ((scan_dir_x < 0) && (sample_tile_x[0] != '0)) begin
                            normal_prefetch_x = sample_tile_x[0] - 1'b1;
                        end
                        if (scan_dir_y > 0) begin
                            normal_prefetch_y = sample_tile_y[0] + 1'b1;
                        end else if ((scan_dir_y < 0) && (sample_tile_y[0] != '0)) begin
                            normal_prefetch_y = sample_tile_y[0] - 1'b1;
                        end
                    end else if (sample_tile_x[0] + 1'b1 < cfg_sector_count_x_reg) begin
                        normal_prefetch_x = sample_tile_x[0] + 1'b1;
                    end
                    normal_prefetch_pending_reg <= cfg_prefetch_enable_reg;
                    normal_prefetch_tile_x_reg <= normal_prefetch_x;
                    normal_prefetch_tile_y_reg <= normal_prefetch_y;
                    if (any_sample_prefetch_hit) begin
                        stat_prefetch_hits_reg <= stat_prefetch_hits_reg + 1'b1;
                    end
                    if (miss_service_active_reg) begin
                        stat_miss_service_latency_count_reg <= stat_miss_service_latency_count_reg + 1'b1;
                        stat_miss_service_latency_sum_reg <= stat_miss_service_latency_sum_reg + miss_service_latency_reg;
                        if (miss_service_latency_reg < stat_miss_service_latency_min_reg) begin
                            stat_miss_service_latency_min_reg <= miss_service_latency_reg;
                        end
                        if (miss_service_latency_reg > stat_miss_service_latency_max_reg) begin
                            stat_miss_service_latency_max_reg <= miss_service_latency_reg;
                        end
                        miss_service_active_reg <= 1'b0;
                        miss_service_latency_reg <= '0;
                    end
                    stat_useful_source_pending_valid_reg <= (useful_sector_count_calc != '0);
                    stat_useful_source_pending_count_reg <= useful_sector_count_calc;
                    for (i = 0; i < 4; i = i + 1) begin
                        if (sample_hit[i]) begin
                            slot_idx = sector_slot(sample_set[i], sample_way[i]);
                            sector_prefetched_reg[slot_idx] <= 1'b0;
                            sector_used_reg[slot_idx] <= 1'b1;
                            sector_last_touch_reg[slot_idx] <= touch_counter_reg + 1'b1;
                        end
                    end
                end

                if (!planner_init_busy && planner_active_reg && cfg_prefetch_enable_reg &&
                    (planner_lead_ok || planner_tile_pending_reg)) begin
                    if (planner_candidate_valid) begin
                        planner_tile_pending_reg <= 1'b1;
                        planner_tile_x_reg <= planner_candidate_tile_x;
                        planner_tile_y_reg <= planner_candidate_tile_y;
                        planner_tile_blocked_reported_reg <= 1'b0;
                        stat_analytic_candidates_reg <= stat_analytic_candidates_reg + 1'b1;
                    end

                    if (planner_tile_pending_reg) begin
                        if (planner_candidate_duplicate) begin
                            stat_analytic_duplicates_reg <= stat_analytic_duplicates_reg + 1'b1;
                            planner_tile_pending_reg <= 1'b0;
                            planner_tile_blocked_reported_reg <= 1'b0;
                        end else if (planner_candidate_blocked) begin
                            if (!planner_tile_blocked_reported_reg) begin
                                stat_analytic_blocked_reg <= stat_analytic_blocked_reg + 1'b1;
                                planner_tile_blocked_reported_reg <= 1'b1;
                            end
                        end else begin
                            planner_tile_pending_reg <= 1'b0;
                            planner_tile_blocked_reported_reg <= 1'b0;
                        end
                    end
                    if (planner_advance_phase) begin
                        if (planner_phase_reg != 2'd3) begin
                            planner_phase_reg <= planner_phase_reg + 1'b1;
                        end else begin
                            planner_phase_reg <= '0;
                            planner_pixel_count_reg <= planner_pixel_count_reg + 1'b1;
                            if (planner_dst_x_reg + 1'b1 < cfg_dst_w_reg) begin
                                planner_dst_x_reg <= planner_dst_x_reg + 1'b1;
                                planner_cur_x_reg <= planner_cur_x_reg + planner_step_x_x_reg;
                                planner_cur_y_reg <= planner_cur_y_reg + planner_step_y_x_reg;
                            end else if (planner_dst_y_reg + 1'b1 < cfg_dst_h_reg) begin
                                planner_dst_x_reg <= '0;
                                planner_dst_y_reg <= planner_dst_y_reg + 1'b1;
                                planner_row_x_reg <= planner_row_x_reg + planner_step_x_y_reg;
                                planner_row_y_reg <= planner_row_y_reg + planner_step_y_y_reg;
                                planner_cur_x_reg <= planner_row_x_reg + planner_step_x_y_reg;
                                planner_cur_y_reg <= planner_row_y_reg + planner_step_y_y_reg;
                            end else begin
                                planner_active_reg <= 1'b0;
                            end
                        end
                    end
                end

                if (stat_scheduler_analytic_blocked_pulse_reg) begin
                    stat_analytic_blocked_reg <= stat_analytic_blocked_reg + 1'b1;
                end
                stat_replacement_fail_pulse_reg <= scheduler_replacement_fail;
                stat_scheduler_analytic_blocked_pulse_reg <=
                    !planner_init_busy && scheduler_analytic_blocked && !fill_request_present;

                if (!fifo_update_pending_reg &&
                    ((fifo_pop_count != '0) ||
                     fifo_delete_req_valid_reg ||
                     planner_candidate_enqueue)) begin
                    fifo_update_pending_reg <= 1'b1;
                    fifo_pop_pending_count_reg <= fifo_pop_count;
                    fifo_delete_pending_valid_reg <= fifo_delete_req_valid_reg;
                    fifo_enqueue_pending_valid_reg <= planner_candidate_enqueue;
                    if (fifo_delete_req_valid_reg) begin
                        fifo_delete_pending_tile_x_reg <= fifo_delete_req_tile_x_reg;
                        fifo_delete_pending_tile_y_reg <= fifo_delete_req_tile_y_reg;
                        fifo_delete_req_valid_reg <= 1'b0;
                    end
                    if (planner_candidate_enqueue) begin
                        fifo_enqueue_pending_tile_x_reg <= planner_tile_x_reg;
                        fifo_enqueue_pending_tile_y_reg <= planner_tile_y_reg;
                    end
                end

                if (repl_abort_speculative) begin
                    repl_state_reg <= REPL_IDLE;
                    repl_run_len_reg <= '0;
                    repl_fifo_pop_count_reg <= '0;
                    for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                        repl_lane_valid_reg[i] <= 1'b0;
                        repl_victim_found_reg[i] <= 1'b0;
                        repl_evict_unused_reg[i] <= 1'b0;
                        for (w = 0; w < WAY_NUM; w = w + 1) begin
                            repl_protected_mask_reg[i][w] <= 1'b0;
                        end
                    end
                end else begin
                    case (repl_state_reg)
                        REPL_IDLE: begin
                            repl_is_prefetch_reg <= repl_capture_is_prefetch;
                            repl_is_analytic_reg <= repl_capture_is_analytic;
                            if (repl_capture_present) begin
                                repl_run_len_reg <= repl_capture_run_len;
                                repl_fifo_pop_count_reg <= repl_capture_fifo_pop_count;
                                for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                                    repl_tile_x_reg[i] <= repl_capture_tile_x[i];
                                    repl_tile_y_reg[i] <= repl_capture_tile_y[i];
                                    repl_set_reg[i] <= sector_set(repl_capture_tile_x[i], repl_capture_tile_y[i]);
                                    repl_lane_valid_reg[i] <= 1'b0;
                                    repl_victim_found_reg[i] <= 1'b0;
                                    repl_victim_way_reg[i] <= '0;
                                    repl_evict_unused_reg[i] <= 1'b0;
                                    for (w = 0; w < WAY_NUM; w = w + 1) begin
                                        repl_protected_mask_reg[i][w] <= 1'b0;
                                    end
                                end
                                repl_state_reg <= REPL_PRECHECK;
                            end
                        end

                        REPL_PRECHECK: begin
                            if (repl_precheck_wait_fifo_update) begin
                                repl_state_reg <= REPL_PRECHECK;
                            end else if (repl_precheck_drop) begin
                                repl_state_reg <= REPL_IDLE;
                                repl_run_len_reg <= '0;
                                repl_fifo_pop_count_reg <= '0;
                            end else begin
                                repl_prefix_len = '0;
                                repl_keep_prefix = 1'b1;
                                for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                                    repl_lane_valid_reg[i] <= 1'b0;
                                    repl_victim_found_reg[i] <= 1'b0;
                                    repl_evict_unused_reg[i] <= 1'b0;
                                    if (repl_keep_prefix && (i < repl_run_len_reg)) begin
                                        if (coord_valid(repl_tile_x_reg[i], repl_tile_y_reg[i]) &&
                                            !cache_lookup(repl_tile_x_reg[i], repl_tile_y_reg[i],
                                                          repl_lookup_set, repl_lookup_way) &&
                                            !coord_pending(repl_tile_x_reg[i], repl_tile_y_reg[i]) &&
                                            !(repl_is_prefetch_reg && !repl_is_analytic_reg &&
                                              coord_in_fifo(repl_tile_x_reg[i], repl_tile_y_reg[i]))) begin
                                            repl_set_reg[i] <= sector_set(repl_tile_x_reg[i], repl_tile_y_reg[i]);
                                            repl_lane_valid_reg[i] <= 1'b1;
                                            repl_prefix_len = RUN_LEN_W'(i + 1);
                                        end else begin
                                            repl_keep_prefix = 1'b0;
                                        end
                                    end
                                end

                                if (repl_prefix_len != '0) begin
                                    repl_run_len_reg <= repl_prefix_len;
                                    if (repl_is_analytic_reg &&
                                        (repl_fifo_pop_count_reg > FIFO_COUNT_W'(repl_prefix_len))) begin
                                        repl_fifo_pop_count_reg <= FIFO_COUNT_W'(repl_prefix_len);
                                    end
                                    repl_state_reg <= REPL_PROTECT;
                                end else begin
                                    if (!repl_is_prefetch_reg &&
                                        cache_lookup(repl_tile_x_reg[0], repl_tile_y_reg[0],
                                                     repl_lookup_set, repl_lookup_way)) begin
                                        sample_miss_pending_reg <= 1'b0;
                                    end else if (repl_is_prefetch_reg && !repl_is_analytic_reg) begin
                                        normal_prefetch_pending_reg <= 1'b0;
                                    end
                                    repl_run_len_reg <= '0;
                                    repl_fifo_pop_count_reg <= '0;
                                    repl_state_reg <= REPL_IDLE;
                                end
                            end
                        end

                        REPL_PROTECT: begin
                            for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                                for (w = 0; w < WAY_NUM; w = w + 1) begin
                                    slot_idx = sector_slot(repl_set_reg[i], WAY_W'(w));
                                    if ((i < repl_run_len_reg) && repl_lane_valid_reg[i]) begin
                                        repl_protected_mask_reg[i][w] <=
                                            sector_valid_reg[slot_idx] &&
                                            protected_coord(sector_tag_x_reg[slot_idx],
                                                            sector_tag_y_reg[slot_idx]);
                                    end else begin
                                        repl_protected_mask_reg[i][w] <= 1'b0;
                                    end
                                end
                            end
                            repl_state_reg <= REPL_INVALID;
                        end

                        REPL_INVALID: begin
                            for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                                if ((i < repl_run_len_reg) && repl_lane_valid_reg[i]) begin
                                    repl_victim_found = 1'b0;
                                    repl_victim_way = '0;
                                    for (w = 0; w < WAY_NUM; w = w + 1) begin
                                        slot_idx = sector_slot(repl_set_reg[i], WAY_W'(w));
                                        if (!repl_victim_found && !sector_valid_reg[slot_idx]) begin
                                            repl_victim_found = 1'b1;
                                            repl_victim_way = WAY_W'(w);
                                        end
                                    end
                                    if (repl_victim_found) begin
                                        repl_victim_found_reg[i] <= 1'b1;
                                        repl_victim_way_reg[i] <= repl_victim_way;
                                        repl_evict_unused_reg[i] <= 1'b0;
                                    end
                                end
                            end
                            repl_state_reg <= REPL_PREFETCH;
                        end

                        REPL_PREFETCH: begin
                            for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                                if ((i < repl_run_len_reg) && repl_lane_valid_reg[i] &&
                                    !repl_victim_found_reg[i]) begin
                                    repl_victim_found = 1'b0;
                                    repl_victim_way = '0;
                                    for (w = 0; w < WAY_NUM; w = w + 1) begin
                                        slot_idx = sector_slot(repl_set_reg[i], WAY_W'(w));
                                        if (!repl_victim_found &&
                                            !repl_protected_mask_reg[i][w] &&
                                            sector_prefetch_fill_reg[slot_idx] &&
                                            sector_used_reg[slot_idx]) begin
                                            repl_victim_found = 1'b1;
                                            repl_victim_way = WAY_W'(w);
                                        end
                                    end
                                    if (repl_victim_found) begin
                                        repl_victim_found_reg[i] <= 1'b1;
                                        repl_victim_way_reg[i] <= repl_victim_way;
                                        repl_evict_unused_reg[i] <= 1'b0;
                                    end
                                end
                            end
                            repl_state_reg <= REPL_OLDEST;
                        end

                        REPL_OLDEST: begin
                            for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                                if ((i < repl_run_len_reg) && repl_lane_valid_reg[i] &&
                                    !repl_victim_found_reg[i]) begin
                                    repl_victim_found = 1'b0;
                                    repl_victim_way = '0;
                                    repl_victim_evict_unused = 1'b0;
                                    repl_oldest_touch = {TOUCH_W{1'b1}};
                                    for (w = 0; w < WAY_NUM; w = w + 1) begin
                                        slot_idx = sector_slot(repl_set_reg[i], WAY_W'(w));
                                        if (!repl_protected_mask_reg[i][w] &&
                                            (sector_last_touch_reg[slot_idx] <= repl_oldest_touch)) begin
                                            repl_victim_found = 1'b1;
                                            repl_victim_way = WAY_W'(w);
                                            repl_oldest_touch = sector_last_touch_reg[slot_idx];
                                            repl_victim_evict_unused =
                                                sector_valid_reg[slot_idx] &&
                                                sector_prefetch_fill_reg[slot_idx] &&
                                                !sector_used_reg[slot_idx];
                                        end
                                    end
                                    if (repl_victim_found) begin
                                        repl_victim_found_reg[i] <= 1'b1;
                                        repl_victim_way_reg[i] <= repl_victim_way;
                                        repl_evict_unused_reg[i] <= repl_victim_evict_unused;
                                    end
                                end
                            end
                            repl_state_reg <= REPL_COMMIT;
                        end

                        REPL_COMMIT: begin
                            if (fill_request_present || scheduler_replacement_fail || normal_prefetch_drop) begin
                                repl_state_reg <= REPL_IDLE;
                                repl_run_len_reg <= '0;
                                repl_fifo_pop_count_reg <= '0;
                                for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                                    repl_lane_valid_reg[i] <= 1'b0;
                                    repl_victim_found_reg[i] <= 1'b0;
                                    repl_evict_unused_reg[i] <= 1'b0;
                                    for (w = 0; w < WAY_NUM; w = w + 1) begin
                                        repl_protected_mask_reg[i][w] <= 1'b0;
                                    end
                                end
                            end
                        end

                        default: begin
                            repl_state_reg <= REPL_IDLE;
                        end
                    endcase
                end

                if (fill_request_present) begin
                    if (!fill_request_is_prefetch && runtime_prefetch_throttle_enable) begin
                        miss_throttle_count_reg <= runtime_prefetch_throttle_cycles_eff;
                    end
                    if (!fill_request_is_prefetch) begin
                        sample_miss_pending_reg <= 1'b0;
                        fifo_delete_req_valid_reg <= 1'b1;
                        fifo_delete_req_tile_x_reg <= fill_request_tile_x;
                        fifo_delete_req_tile_y_reg <= fill_request_tile_y;
                    end else if (!fill_request_is_analytic) begin
                        normal_prefetch_pending_reg <= 1'b0;
                    end
                    fill_req_valid_reg <= 1'b1;
                    fill_req_tile_x_reg <= fill_request_tile_x;
                    fill_req_tile_y_reg <= fill_request_tile_y;
                    fill_req_run_len_reg <= fill_request_run_len;
                    fill_req_is_prefetch_reg <= fill_request_is_prefetch;
                    fill_req_is_analytic_reg <= fill_request_is_analytic;
                    for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                        if (i < fill_request_run_len) begin
                            fill_req_set_reg[i] <= fill_request_set[i];
                            fill_req_way_reg[i] <= fill_request_way[i];
                            fill_req_evict_unused_reg[i] <= fill_request_evict_unused[i];
                        end
                    end
                end

                if (fill_req_valid_reg && !fill_plan_valid_reg) begin
                    fill_plan_valid_reg <= 1'b1;
                    fill_plan_tile_x_reg <= fill_req_tile_x_reg;
                    fill_plan_tile_y_reg <= fill_req_tile_y_reg;
                    fill_plan_run_len_reg <= fill_req_run_len_reg;
                    fill_plan_is_prefetch_reg <= fill_req_is_prefetch_reg;
                    fill_plan_is_analytic_reg <= fill_req_is_analytic_reg;
                    for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                        if (i < fill_req_run_len_reg) begin
                            fill_plan_set_reg[i] <= fill_req_set_reg[i];
                            fill_plan_way_reg[i] <= fill_req_way_reg[i];
                            fill_plan_evict_unused_reg[i] <= fill_req_evict_unused_reg[i];
                        end
                    end
                    fill_req_valid_reg <= 1'b0;
                end

                if (normal_prefetch_drop) begin
                    normal_prefetch_pending_reg <= 1'b0;
                end

                if (fill_plan_valid_reg && !fill_active_reg && !read_issue_pending_reg && !row_inflight_reg) begin
                    plan_evict_unused_count = '0;
                    fill_active_reg <= 1'b1;
                    fill_tile_x_reg <= fill_plan_tile_x_reg;
                    fill_tile_y_reg <= fill_plan_tile_y_reg;
                    fill_run_len_reg <= fill_plan_run_len_reg;
                    fill_is_prefetch_reg <= fill_plan_is_prefetch_reg;
                    fill_is_analytic_reg <= fill_plan_is_analytic_reg;
                    if (fill_plan_run_len_reg <= RUN_LEN_W'(MERGE_MAX_X)) begin
                        stat_merge_len_hist_reg[fill_plan_run_len_reg] <=
                            stat_merge_len_hist_reg[fill_plan_run_len_reg] + 1'b1;
                    end
                    for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                        fill_set_reg[i] <= fill_plan_set_reg[i];
                        fill_way_reg[i] <= fill_plan_way_reg[i];
                        if (i < fill_plan_run_len_reg) begin
                            if (fill_plan_evict_unused_reg[i]) begin
                                plan_evict_unused_count = plan_evict_unused_count + 1'b1;
                            end
                            slot_idx = sector_slot(fill_plan_set_reg[i], fill_plan_way_reg[i]);
                            sector_valid_reg[slot_idx] <= 1'b0;
                            sector_prefetched_reg[slot_idx] <= 1'b0;
                            sector_prefetch_fill_reg[slot_idx] <= 1'b0;
                            sector_used_reg[slot_idx] <= 1'b0;
                        end
                    end

                    start_x_byte = fill_plan_tile_x_reg * BASE_TILE_W;
                    start_y_row = fill_plan_tile_y_reg * BASE_TILE_H;
                    rem_width = (start_x_byte < cfg_src_w_reg) ? (cfg_src_w_reg - start_x_byte) : 32'd0;
                    rem_rows = (start_y_row < cfg_src_h_reg) ? (cfg_src_h_reg - start_y_row) : 32'd0;
                    plan_width = fill_plan_run_len_reg * BASE_TILE_W;
                    if (plan_width > rem_width) begin
                        plan_width = rem_width;
                    end
                    plan_rows = (rem_rows > BASE_TILE_H) ? 16'(BASE_TILE_H) : 16'(rem_rows);

                    fill_read_width_reg <= plan_width;
                    fill_read_rows_reg <= plan_rows;
                    fill_stream_col_reg <= '0;
                    fill_stream_row_reg <= '0;
                    read_addr_reg <= cfg_src_base_addr_reg + start_y_row * cfg_src_stride_reg + start_x_byte;
                    read_row_stride_reg <= cfg_src_stride_reg;
                    read_byte_count_reg <= plan_width;
                    read_row_count_reg <= plan_rows;
                    read_issue_pending_reg <= (plan_width != 0) && (plan_rows != 0);
                    if (fill_plan_is_prefetch_reg) begin
                        stat_prefetch_starts_reg <= stat_prefetch_starts_reg + 1'b1;
                    end else begin
                        stat_misses_reg <= stat_misses_reg + 1'b1;
                    end
                    if (fill_plan_is_analytic_reg) begin
                        stat_analytic_fills_reg <= stat_analytic_fills_reg + 1'b1;
                    end else if (fill_plan_is_prefetch_reg) begin
                        stat_normal_prefetch_fills_reg <= stat_normal_prefetch_fills_reg + 1'b1;
                    end
                    if (plan_evict_unused_count != '0) begin
                        stat_prefetch_evicted_unused_reg <=
                            stat_prefetch_evicted_unused_reg + plan_evict_unused_count;
                    end
                    if ((plan_width == 0) || (plan_rows == 0)) begin
                        fill_active_reg <= 1'b0;
                    end
                    fill_plan_valid_reg <= 1'b0;
                end

                if (read_issue_pending_reg && read_start_ready && !read_busy) begin
                    read_issue_pending_reg <= 1'b0;
                    row_inflight_reg <= 1'b1;
                    stat_read_starts_reg <= stat_read_starts_reg + 1'b1;
                    stat_read_bytes_total_reg <= stat_read_bytes_total_reg + (64'(read_byte_count_reg) * 64'(read_row_count_reg));
                end

                if (fill_active_reg && row_inflight_reg && in_valid && in_ready) begin
                    stream_sector_idx = RUN_LEN_W'(fill_stream_col_reg >> TILE_X_SHIFT);
                    stream_local_col = BASE_COL_W'(fill_stream_col_reg & (BASE_TILE_W - 1));
                    stream_local_row = BASE_ROW_W'(fill_stream_row_reg);
                    if (stream_sector_idx < fill_run_len_reg) begin
                        slot_idx = sector_slot(fill_set_reg[stream_sector_idx], fill_way_reg[stream_sector_idx]);
                        sector_mem[slot_idx][sector_pixel_lsb(stream_local_row, stream_local_col) +: PIXEL_W] <= in_data;
                    end

                    next_stream_col = fill_stream_col_reg + 1'b1;
                    next_stream_row = fill_stream_row_reg;
                    if (in_row_last || (next_stream_col >= fill_read_width_reg)) begin
                        next_stream_col = '0;
                        next_stream_row = fill_stream_row_reg + 1'b1;
                    end
                    fill_stream_col_reg <= next_stream_col;
                    fill_stream_row_reg <= next_stream_row;
                end

                if (fill_active_reg && row_inflight_reg && read_done) begin
                    row_inflight_reg <= 1'b0;
                    fill_active_reg <= 1'b0;
                    touch_counter_reg <= touch_counter_reg + 1'b1;
                    for (i = 0; i < MERGE_MAX_X; i = i + 1) begin
                        if (i < fill_run_len_reg) begin
                            plan_tile_x_i = fill_tile_x_reg + SECTOR_X_W'(i);
                            slot_idx = sector_slot(fill_set_reg[i], fill_way_reg[i]);
                            sector_valid_reg[slot_idx] <= 1'b1;
                            sector_prefetched_reg[slot_idx] <= fill_is_prefetch_reg;
                            sector_prefetch_fill_reg[slot_idx] <= fill_is_prefetch_reg;
                            sector_used_reg[slot_idx] <= 1'b0;
                            sector_tag_x_reg[slot_idx] <= plan_tile_x_i;
                            sector_tag_y_reg[slot_idx] <= fill_tile_y_reg;
                            sector_last_touch_reg[slot_idx] <= touch_counter_reg + 1'b1;
                        end
                    end
                end
            end
        end
    end
    end

    wire _unused_compat = &{1'b0, cfg_rot_sin_q16_reg[0], cfg_rot_cos_q16_reg[0],
                            last_scan_dir_x_reg[0], last_scan_dir_y_reg[0],
                            scan_dir_x[0], scan_dir_y[0], TILE_W[0], TILE_H[0], TILE_NUM[0]};

endmodule
