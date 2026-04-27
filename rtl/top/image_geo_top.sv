`timescale 1ns/1ps

`ifndef IMAGE_GEO_SRC_TILE_NUM
`define IMAGE_GEO_SRC_TILE_NUM 24
`endif

`ifndef IMAGE_GEO_SRC_TILE_W
`define IMAGE_GEO_SRC_TILE_W 64
`endif

`ifndef IMAGE_GEO_SRC_TILE_H
`define IMAGE_GEO_SRC_TILE_H 8
`endif

`ifndef IMAGE_GEO_RD_BURST_MAX_LEN
`define IMAGE_GEO_RD_BURST_MAX_LEN 16
`endif

`ifndef IMAGE_GEO_RD_MAX_OUTSTANDING_BURSTS
`define IMAGE_GEO_RD_MAX_OUTSTANDING_BURSTS 4
`endif

`ifndef IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS
`define IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS 16
`endif

`ifndef IMAGE_GEO_RD_FIFO_DEPTH_WORDS
`define IMAGE_GEO_RD_FIFO_DEPTH_WORDS 64
`endif

`ifndef IMAGE_GEO_WR_BURST_MAX_LEN
`define IMAGE_GEO_WR_BURST_MAX_LEN 16
`endif

`ifndef IMAGE_GEO_WR_FIFO_DEPTH_PIXELS
`define IMAGE_GEO_WR_FIFO_DEPTH_PIXELS 256
`endif

`ifndef SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS
`define SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS 64
`endif

`ifndef SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH
`define SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH 32
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

// 椤跺眰鑱岃矗锛?
// 1. 鎻愪緵 AXI-Lite 瀵勫瓨鍣ㄦ帴鍙ｏ紝鐢ㄤ簬閰嶇疆婧愬浘鍜岀洰鏍囧浘鐨勫湴鍧€銆佸昂瀵搞€佹闀夸互鍙婂惎鍔ㄦ帶鍒躲€?
// 2. 涓叉帴 DDR 璇诲啓銆佹簮琛岀紦瀛樸€乥ilinear core 鍜岀粨鏋滃啓鍥烇紝褰㈡垚瀹屾暣鐨勭缉鏀炬暟鎹€氳矾銆?
// 3. 姹囨€诲畬鎴愬拰閿欒鐘舵€侊紝骞堕€氳繃涓柇涓庣姸鎬佸瘎瀛樺櫒瀵瑰鍙嶉褰撳墠浠诲姟杩涘害銆?
module image_geo_top #(
    parameter int AXIL_ADDR_W = 12,
    parameter int AXIL_DATA_W = 32,
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32,
    parameter int AXI_ID_W    = 4,
    parameter int PIXEL_W     = 8,
    parameter int MAX_SRC_W   = 7200,
    parameter int MAX_SRC_H   = 7200,
    parameter int MAX_DST_W   = 600,
    parameter int MAX_DST_H   = 600,
    parameter int LINE_NUM    = 2
) (
    input  logic                         axi_clk,
    input  logic                         axi_rstn,
    input  logic                         core_clk,
    input  logic                         core_rstn,

    output logic                         irq,

    input  logic [AXIL_ADDR_W-1:0]       s_axi_ctrl_awaddr,
    input  logic [2:0]                   s_axi_ctrl_awprot,
    input  logic                         s_axi_ctrl_awvalid,
    output logic                         s_axi_ctrl_awready,
    input  logic [AXIL_DATA_W-1:0]       s_axi_ctrl_wdata,
    input  logic [(AXIL_DATA_W/8)-1:0]   s_axi_ctrl_wstrb,
    input  logic                         s_axi_ctrl_wvalid,
    output logic                         s_axi_ctrl_wready,
    output logic [1:0]                   s_axi_ctrl_bresp,
    output logic                         s_axi_ctrl_bvalid,
    input  logic                         s_axi_ctrl_bready,
    input  logic [AXIL_ADDR_W-1:0]       s_axi_ctrl_araddr,
    input  logic [2:0]                   s_axi_ctrl_arprot,
    input  logic                         s_axi_ctrl_arvalid,
    output logic                         s_axi_ctrl_arready,
    output logic [AXIL_DATA_W-1:0]       s_axi_ctrl_rdata,
    output logic [1:0]                   s_axi_ctrl_rresp,
    output logic                         s_axi_ctrl_rvalid,
    input  logic                         s_axi_ctrl_rready,

    // DDR璇诲彛
    output logic [AXI_ID_W-1:0]          m_axi_rd_arid,
    output logic [AXI_ADDR_W-1:0]        m_axi_rd_araddr,
    output logic [7:0]                   m_axi_rd_arlen,
    output logic [2:0]                   m_axi_rd_arsize,
    output logic [1:0]                   m_axi_rd_arburst,
    output logic                         m_axi_rd_arlock,
    output logic [3:0]                   m_axi_rd_arcache,
    output logic [2:0]                   m_axi_rd_arprot,
    output logic [3:0]                   m_axi_rd_arqos,
    output logic [3:0]                   m_axi_rd_arregion,
    output logic                         m_axi_rd_arvalid,
    input  logic                         m_axi_rd_arready,
    input  logic [AXI_ID_W-1:0]          m_axi_rd_rid,
    input  logic [AXI_DATA_W-1:0]        m_axi_rd_rdata,
    input  logic [1:0]                   m_axi_rd_rresp,
    input  logic                         m_axi_rd_rlast,
    input  logic                         m_axi_rd_rvalid,
    output logic                         m_axi_rd_rready,

    // DDR鍐欏彛
    output logic [AXI_ID_W-1:0]          m_axi_wr_awid,
    output logic [AXI_ADDR_W-1:0]        m_axi_wr_awaddr,
    output logic [7:0]                   m_axi_wr_awlen,
    output logic [2:0]                   m_axi_wr_awsize,
    output logic [1:0]                   m_axi_wr_awburst,
    output logic                         m_axi_wr_awlock,
    output logic [3:0]                   m_axi_wr_awcache,
    output logic [2:0]                   m_axi_wr_awprot,
    output logic [3:0]                   m_axi_wr_awqos,
    output logic [3:0]                   m_axi_wr_awregion,
    output logic                         m_axi_wr_awvalid,
    input  logic                         m_axi_wr_awready,
    output logic [AXI_DATA_W-1:0]        m_axi_wr_wdata,
    output logic [(AXI_DATA_W/8)-1:0]    m_axi_wr_wstrb,
    output logic                         m_axi_wr_wlast,
    output logic                         m_axi_wr_wvalid,
    input  logic                         m_axi_wr_wready,
    input  logic [AXI_ID_W-1:0]          m_axi_wr_bid,
    input  logic [1:0]                   m_axi_wr_bresp,
    input  logic                         m_axi_wr_bvalid,
    output logic                         m_axi_wr_bready
);

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    localparam logic [AXIL_ADDR_W-1:0] REG_CTRL_ADDR       = 12'h000;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_BASE_ADDR   = 12'h004;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_BASE_ADDR   = 12'h008;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_STRIDE_ADDR = 12'h00C;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_STRIDE_ADDR = 12'h010;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_SIZE_ADDR   = 12'h014;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_SIZE_ADDR   = 12'h018;
    localparam logic [AXIL_ADDR_W-1:0] REG_STATUS_ADDR     = 12'h01C;
    localparam logic [AXIL_ADDR_W-1:0] REG_ROT_SIN_ADDR    = 12'h020; // 鏃嬭浆瑙掑害鐨勬寮﹀€硷紝閲囩敤 Q16 瀹氱偣鏍煎紡琛ㄧず锛岃寖鍥?[-1, 1) 鏄犲皠鍒?[-65536, 65535] 涔嬮棿銆?
    localparam logic [AXIL_ADDR_W-1:0] REG_ROT_COS_ADDR    = 12'h024; // 鏃嬭浆瑙掑害鐨勪綑寮﹀€硷紝閲囩敤 Q16 瀹氱偣鏍煎紡琛ㄧず锛岃寖鍥?[-1, 1) 鏄犲皠鍒?[-65536, 65535] 涔嬮棿銆?
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_READS_ADDR = 12'h028;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_MISSES_ADDR = 12'h02C;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_PREFETCH_ADDR = 12'h030;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_PREFETCH_HIT_ADDR = 12'h034;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_CTRL_ADDR = 12'h038;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_STATS_EXT_BASE_ADDR = 12'h040;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_CTRL_ADDR = 12'h140;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_LEAD_ADDR = 12'h144;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_MERGE_ADDR = 12'h148;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_FIFO_ADDR = 12'h14C;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_THROTTLE_ADDR = 12'h150;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_STATUS_ADDR = 12'h154;
    localparam int CACHE_STATS_HIST_BINS = 17;
    localparam int CACHE_STATS_WORDS = 64;
    localparam int CACHE_STATS_PAYLOAD_W = CACHE_STATS_WORDS * 32;
    localparam int CACHE_STAT_VERSION_WORD = 0;
    localparam int CACHE_STAT_SNAPSHOT_ID_WORD = 1;
    localparam int CACHE_STAT_FRAME_CYCLES_WORD = 2;
    localparam int CACHE_STAT_TOTAL_CYCLES_WORD = 3;
    localparam int CACHE_STAT_SAMPLE_REQ_WORD = 4;
    localparam int CACHE_STAT_SAMPLE_ACCEPT_WORD = 5;
    localparam int CACHE_STAT_SAMPLE_STALL_WORD = 6;
    localparam int CACHE_STAT_READ_STARTS_WORD = 7;
    localparam int CACHE_STAT_MISSES_WORD = 8;
    localparam int CACHE_STAT_PREFETCH_STARTS_WORD = 9;
    localparam int CACHE_STAT_PREFETCH_HITS_WORD = 10;
    localparam int CACHE_STAT_ANALYTIC_CANDIDATES_WORD = 11;
    localparam int CACHE_STAT_ANALYTIC_DUPLICATES_WORD = 12;
    localparam int CACHE_STAT_ANALYTIC_BLOCKED_WORD = 13;
    localparam int CACHE_STAT_ANALYTIC_FILLS_WORD = 14;
    localparam int CACHE_STAT_NORMAL_PREFETCH_FILLS_WORD = 15;
    localparam int CACHE_STAT_PREFETCH_EVICT_UNUSED_WORD = 16;
    localparam int CACHE_STAT_FIFO_MAX_WORD = 17;
    localparam int CACHE_STAT_READ_BUSY_CYCLES_WORD = 18;
    localparam int CACHE_STAT_READ_BYTES_LOW_WORD = 19;
    localparam int CACHE_STAT_READ_BYTES_HIGH_WORD = 20;
    localparam int CACHE_STAT_USEFUL_SOURCE_SECTORS_WORD = 21;
    localparam int CACHE_STAT_REPLACEMENT_FAIL_WORD = 22;
    localparam int CACHE_STAT_MISS_LATENCY_MIN_WORD = 23;
    localparam int CACHE_STAT_MISS_LATENCY_MAX_WORD = 24;
    localparam int CACHE_STAT_MISS_LATENCY_SUM_LOW_WORD = 25;
    localparam int CACHE_STAT_MISS_LATENCY_SUM_HIGH_WORD = 26;
    localparam int CACHE_STAT_MISS_LATENCY_COUNT_WORD = 27;
    localparam int CACHE_STAT_MERGE_HIST_BASE_WORD = 28;
    localparam int CACHE_STAT_OVERRUN_WORD = CACHE_STAT_MERGE_HIST_BASE_WORD + CACHE_STATS_HIST_BINS;
    localparam int CACHE_STAT_SCHED_POLICY_WORD = 46;
    localparam int CACHE_STAT_SCHED_LEAD_WORD = 47;
    localparam int CACHE_STAT_SCHED_MERGE_WORD = 48;
    localparam int CACHE_STAT_SCHED_FIFO_WORD = 49;
    localparam int CACHE_STAT_SCHED_THROTTLE_WORD = 50;
    localparam int CACHE_STAT_FIFO_HEAD_RUN_WORD = 51;
    localparam int CACHE_STAT_FIFO_SAME_ROW_ADJ_WORD = 52;
    localparam int CACHE_STAT_FIFO_REVERSE_X_ADJ_WORD = 53;
    localparam int CACHE_STAT_MERGE_OPPORTUNITY_MISSED_WORD = 54;
    localparam int SCHED_DEFAULT_POLICY =
        ((`SRC_TILE_CACHE_ENABLE_MERGE_MIN != 0) ? 1 : 0) |
        ((`SRC_TILE_CACHE_ENABLE_PREFETCH_THROTTLE != 0) ? 2 : 0);

    localparam int LINE_SEL_W   = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;
    localparam int SRC_X_W      = $clog2(MAX_SRC_W+1);
    localparam int SRC_Y_W      = $clog2(MAX_SRC_H+1);
    localparam int DST_X_W      = $clog2(MAX_DST_W+1);
    localparam int DST_Y_W      = $clog2(MAX_DST_H+1);
    localparam int CORE_SRC_Y_W = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;
    localparam int SRC_LAST_X_W = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int SRC_LAST_Y_W = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;
    localparam int GEOM_COORD_W = 48;
    localparam int GEOM_ID_W    = 8;

    logic axi_sys_rst_async;
    logic core_sys_rst_async;
    logic axi_sys_rst;
    logic core_sys_rst;

    logic axil_aw_hold_valid_reg;
    logic axil_w_hold_valid_reg;
    logic axil_ar_hold_valid_reg;
    logic [AXIL_ADDR_W-1:0] axil_awaddr_reg;
    logic [AXIL_DATA_W-1:0] axil_wdata_reg;
    logic [(AXIL_DATA_W/8)-1:0] axil_wstrb_reg;
    logic [AXIL_ADDR_W-1:0] axil_araddr_reg;
    logic [AXIL_DATA_W-1:0] axil_rdata_next;
    logic                   axil_read_addr_hit;

    logic [AXI_ADDR_W-1:0] reg_src_base_addr;
    logic [AXI_ADDR_W-1:0] reg_dst_base_addr;
    logic [AXI_ADDR_W-1:0] reg_src_stride;
    logic [AXI_ADDR_W-1:0] reg_dst_stride;
    logic [15:0]           reg_src_w;
    logic [15:0]           reg_src_h;
    logic [15:0]           reg_dst_w;
    logic [15:0]           reg_dst_h;
    logic signed [31:0]    reg_rot_sin_q16;
    logic signed [31:0]    reg_rot_cos_q16;
    logic                  reg_cache_prefetch_en;
    logic [15:0]           reg_sched_lead_pixels;
    logic [7:0]            reg_sched_merge_max_x_eff;
    logic [7:0]            reg_sched_merge_min_x;
    logic [15:0]           reg_sched_fifo_depth_eff;
    logic [15:0]           reg_sched_fifo_age_limit;
    logic [15:0]           reg_sched_throttle_cycles;
    logic [1:0]            reg_sched_policy;
    logic                  reg_irq_en;
    logic                  start_pulse_reg;
    logic                  done_sticky_reg;
    logic                  error_sticky_reg;
    logic [AXI_ADDR_W-1:0] core_src_base_addr;
    logic [AXI_ADDR_W-1:0] core_dst_base_addr;
    logic [AXI_ADDR_W-1:0] core_src_stride;
    logic [AXI_ADDR_W-1:0] core_dst_stride;
    logic [15:0]           core_src_w_cfg;
    logic [15:0]           core_src_h_cfg;
    logic [15:0]           core_dst_w_cfg;
    logic [15:0]           core_dst_h_cfg;
    logic signed [31:0]    core_rot_sin_q16;
    logic signed [31:0]    core_rot_cos_q16;
    logic                  core_cache_prefetch_en;
    logic [15:0]           core_sched_lead_pixels;
    logic [7:0]            core_sched_merge_max_x_eff;
    logic [7:0]            core_sched_merge_min_x;
    logic [15:0]           core_sched_fifo_depth_eff;
    logic [15:0]           core_sched_fifo_age_limit;
    logic [15:0]           core_sched_throttle_cycles;
    logic [1:0]            core_sched_policy;
    logic                  core_cfg_valid;
    logic                  core_cfg_ready;
    logic                  core_cfg_fire;
    logic                  cfg_ready_axi;
    logic                  geom_cfg_ready_core;
    logic                  ctrl_busy_core;
    logic                  ctrl_done_core;
    logic                  ctrl_error_core;
    logic                  ctrl_busy_axi_reg;
    logic                  ctrl_result_valid_axi;
    logic                  ctrl_result_done_axi;
    logic                  ctrl_result_error_axi;

    logic                  read_busy_core;
    logic                  read_done_core;
    logic                  read_error_core;
    logic [PIXEL_W-1:0]    read_out_data;
    logic                  read_out_valid;
    logic                  read_out_row_last;
    logic                  read_out_ready;

    logic                  core_start;
    logic                  core_busy;
    logic                  core_done;
    logic                  core_error;
    logic                  geom_start;
    logic                  geom_valid;
    logic                  geom_busy;
    logic                  geom_error;
    logic [GEOM_ID_W-1:0] geom_next_id_reg;
    logic [GEOM_ID_W-1:0] geom_pending_id_reg;
    logic [GEOM_ID_W-1:0] geom_active_id_reg;
    logic [GEOM_ID_W-1:0] geom_result_id;
    logic                  geom_pending_valid_reg;
    logic                  geom_active_valid_reg;
    logic                  geom_ready_reg;
    logic                  geom_error_hold_reg;
    logic [SRC_X_W-1:0]   geom_src_w_cfg_reg;
    logic [SRC_Y_W-1:0]   geom_src_h_cfg_reg;
    logic [DST_X_W-1:0]   geom_dst_w_cfg_reg;
    logic [DST_Y_W-1:0]   geom_dst_h_cfg_reg;
    logic signed [31:0]   geom_rot_sin_q16_reg;
    logic signed [31:0]   geom_rot_cos_q16_reg;
    logic signed [31:0]   geom_scale_x_q16;
    logic signed [31:0]   geom_scale_y_q16;
    logic signed [GEOM_COORD_W-1:0] geom_step_x_x;
    logic signed [GEOM_COORD_W-1:0] geom_step_y_x;
    logic signed [GEOM_COORD_W-1:0] geom_step_x_y;
    logic signed [GEOM_COORD_W-1:0] geom_step_y_y;
    logic signed [GEOM_COORD_W-1:0] geom_row0_x;
    logic signed [GEOM_COORD_W-1:0] geom_row0_y;
    logic [SRC_LAST_X_W-1:0] geom_src_x_last;
    logic [SRC_LAST_Y_W-1:0] geom_src_y_last;
    logic signed [GEOM_COORD_W-1:0] geom_src_x_max_q16;
    logic signed [GEOM_COORD_W-1:0] geom_src_y_max_q16;
    logic signed [GEOM_COORD_W-1:0] geom_hold_step_x_x_reg;
    logic signed [GEOM_COORD_W-1:0] geom_hold_step_y_x_reg;
    logic signed [GEOM_COORD_W-1:0] geom_hold_step_x_y_reg;
    logic signed [GEOM_COORD_W-1:0] geom_hold_step_y_y_reg;
    logic signed [GEOM_COORD_W-1:0] geom_hold_row0_x_reg;
    logic signed [GEOM_COORD_W-1:0] geom_hold_row0_y_reg;
    logic [SRC_LAST_X_W-1:0] geom_hold_src_x_last_reg;
    logic [SRC_LAST_Y_W-1:0] geom_hold_src_y_last_reg;
    logic signed [GEOM_COORD_W-1:0] geom_hold_src_x_max_q16_reg;
    logic signed [GEOM_COORD_W-1:0] geom_hold_src_y_max_q16_reg;
    logic                  src_cache_error;
    logic                  cache_read_start;
    logic [AXI_ADDR_W-1:0] cache_read_addr;
    logic [31:0]           cache_read_row_stride;
    logic [31:0]           cache_read_byte_count;
    logic [15:0]           cache_read_row_count;
    logic                  cache_read_start_ready;
    logic                  cache_read_busy;
    logic                  cache_read_done;
    logic                  cache_read_error;
    logic                  sample_req_valid;
    logic                  sample_req_ready;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x0;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y0;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x1;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y1;
    logic [PIXEL_W-1:0]    cache_sample_p00;
    logic [PIXEL_W-1:0]    cache_sample_p01;
    logic [PIXEL_W-1:0]    cache_sample_p10;
    logic [PIXEL_W-1:0]    cache_sample_p11;
    logic                  cache_sample_rsp_valid;
    logic [PIXEL_W-1:0]    sample_p00;
    logic [PIXEL_W-1:0]    sample_p01;
    logic [PIXEL_W-1:0]    sample_p10;
    logic [PIXEL_W-1:0]    sample_p11;
    logic                  sample_rsp_valid;
    logic signed [1:0]     sample_scan_dir_x;
    logic signed [1:0]     sample_scan_dir_y;
    logic                  sample_scan_dir_valid;
    logic [31:0]           src_cache_stat_read_starts;
    logic [31:0]           src_cache_stat_misses;
    logic [31:0]           src_cache_stat_prefetch_starts;
    logic [31:0]           src_cache_stat_prefetch_hits;
    logic [31:0]           src_cache_stat_analytic_candidates;
    logic [31:0]           src_cache_stat_analytic_duplicates;
    logic [31:0]           src_cache_stat_analytic_blocked;
    logic [31:0]           src_cache_stat_analytic_fills;
    logic [31:0]           src_cache_stat_prefetch_evicted_unused;
    logic [31:0]           src_cache_stat_total_cycles;
    logic [31:0]           src_cache_stat_sample_req_count;
    logic [31:0]           src_cache_stat_sample_accept_count;
    logic [31:0]           src_cache_stat_sample_stall_cycles;
    logic [31:0]           src_cache_stat_normal_prefetch_fills;
    logic [31:0]           src_cache_stat_fifo_max_occupancy;
    logic [31:0]           src_cache_stat_read_busy_cycles;
    logic [31:0]           src_cache_stat_read_bytes_total_low;
    logic [31:0]           src_cache_stat_read_bytes_total_high;
    logic [31:0]           src_cache_stat_useful_source_sectors;
    logic [31:0]           src_cache_stat_replacement_fail_cycles;
    logic [31:0]           src_cache_stat_miss_service_latency_min;
    logic [31:0]           src_cache_stat_miss_service_latency_max;
    logic [31:0]           src_cache_stat_miss_service_latency_sum_low;
    logic [31:0]           src_cache_stat_miss_service_latency_sum_high;
    logic [31:0]           src_cache_stat_miss_service_latency_count;
    logic [(CACHE_STATS_HIST_BINS*32)-1:0] src_cache_stat_merge_len_hist_flat;
    logic [31:0]           src_cache_stat_fifo_head_run_len;
    logic [31:0]           src_cache_stat_fifo_same_row_adjacent_count;
    logic [31:0]           src_cache_stat_fifo_reverse_x_adjacent_count;
    logic [31:0]           src_cache_stat_merge_opportunity_missed_count;
    logic [31:0]           cache_stats_snapshot_id_core_reg;
    logic [31:0]           frame_total_cycles_core_reg;
    logic                  frame_cycle_active_core_reg;
    logic                  cache_stats_event_core;
    logic                  cache_stats_ready_core;
    logic                  cache_stats_valid_axi;
    logic [CACHE_STATS_PAYLOAD_W-1:0] cache_stats_payload_core;
    logic [CACHE_STATS_PAYLOAD_W-1:0] cache_stats_pending_payload_reg;
    logic [CACHE_STATS_PAYLOAD_W-1:0] cache_stats_payload_axi;
    logic                  cache_stats_pending_valid_reg;
    logic                  cache_stats_overrun_reg;
    (* ASYNC_REG = "TRUE" *) logic cache_stats_overrun_axi_sync1_reg;
    (* ASYNC_REG = "TRUE" *) logic cache_stats_overrun_axi_sync2_reg;
    logic                  ctrl_result_ready_core;
    logic                  core_pix_valid;
    logic                  core_pix_ready;
    logic [PIXEL_W-1:0]    core_pix_data;
    logic                  core_pix_pipe_valid_reg;
    logic [PIXEL_W-1:0]    core_pix_pipe_data_reg;
    logic                  row_in_valid;
    logic [PIXEL_W-1:0]    row_in_data;
    logic                  row_in_ready;
    logic                  core_row_done;

    logic                           row_start;
    logic [DST_X_W-1:0]             row_pixel_count;
    logic                           row_busy;
    logic                           row_done_fill;
    logic                           row_error;
    logic                           row_out_start;
    logic [PIXEL_W-1:0]             row_out_data;
    logic                           row_out_valid;
    logic                           row_out_ready;
    logic                           row_out_done;

    logic                  write_start;
    logic [AXI_ADDR_W-1:0] write_addr;
    logic [31:0]           write_byte_count;
    logic                  write_busy;
    logic                  write_done;
    logic                  write_error;
    logic                    unused_signals;

    taxi_axi_if #(
        .DATA_W(AXI_DATA_W),
        .ADDR_W(AXI_ADDR_W),
        .ID_W(AXI_ID_W)
    ) m_axi_rd_if ();

    taxi_axi_if #(
        .DATA_W(AXI_DATA_W),
        .ADDR_W(AXI_ADDR_W),
        .ID_W(AXI_ID_W)
    ) m_axi_wr_if ();

    initial begin
        if (AXIL_DATA_W != 32) $error("image_geo_top currently expects AXI-Lite data width = 32.");
        if (AXI_DATA_W != 32)  $error("image_geo_top currently expects AXI data width = 32.");
        if (PIXEL_W != 8)      $error("image_geo_top currently expects PIXEL_W = 8.");
    end

    // 绯荤粺澶嶄綅鐢?AXI 渚т綆鏈夋晥澶嶄綅缈昏浆寰楀埌锛屾帶鍒跺瘎瀛樺櫒涓庝富鏁版嵁閾捐矾鍏辩敤璇ユ椂閽熷煙銆?
    assign axi_sys_rst_async = ~axi_rstn;
    assign core_sys_rst_async = ~core_rstn;

    reset_sync u_axi_reset_sync (
        .clk(axi_clk),
        .async_rst(axi_sys_rst_async),
        .sync_rst(axi_sys_rst)
    );

    reset_sync u_core_reset_sync (
        .clk(core_clk),
        .async_rst(core_sys_rst_async),
        .sync_rst(core_sys_rst)
    );

    assign s_axi_ctrl_awready = !axil_aw_hold_valid_reg && !s_axi_ctrl_bvalid;
    assign s_axi_ctrl_wready  = !axil_w_hold_valid_reg && !s_axi_ctrl_bvalid;
    assign s_axi_ctrl_arready = !axil_ar_hold_valid_reg && !s_axi_ctrl_rvalid;

    // AXI-Lite 璇婚€氳矾锛氭牴鎹瘎瀛樺櫒鍦板潃杩斿洖褰撳墠閰嶇疆銆佺姸鎬佷互鍙婄粺璁′俊鎭€?
    always_comb begin
        int cache_stats_idx;

        axil_rdata_next    = '0;
        axil_read_addr_hit = 1'b1;
        cache_stats_idx    = 0;

        case (axil_araddr_reg)
            REG_CTRL_ADDR: begin
                axil_rdata_next[0] = 1'b0;
                axil_rdata_next[1] = reg_irq_en;
            end
            REG_SRC_BASE_ADDR: begin
                axil_rdata_next = reg_src_base_addr;
            end
            REG_DST_BASE_ADDR: begin
                axil_rdata_next = reg_dst_base_addr;
            end
            REG_SRC_STRIDE_ADDR: begin
                axil_rdata_next = reg_src_stride;
            end
            REG_DST_STRIDE_ADDR: begin
                axil_rdata_next = reg_dst_stride;
            end
            REG_SRC_SIZE_ADDR: begin
                axil_rdata_next[15:0]  = reg_src_w;
                axil_rdata_next[31:16] = reg_src_h;
            end
            REG_DST_SIZE_ADDR: begin
                axil_rdata_next[15:0]  = reg_dst_w;
                axil_rdata_next[31:16] = reg_dst_h;
            end
            REG_STATUS_ADDR: begin
                axil_rdata_next[0] = ctrl_busy_axi_reg;
                axil_rdata_next[1] = done_sticky_reg;
                axil_rdata_next[2] = error_sticky_reg;
                axil_rdata_next[8] = 1'b0;
                axil_rdata_next[9] = 1'b0;
            end
            REG_ROT_SIN_ADDR: begin
                axil_rdata_next = reg_rot_sin_q16;
            end
            REG_ROT_COS_ADDR: begin
                axil_rdata_next = reg_rot_cos_q16;
            end
            REG_CACHE_READS_ADDR: begin
                axil_rdata_next = cache_stats_payload_axi[CACHE_STAT_READ_STARTS_WORD*32 +: 32];
            end
            REG_CACHE_MISSES_ADDR: begin
                axil_rdata_next = cache_stats_payload_axi[CACHE_STAT_MISSES_WORD*32 +: 32];
            end
            REG_CACHE_PREFETCH_ADDR: begin
                axil_rdata_next = cache_stats_payload_axi[CACHE_STAT_PREFETCH_STARTS_WORD*32 +: 32];
            end
            REG_CACHE_PREFETCH_HIT_ADDR: begin
                axil_rdata_next = cache_stats_payload_axi[CACHE_STAT_PREFETCH_HITS_WORD*32 +: 32];
            end
            REG_CACHE_CTRL_ADDR: begin
                axil_rdata_next[0] = reg_cache_prefetch_en;
            end
            REG_SCHED_CTRL_ADDR: begin
                axil_rdata_next[0] = reg_cache_prefetch_en;
                axil_rdata_next[9:8] = reg_sched_policy;
            end
            REG_SCHED_LEAD_ADDR: begin
                axil_rdata_next[15:0] = reg_sched_lead_pixels;
            end
            REG_SCHED_MERGE_ADDR: begin
                axil_rdata_next[7:0] = reg_sched_merge_max_x_eff;
                axil_rdata_next[15:8] = reg_sched_merge_min_x;
            end
            REG_SCHED_FIFO_ADDR: begin
                axil_rdata_next[15:0] = reg_sched_fifo_depth_eff;
                axil_rdata_next[31:16] = reg_sched_fifo_age_limit;
            end
            REG_SCHED_THROTTLE_ADDR: begin
                axil_rdata_next[15:0] = reg_sched_throttle_cycles;
            end
            REG_SCHED_STATUS_ADDR: begin
                axil_rdata_next[0] = cache_stats_overrun_axi_sync2_reg;
            end
            default: begin
                if ((axil_araddr_reg >= REG_CACHE_STATS_EXT_BASE_ADDR) &&
                    (axil_araddr_reg < (REG_CACHE_STATS_EXT_BASE_ADDR + AXIL_ADDR_W'(CACHE_STATS_WORDS*4))) &&
                    (axil_araddr_reg[1:0] == 2'b00)) begin
                    cache_stats_idx = (axil_araddr_reg - REG_CACHE_STATS_EXT_BASE_ADDR) >> 2;
                    axil_rdata_next = cache_stats_payload_axi[cache_stats_idx*32 +: 32];
                end else begin
                    axil_read_addr_hit = 1'b0;
                end
            end
        endcase
    end

    logic write_fire;
    logic read_fire;

    // AXI-Lite 鍐欓€氳矾锛氱紦瀛?AW/W 閫氶亾鍚庣粺涓€鎻愪氦瀵勫瓨鍣ㄥ啓鍏ワ紝骞剁淮鎶よ鍐欏搷搴旀彙鎵嬨€?
    always_ff @(posedge axi_clk) begin
        if (axi_sys_rst) begin
            axil_aw_hold_valid_reg <= 1'b0;
            axil_w_hold_valid_reg  <= 1'b0;
            axil_ar_hold_valid_reg <= 1'b0;
            axil_awaddr_reg        <= '0;
            axil_wdata_reg         <= '0;
            axil_wstrb_reg         <= '0;
            axil_araddr_reg        <= '0;
            s_axi_ctrl_bvalid      <= 1'b0;
            s_axi_ctrl_bresp       <= AXI_RESP_OKAY;
            s_axi_ctrl_rvalid      <= 1'b0;
            s_axi_ctrl_rresp       <= AXI_RESP_OKAY;
            s_axi_ctrl_rdata       <= '0;

            reg_src_base_addr      <= '0;
            reg_dst_base_addr      <= '0;
            reg_src_stride         <= '0;
            reg_dst_stride         <= '0;
            reg_src_w              <= '0;
            reg_src_h              <= '0;
            reg_dst_w              <= '0;
            reg_dst_h              <= '0;
            reg_rot_sin_q16        <= '0;
            reg_rot_cos_q16        <= 32'sh0001_0000;
            reg_cache_prefetch_en  <= 1'b1;
            reg_sched_lead_pixels <= 16'(`SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS);
            reg_sched_merge_max_x_eff <= 8'(`SRC_TILE_CACHE_MERGE_MAX_X);
            reg_sched_merge_min_x <= 8'(`SRC_TILE_CACHE_MERGE_MIN_X);
            reg_sched_fifo_depth_eff <= 16'(`SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH);
            reg_sched_fifo_age_limit <= 16'(`SRC_TILE_CACHE_FIFO_AGE_LIMIT);
            reg_sched_throttle_cycles <= 16'(`SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES);
            reg_sched_policy <= 2'(SCHED_DEFAULT_POLICY);
            reg_irq_en             <= 1'b0;
            start_pulse_reg        <= 1'b0;
            done_sticky_reg        <= 1'b0;
            error_sticky_reg       <= 1'b0;
            ctrl_busy_axi_reg      <= 1'b0;
        end else begin
            write_fire = axil_aw_hold_valid_reg && axil_w_hold_valid_reg && !s_axi_ctrl_bvalid;
            read_fire  = axil_ar_hold_valid_reg && !s_axi_ctrl_rvalid;
            start_pulse_reg <= 1'b0;

            if (ctrl_result_done_axi) begin
                done_sticky_reg <= 1'b1;
            end
            if (ctrl_result_error_axi) begin
                error_sticky_reg <= 1'b1;
            end
            if (ctrl_result_valid_axi) begin
                ctrl_busy_axi_reg <= 1'b0;
            end

            if (s_axi_ctrl_awready && s_axi_ctrl_awvalid) begin
                axil_aw_hold_valid_reg <= 1'b1;
                axil_awaddr_reg        <= s_axi_ctrl_awaddr;
            end

            if (s_axi_ctrl_wready && s_axi_ctrl_wvalid) begin
                axil_w_hold_valid_reg <= 1'b1;
                axil_wdata_reg        <= s_axi_ctrl_wdata;
                axil_wstrb_reg        <= s_axi_ctrl_wstrb;
            end

            if (s_axi_ctrl_arready && s_axi_ctrl_arvalid) begin
                axil_ar_hold_valid_reg <= 1'b1;
                axil_araddr_reg        <= s_axi_ctrl_araddr;
            end

            if (write_fire) begin
                s_axi_ctrl_bvalid      <= 1'b1;
                s_axi_ctrl_bresp       <= AXI_RESP_OKAY;
                axil_aw_hold_valid_reg <= 1'b0;
                axil_w_hold_valid_reg  <= 1'b0;

                case (axil_awaddr_reg)
                    REG_CTRL_ADDR: begin
                        if (axil_wstrb_reg[0]) begin
                            reg_irq_en <= axil_wdata_reg[1];
                            if (axil_wdata_reg[0] && !ctrl_busy_axi_reg && cfg_ready_axi) begin
                                start_pulse_reg  <= 1'b1;
                                done_sticky_reg  <= 1'b0;
                                error_sticky_reg <= 1'b0;
                                ctrl_busy_axi_reg <= 1'b1;
                            end
                        end
                    end
                    REG_SRC_BASE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_src_base_addr[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_src_base_addr[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_src_base_addr[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_src_base_addr[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_DST_BASE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_dst_base_addr[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_dst_base_addr[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_dst_base_addr[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_dst_base_addr[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_SRC_STRIDE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_src_stride[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_src_stride[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_src_stride[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_src_stride[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_DST_STRIDE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_dst_stride[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_dst_stride[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_dst_stride[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_dst_stride[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_SRC_SIZE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_src_w[7:0]  <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_src_w[15:8] <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_src_h[7:0]  <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_src_h[15:8] <= axil_wdata_reg[31:24];
                    end
                    REG_DST_SIZE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_dst_w[7:0]  <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_dst_w[15:8] <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_dst_h[7:0]  <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_dst_h[15:8] <= axil_wdata_reg[31:24];
                    end
                    REG_STATUS_ADDR: begin
                        if (axil_wstrb_reg[0]) begin
                            if (axil_wdata_reg[1]) done_sticky_reg  <= 1'b0;
                            if (axil_wdata_reg[2]) error_sticky_reg <= 1'b0;
                        end
                    end
                    REG_ROT_SIN_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_rot_sin_q16[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_rot_sin_q16[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_rot_sin_q16[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_rot_sin_q16[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_ROT_COS_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_rot_cos_q16[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_rot_cos_q16[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_rot_cos_q16[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_rot_cos_q16[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_CACHE_CTRL_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_cache_prefetch_en <= axil_wdata_reg[0];
                    end
                    REG_SCHED_CTRL_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_cache_prefetch_en <= axil_wdata_reg[0];
                        if (axil_wstrb_reg[1]) reg_sched_policy <= axil_wdata_reg[9:8];
                    end
                    REG_SCHED_LEAD_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_sched_lead_pixels[7:0] <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_sched_lead_pixels[15:8] <= axil_wdata_reg[15:8];
                    end
                    REG_SCHED_MERGE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_sched_merge_max_x_eff <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_sched_merge_min_x <= axil_wdata_reg[15:8];
                    end
                    REG_SCHED_FIFO_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_sched_fifo_depth_eff[7:0] <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_sched_fifo_depth_eff[15:8] <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_sched_fifo_age_limit[7:0] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_sched_fifo_age_limit[15:8] <= axil_wdata_reg[31:24];
                    end
                    REG_SCHED_THROTTLE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_sched_throttle_cycles[7:0] <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_sched_throttle_cycles[15:8] <= axil_wdata_reg[15:8];
                    end
                    default: begin
                        s_axi_ctrl_bresp <= AXI_RESP_SLVERR;
                    end
                endcase
            end

            if (s_axi_ctrl_bvalid && s_axi_ctrl_bready) begin
                s_axi_ctrl_bvalid <= 1'b0;
            end

            if (read_fire) begin
                s_axi_ctrl_rvalid      <= 1'b1;
                s_axi_ctrl_rresp       <= axil_read_addr_hit ? AXI_RESP_OKAY : AXI_RESP_SLVERR;
                s_axi_ctrl_rdata       <= axil_rdata_next;
                axil_ar_hold_valid_reg <= 1'b0;
            end

            if (s_axi_ctrl_rvalid && s_axi_ctrl_rready) begin
                s_axi_ctrl_rvalid <= 1'b0;
            end
        end
    end

    assign irq = reg_irq_en && (done_sticky_reg || error_sticky_reg);
    assign cache_stats_event_core = ctrl_done_core || ctrl_error_core;

    always_comb begin
        int h;

        cache_stats_payload_core = '0;
        cache_stats_payload_core[CACHE_STAT_VERSION_WORD*32 +: 32] = 32'h0001_0000;
        cache_stats_payload_core[CACHE_STAT_SNAPSHOT_ID_WORD*32 +: 32] = cache_stats_snapshot_id_core_reg + 1'b1;
        cache_stats_payload_core[CACHE_STAT_FRAME_CYCLES_WORD*32 +: 32] = frame_total_cycles_core_reg;
        cache_stats_payload_core[CACHE_STAT_TOTAL_CYCLES_WORD*32 +: 32] = src_cache_stat_total_cycles;
        cache_stats_payload_core[CACHE_STAT_SAMPLE_REQ_WORD*32 +: 32] = src_cache_stat_sample_req_count;
        cache_stats_payload_core[CACHE_STAT_SAMPLE_ACCEPT_WORD*32 +: 32] = src_cache_stat_sample_accept_count;
        cache_stats_payload_core[CACHE_STAT_SAMPLE_STALL_WORD*32 +: 32] = src_cache_stat_sample_stall_cycles;
        cache_stats_payload_core[CACHE_STAT_READ_STARTS_WORD*32 +: 32] = src_cache_stat_read_starts;
        cache_stats_payload_core[CACHE_STAT_MISSES_WORD*32 +: 32] = src_cache_stat_misses;
        cache_stats_payload_core[CACHE_STAT_PREFETCH_STARTS_WORD*32 +: 32] = src_cache_stat_prefetch_starts;
        cache_stats_payload_core[CACHE_STAT_PREFETCH_HITS_WORD*32 +: 32] = src_cache_stat_prefetch_hits;
        cache_stats_payload_core[CACHE_STAT_ANALYTIC_CANDIDATES_WORD*32 +: 32] = src_cache_stat_analytic_candidates;
        cache_stats_payload_core[CACHE_STAT_ANALYTIC_DUPLICATES_WORD*32 +: 32] = src_cache_stat_analytic_duplicates;
        cache_stats_payload_core[CACHE_STAT_ANALYTIC_BLOCKED_WORD*32 +: 32] = src_cache_stat_analytic_blocked;
        cache_stats_payload_core[CACHE_STAT_ANALYTIC_FILLS_WORD*32 +: 32] = src_cache_stat_analytic_fills;
        cache_stats_payload_core[CACHE_STAT_NORMAL_PREFETCH_FILLS_WORD*32 +: 32] = src_cache_stat_normal_prefetch_fills;
        cache_stats_payload_core[CACHE_STAT_PREFETCH_EVICT_UNUSED_WORD*32 +: 32] = src_cache_stat_prefetch_evicted_unused;
        cache_stats_payload_core[CACHE_STAT_FIFO_MAX_WORD*32 +: 32] = src_cache_stat_fifo_max_occupancy;
        cache_stats_payload_core[CACHE_STAT_READ_BUSY_CYCLES_WORD*32 +: 32] = src_cache_stat_read_busy_cycles;
        cache_stats_payload_core[CACHE_STAT_READ_BYTES_LOW_WORD*32 +: 32] = src_cache_stat_read_bytes_total_low;
        cache_stats_payload_core[CACHE_STAT_READ_BYTES_HIGH_WORD*32 +: 32] = src_cache_stat_read_bytes_total_high;
        cache_stats_payload_core[CACHE_STAT_USEFUL_SOURCE_SECTORS_WORD*32 +: 32] = src_cache_stat_useful_source_sectors;
        cache_stats_payload_core[CACHE_STAT_REPLACEMENT_FAIL_WORD*32 +: 32] = src_cache_stat_replacement_fail_cycles;
        cache_stats_payload_core[CACHE_STAT_MISS_LATENCY_MIN_WORD*32 +: 32] = src_cache_stat_miss_service_latency_min;
        cache_stats_payload_core[CACHE_STAT_MISS_LATENCY_MAX_WORD*32 +: 32] = src_cache_stat_miss_service_latency_max;
        cache_stats_payload_core[CACHE_STAT_MISS_LATENCY_SUM_LOW_WORD*32 +: 32] = src_cache_stat_miss_service_latency_sum_low;
        cache_stats_payload_core[CACHE_STAT_MISS_LATENCY_SUM_HIGH_WORD*32 +: 32] = src_cache_stat_miss_service_latency_sum_high;
        cache_stats_payload_core[CACHE_STAT_MISS_LATENCY_COUNT_WORD*32 +: 32] = src_cache_stat_miss_service_latency_count;
        for (h = 0; h < CACHE_STATS_HIST_BINS; h = h + 1) begin
            cache_stats_payload_core[(CACHE_STAT_MERGE_HIST_BASE_WORD + h)*32 +: 32] =
                src_cache_stat_merge_len_hist_flat[h*32 +: 32];
        end
        cache_stats_payload_core[CACHE_STAT_OVERRUN_WORD*32 +: 32] = {31'd0, cache_stats_overrun_reg};
        cache_stats_payload_core[CACHE_STAT_SCHED_POLICY_WORD*32 +: 32] = {30'd0, core_sched_policy};
        cache_stats_payload_core[CACHE_STAT_SCHED_LEAD_WORD*32 +: 32] = {16'd0, core_sched_lead_pixels};
        cache_stats_payload_core[CACHE_STAT_SCHED_MERGE_WORD*32 +: 32] =
            {16'd0, core_sched_merge_min_x, core_sched_merge_max_x_eff};
        cache_stats_payload_core[CACHE_STAT_SCHED_FIFO_WORD*32 +: 32] =
            {core_sched_fifo_age_limit, core_sched_fifo_depth_eff};
        cache_stats_payload_core[CACHE_STAT_SCHED_THROTTLE_WORD*32 +: 32] =
            {16'd0, core_sched_throttle_cycles};
        cache_stats_payload_core[CACHE_STAT_FIFO_HEAD_RUN_WORD*32 +: 32] =
            src_cache_stat_fifo_head_run_len;
        cache_stats_payload_core[CACHE_STAT_FIFO_SAME_ROW_ADJ_WORD*32 +: 32] =
            src_cache_stat_fifo_same_row_adjacent_count;
        cache_stats_payload_core[CACHE_STAT_FIFO_REVERSE_X_ADJ_WORD*32 +: 32] =
            src_cache_stat_fifo_reverse_x_adjacent_count;
        cache_stats_payload_core[CACHE_STAT_MERGE_OPPORTUNITY_MISSED_WORD*32 +: 32] =
            src_cache_stat_merge_opportunity_missed_count;
    end

    frame_config_cdc #(
        .ADDR_W(AXI_ADDR_W)
    ) u_frame_config_cdc (
        .src_clk(axi_clk),
        .src_rst(axi_sys_rst),
        .cfg_valid_src(start_pulse_reg),
        .src_base_addr_src(reg_src_base_addr),
        .dst_base_addr_src(reg_dst_base_addr),
        .src_stride_src(reg_src_stride),
        .dst_stride_src(reg_dst_stride),
        .src_w_src(reg_src_w),
        .src_h_src(reg_src_h),
        .dst_w_src(reg_dst_w),
        .dst_h_src(reg_dst_h),
        .rot_sin_q16_src(reg_rot_sin_q16),
        .rot_cos_q16_src(reg_rot_cos_q16),
        .cache_prefetch_en_src(reg_cache_prefetch_en),
        .scheduler_lead_pixels_src(reg_sched_lead_pixels),
        .scheduler_merge_max_x_eff_src(reg_sched_merge_max_x_eff),
        .scheduler_merge_min_x_src(reg_sched_merge_min_x),
        .scheduler_fifo_depth_eff_src(reg_sched_fifo_depth_eff),
        .scheduler_fifo_age_limit_src(reg_sched_fifo_age_limit),
        .scheduler_throttle_cycles_src(reg_sched_throttle_cycles),
        .scheduler_policy_src(reg_sched_policy),
        .cfg_ready_src(cfg_ready_axi),
        .dst_clk(core_clk),
        .dst_rst(core_sys_rst),
        .cfg_valid_dst(core_cfg_valid),
        .src_base_addr_dst(core_src_base_addr),
        .dst_base_addr_dst(core_dst_base_addr),
        .src_stride_dst(core_src_stride),
        .dst_stride_dst(core_dst_stride),
        .src_w_dst(core_src_w_cfg),
        .src_h_dst(core_src_h_cfg),
        .dst_w_dst(core_dst_w_cfg),
        .dst_h_dst(core_dst_h_cfg),
        .rot_sin_q16_dst(core_rot_sin_q16),
        .rot_cos_q16_dst(core_rot_cos_q16),
        .cache_prefetch_en_dst(core_cache_prefetch_en),
        .scheduler_lead_pixels_dst(core_sched_lead_pixels),
        .scheduler_merge_max_x_eff_dst(core_sched_merge_max_x_eff),
        .scheduler_merge_min_x_dst(core_sched_merge_min_x),
        .scheduler_fifo_depth_eff_dst(core_sched_fifo_depth_eff),
        .scheduler_fifo_age_limit_dst(core_sched_fifo_age_limit),
        .scheduler_throttle_cycles_dst(core_sched_throttle_cycles),
        .scheduler_policy_dst(core_sched_policy),
        .cfg_ready_dst(core_cfg_ready)
    );

    result_cdc u_ctrl_result_cdc (
        .src_clk(core_clk),
        .src_rst(core_sys_rst),
        .result_valid_src(ctrl_done_core || ctrl_error_core),
        .result_done_src(ctrl_done_core),
        .result_error_src(ctrl_error_core),
        .result_ready_src(ctrl_result_ready_core),
        .dst_clk(axi_clk),
        .dst_rst(axi_sys_rst),
        .result_valid_dst(ctrl_result_valid_axi),
        .result_done_dst(ctrl_result_done_axi),
        .result_error_dst(ctrl_result_error_axi)
    );

    cache_stats_cdc #(
        .PAYLOAD_W(CACHE_STATS_PAYLOAD_W)
    ) u_cache_stats_cdc (
        .src_clk(core_clk),
        .src_rst(core_sys_rst),
        .stats_valid_src(cache_stats_pending_valid_reg),
        .stats_payload_src(cache_stats_pending_payload_reg),
        .stats_ready_src(cache_stats_ready_core),
        .dst_clk(axi_clk),
        .dst_rst(axi_sys_rst),
        .stats_valid_dst(cache_stats_valid_axi),
        .stats_payload_dst(cache_stats_payload_axi)
    );

    always_ff @(posedge axi_clk) begin
        if (axi_sys_rst) begin
            cache_stats_overrun_axi_sync1_reg <= 1'b0;
            cache_stats_overrun_axi_sync2_reg <= 1'b0;
        end else begin
            cache_stats_overrun_axi_sync1_reg <= cache_stats_overrun_reg;
            cache_stats_overrun_axi_sync2_reg <= cache_stats_overrun_axi_sync1_reg;
        end
    end

    assign geom_cfg_ready_core = !geom_busy && !geom_pending_valid_reg && !geom_active_valid_reg;
    assign core_cfg_ready = !ctrl_busy_core && geom_cfg_ready_core;
    assign core_cfg_fire = core_cfg_valid && core_cfg_ready;
    assign geom_start = geom_pending_valid_reg && !geom_busy;

    always_ff @(posedge core_clk) begin
        if (core_sys_rst) begin
            cache_stats_snapshot_id_core_reg <= '0;
            frame_total_cycles_core_reg <= '0;
            frame_cycle_active_core_reg <= 1'b0;
            cache_stats_pending_valid_reg <= 1'b0;
            cache_stats_pending_payload_reg <= '0;
            cache_stats_overrun_reg <= 1'b0;
        end else begin
            if (core_cfg_fire) begin
                frame_total_cycles_core_reg <= '0;
                frame_cycle_active_core_reg <= 1'b1;
            end else if (frame_cycle_active_core_reg && !cache_stats_event_core) begin
                frame_total_cycles_core_reg <= frame_total_cycles_core_reg + 1'b1;
            end

            if (cache_stats_event_core) begin
                if (cache_stats_pending_valid_reg && !cache_stats_ready_core) begin
                    cache_stats_overrun_reg <= 1'b1;
                end else begin
                    cache_stats_pending_valid_reg <= 1'b1;
                    cache_stats_pending_payload_reg <= cache_stats_payload_core;
                    cache_stats_snapshot_id_core_reg <= cache_stats_snapshot_id_core_reg + 1'b1;
                end
                frame_cycle_active_core_reg <= 1'b0;
            end else if (cache_stats_pending_valid_reg && cache_stats_ready_core) begin
                cache_stats_pending_valid_reg <= 1'b0;
            end
        end
    end

    always_ff @(posedge core_clk) begin
        if (core_sys_rst) begin
            geom_next_id_reg <= '0;
            geom_pending_id_reg <= '0;
            geom_active_id_reg <= '0;
            geom_pending_valid_reg <= 1'b0;
            geom_active_valid_reg <= 1'b0;
            geom_ready_reg <= 1'b0;
            geom_error_hold_reg <= 1'b0;
            geom_src_w_cfg_reg <= '0;
            geom_src_h_cfg_reg <= '0;
            geom_dst_w_cfg_reg <= '0;
            geom_dst_h_cfg_reg <= '0;
            geom_rot_sin_q16_reg <= '0;
            geom_rot_cos_q16_reg <= '0;
            geom_hold_step_x_x_reg <= '0;
            geom_hold_step_y_x_reg <= '0;
            geom_hold_step_x_y_reg <= '0;
            geom_hold_step_y_y_reg <= '0;
            geom_hold_row0_x_reg <= '0;
            geom_hold_row0_y_reg <= '0;
            geom_hold_src_x_last_reg <= '0;
            geom_hold_src_y_last_reg <= '0;
            geom_hold_src_x_max_q16_reg <= '0;
            geom_hold_src_y_max_q16_reg <= '0;
        end else begin
            if (core_cfg_fire) begin
                geom_src_w_cfg_reg <= core_src_w_cfg[SRC_X_W-1:0];
                geom_src_h_cfg_reg <= core_src_h_cfg[SRC_Y_W-1:0];
                geom_dst_w_cfg_reg <= core_dst_w_cfg[DST_X_W-1:0];
                geom_dst_h_cfg_reg <= core_dst_h_cfg[DST_Y_W-1:0];
                geom_rot_sin_q16_reg <= core_rot_sin_q16;
                geom_rot_cos_q16_reg <= core_rot_cos_q16;
                geom_ready_reg <= 1'b0;
                geom_error_hold_reg <= 1'b0;
                if ((core_src_w_cfg != 16'd0) && (core_src_h_cfg != 16'd0) &&
                    (core_dst_w_cfg != 16'd0) && (core_dst_h_cfg != 16'd0)) begin
                    geom_pending_valid_reg <= 1'b1;
                    geom_pending_id_reg <= geom_next_id_reg;
                    geom_next_id_reg <= geom_next_id_reg + 1'b1;
                end else begin
                    geom_pending_valid_reg <= 1'b0;
                    geom_active_valid_reg <= 1'b0;
                    geom_error_hold_reg <= 1'b1;
                end
            end

            if (geom_start) begin
                geom_active_valid_reg <= 1'b1;
                geom_active_id_reg <= geom_pending_id_reg;
                geom_pending_valid_reg <= 1'b0;
            end

            if (geom_active_valid_reg && (geom_result_id == geom_active_id_reg)) begin
                if (geom_error) begin
                    geom_ready_reg <= 1'b0;
                    geom_error_hold_reg <= 1'b1;
                    geom_active_valid_reg <= 1'b0;
                end else if (geom_valid && !geom_pending_valid_reg) begin
                    geom_hold_step_x_x_reg <= geom_step_x_x;
                    geom_hold_step_y_x_reg <= geom_step_y_x;
                    geom_hold_step_x_y_reg <= geom_step_x_y;
                    geom_hold_step_y_y_reg <= geom_step_y_y;
                    geom_hold_row0_x_reg <= geom_row0_x;
                    geom_hold_row0_y_reg <= geom_row0_y;
                    geom_hold_src_x_last_reg <= geom_src_x_last;
                    geom_hold_src_y_last_reg <= geom_src_y_last;
                    geom_hold_src_x_max_q16_reg <= geom_src_x_max_q16;
                    geom_hold_src_y_max_q16_reg <= geom_src_y_max_q16;
                    geom_ready_reg <= 1'b1;
                    geom_error_hold_reg <= 1'b0;
                    geom_active_valid_reg <= 1'b0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    logic cfg_hold_valid_reg;
    logic [AXI_ADDR_W-1:0] cfg_hold_src_base_addr_reg;
    logic [AXI_ADDR_W-1:0] cfg_hold_dst_base_addr_reg;
    logic [AXI_ADDR_W-1:0] cfg_hold_src_stride_reg;
    logic [AXI_ADDR_W-1:0] cfg_hold_dst_stride_reg;
    logic [15:0] cfg_hold_src_w_reg;
    logic [15:0] cfg_hold_src_h_reg;
    logic [15:0] cfg_hold_dst_w_reg;
    logic [15:0] cfg_hold_dst_h_reg;
    logic signed [31:0] cfg_hold_rot_sin_reg;
    logic signed [31:0] cfg_hold_rot_cos_reg;
    logic cfg_hold_prefetch_reg;
    logic [15:0] cfg_hold_sched_lead_reg;
    logic [7:0] cfg_hold_sched_merge_max_reg;
    logic [7:0] cfg_hold_sched_merge_min_reg;
    logic [15:0] cfg_hold_sched_fifo_depth_reg;
    logic [15:0] cfg_hold_sched_fifo_age_reg;
    logic [15:0] cfg_hold_sched_throttle_reg;
    logic [1:0] cfg_hold_sched_policy_reg;

    always_ff @(posedge core_clk) begin
        if (core_sys_rst) begin
            cfg_hold_valid_reg <= 1'b0;
            cfg_hold_src_base_addr_reg <= '0;
            cfg_hold_dst_base_addr_reg <= '0;
            cfg_hold_src_stride_reg <= '0;
            cfg_hold_dst_stride_reg <= '0;
            cfg_hold_src_w_reg <= '0;
            cfg_hold_src_h_reg <= '0;
            cfg_hold_dst_w_reg <= '0;
            cfg_hold_dst_h_reg <= '0;
            cfg_hold_rot_sin_reg <= '0;
            cfg_hold_rot_cos_reg <= '0;
            cfg_hold_prefetch_reg <= 1'b0;
            cfg_hold_sched_lead_reg <= '0;
            cfg_hold_sched_merge_max_reg <= '0;
            cfg_hold_sched_merge_min_reg <= '0;
            cfg_hold_sched_fifo_depth_reg <= '0;
            cfg_hold_sched_fifo_age_reg <= '0;
            cfg_hold_sched_throttle_reg <= '0;
            cfg_hold_sched_policy_reg <= '0;
        end else begin
            if (core_cfg_valid && !core_cfg_ready) begin
                if (!cfg_hold_valid_reg) begin
                    cfg_hold_valid_reg <= 1'b1;
                    cfg_hold_src_base_addr_reg <= core_src_base_addr;
                    cfg_hold_dst_base_addr_reg <= core_dst_base_addr;
                    cfg_hold_src_stride_reg <= core_src_stride;
                    cfg_hold_dst_stride_reg <= core_dst_stride;
                    cfg_hold_src_w_reg <= core_src_w_cfg;
                    cfg_hold_src_h_reg <= core_src_h_cfg;
                    cfg_hold_dst_w_reg <= core_dst_w_cfg;
                    cfg_hold_dst_h_reg <= core_dst_h_cfg;
                    cfg_hold_rot_sin_reg <= core_rot_sin_q16;
                    cfg_hold_rot_cos_reg <= core_rot_cos_q16;
                    cfg_hold_prefetch_reg <= core_cache_prefetch_en;
                    cfg_hold_sched_lead_reg <= core_sched_lead_pixels;
                    cfg_hold_sched_merge_max_reg <= core_sched_merge_max_x_eff;
                    cfg_hold_sched_merge_min_reg <= core_sched_merge_min_x;
                    cfg_hold_sched_fifo_depth_reg <= core_sched_fifo_depth_eff;
                    cfg_hold_sched_fifo_age_reg <= core_sched_fifo_age_limit;
                    cfg_hold_sched_throttle_reg <= core_sched_throttle_cycles;
                    cfg_hold_sched_policy_reg <= core_sched_policy;
                end else if ((cfg_hold_src_base_addr_reg !== core_src_base_addr) ||
                             (cfg_hold_dst_base_addr_reg !== core_dst_base_addr) ||
                             (cfg_hold_src_stride_reg !== core_src_stride) ||
                             (cfg_hold_dst_stride_reg !== core_dst_stride) ||
                             (cfg_hold_src_w_reg !== core_src_w_cfg) ||
                             (cfg_hold_src_h_reg !== core_src_h_cfg) ||
                             (cfg_hold_dst_w_reg !== core_dst_w_cfg) ||
                             (cfg_hold_dst_h_reg !== core_dst_h_cfg) ||
                             (cfg_hold_rot_sin_reg !== core_rot_sin_q16) ||
                             (cfg_hold_rot_cos_reg !== core_rot_cos_q16) ||
                             (cfg_hold_prefetch_reg !== core_cache_prefetch_en) ||
                             (cfg_hold_sched_lead_reg !== core_sched_lead_pixels) ||
                             (cfg_hold_sched_merge_max_reg !== core_sched_merge_max_x_eff) ||
                             (cfg_hold_sched_merge_min_reg !== core_sched_merge_min_x) ||
                             (cfg_hold_sched_fifo_depth_reg !== core_sched_fifo_depth_eff) ||
                             (cfg_hold_sched_fifo_age_reg !== core_sched_fifo_age_limit) ||
                             (cfg_hold_sched_throttle_reg !== core_sched_throttle_cycles) ||
                             (cfg_hold_sched_policy_reg !== core_sched_policy)) begin
                    $error("image_geo_top core config payload changed while valid was held without ready");
                end
            end else begin
                cfg_hold_valid_reg <= 1'b0;
            end

            if (core_cfg_fire && (!geom_cfg_ready_core || ctrl_busy_core)) begin
                $error("image_geo_top fired a new config while geometry or controller was not ready");
            end

            if (cache_stats_overrun_reg) begin
                $error("image_geo_top cache stats snapshot overrun");
            end

            if ((ctrl_done_core || ctrl_error_core) && !ctrl_result_ready_core) begin
                $error("image_geo_top result event occurred while result_cdc was busy");
            end
        end
    end
`endif

    rotate_geom_init_unit #(
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .FRAC_W   (16),
        .COORD_W  (GEOM_COORD_W),
        .GEOM_ID_W(GEOM_ID_W)
    ) u_rotate_geom_init (
        .clk            (core_clk),
        .rst            (core_sys_rst),
        .start          (geom_start),
        .start_id       (geom_pending_id_reg),
        .src_w          (geom_src_w_cfg_reg),
        .src_h          (geom_src_h_cfg_reg),
        .dst_w          (geom_dst_w_cfg_reg),
        .dst_h          (geom_dst_h_cfg_reg),
        .rot_sin_q16    (geom_rot_sin_q16_reg),
        .rot_cos_q16    (geom_rot_cos_q16_reg),
        .geom_valid     (geom_valid),
        .geom_busy      (geom_busy),
        .geom_error     (geom_error),
        .geom_id        (geom_result_id),
        .scale_x_q16    (geom_scale_x_q16),
        .scale_y_q16    (geom_scale_y_q16),
        .step_x_x       (geom_step_x_x),
        .step_y_x       (geom_step_y_x),
        .step_x_y       (geom_step_x_y),
        .step_y_y       (geom_step_y_y),
        .row0_x         (geom_row0_x),
        .row0_y         (geom_row0_y),
        .src_x_last     (geom_src_x_last),
        .src_y_last     (geom_src_y_last),
        .src_x_max_q16  (geom_src_x_max_q16),
        .src_y_max_q16  (geom_src_y_max_q16)
    );


    // 缂╂斁閾捐矾涓绘帶锛氳礋璐ｆ簮琛岀紦瀛橀瑁呫€乧ore 鍚姩鍜岀粨鏋滃啓鍥炴椂搴忋€?
    scaler_ctrl #(
        .PIXEL_W(PIXEL_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .LINE_NUM(LINE_NUM)
    ) u_scaler_ctrl (
        .clk(core_clk),
        .sys_rst(core_sys_rst),
        .start(core_cfg_fire),
        .src_base_addr(core_src_base_addr),
        .dst_base_addr(core_dst_base_addr),
        .src_stride(core_src_stride),
        .dst_stride(core_dst_stride),
        .src_w(core_src_w_cfg[SRC_X_W-1:0]),
        .src_h(core_src_h_cfg[SRC_Y_W-1:0]),
        .dst_w(core_dst_w_cfg[DST_X_W-1:0]),
        .dst_h(core_dst_h_cfg[DST_Y_W-1:0]),
        .busy(ctrl_busy_core),
        .done(ctrl_done_core),
        .error(ctrl_error_core),
        .core_start(core_start),
        .core_busy(core_busy),
        .core_done(core_done),
        .core_error(core_error),
        .cache_error(src_cache_error),
        .row_done(core_row_done),
        .wb_start(row_start),
        .wb_pixel_count(row_pixel_count),
        .wb_busy(row_busy),
        .wb_done_buf(row_done_fill),
        .wb_error(row_error),
        .wb_out_start(row_out_start),
        .wb_out_done(row_out_done),

        .write_start(write_start),
        .write_addr(write_addr),
        .write_byte_count(write_byte_count),
        .write_busy(write_busy),
        .write_done(write_done),
        .write_error(write_error)
    );

    // 涓绘暟鎹摼璺緷娆¤繛鎺?DDR 璇诲彇銆佹簮琛岀紦瀛樸€乥ilinear core銆佽缂撳啿鍜?DDR 鍐欏洖銆?
    src_tile_cache #(
        .PIXEL_W(PIXEL_W),
        .ADDR_W(AXI_ADDR_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .COORD_W(GEOM_COORD_W),
        .TILE_W(`IMAGE_GEO_SRC_TILE_W),
        .TILE_H(`IMAGE_GEO_SRC_TILE_H),
        .TILE_NUM(`IMAGE_GEO_SRC_TILE_NUM)
    ) u_src_tile_cache (
        .clk(core_clk),
        .sys_rst(core_sys_rst),
        .start(core_cfg_fire),
        .src_base_addr(core_src_base_addr),
        .src_stride(core_src_stride),
        .src_w(core_src_w_cfg[SRC_X_W-1:0]),
        .src_h(core_src_h_cfg[SRC_Y_W-1:0]),
        .dst_w(core_dst_w_cfg[DST_X_W-1:0]),
        .dst_h(core_dst_h_cfg[DST_Y_W-1:0]),
        .rot_sin_q16(core_rot_sin_q16),
        .rot_cos_q16(core_rot_cos_q16),
        .geom_ready(geom_ready_reg),
        .geom_error(geom_error_hold_reg),
        .geom_step_x_x(geom_hold_step_x_x_reg),
        .geom_step_y_x(geom_hold_step_y_x_reg),
        .geom_step_x_y(geom_hold_step_x_y_reg),
        .geom_step_y_y(geom_hold_step_y_y_reg),
        .geom_row0_x(geom_hold_row0_x_reg),
        .geom_row0_y(geom_hold_row0_y_reg),
        .geom_src_x_last(geom_hold_src_x_last_reg),
        .geom_src_y_last(geom_hold_src_y_last_reg),
        .geom_src_x_max_q16(geom_hold_src_x_max_q16_reg),
        .geom_src_y_max_q16(geom_hold_src_y_max_q16_reg),
        .prefetch_enable(core_cache_prefetch_en),
        .runtime_lead_pixels(core_sched_lead_pixels),
        .runtime_merge_max_x_eff(core_sched_merge_max_x_eff),
        .runtime_merge_min_x(core_sched_merge_min_x),
        .runtime_fifo_depth_eff(core_sched_fifo_depth_eff),
        .runtime_fifo_age_limit(core_sched_fifo_age_limit),
        .runtime_prefetch_throttle_cycles(core_sched_throttle_cycles),
        .runtime_scheduler_policy(core_sched_policy),
        .scan_dir_x(sample_scan_dir_x),
        .scan_dir_y(sample_scan_dir_y),
        .scan_dir_valid(sample_scan_dir_valid),
        .busy(read_busy_core),
        .error(src_cache_error),
        .read_start(cache_read_start),
        .read_addr(cache_read_addr),
        .read_row_stride(cache_read_row_stride),
        .read_byte_count(cache_read_byte_count),
        .read_row_count(cache_read_row_count),
        .read_start_ready(cache_read_start_ready),
        .read_busy(cache_read_busy),
        .read_done(cache_read_done),
        .read_error(cache_read_error),
        .in_data(read_out_data),
        .in_valid(read_out_valid),
        .in_row_last(read_out_row_last),
        .in_ready(read_out_ready),
        .sample_req_valid(sample_req_valid),
        .sample_x0(sample_x0),
        .sample_y0(sample_y0),
        .sample_x1(sample_x1),
        .sample_y1(sample_y1),
        .sample_req_ready(sample_req_ready),
        .sample_p00(cache_sample_p00),
        .sample_p01(cache_sample_p01),
        .sample_p10(cache_sample_p10),
        .sample_p11(cache_sample_p11),
        .sample_rsp_valid(cache_sample_rsp_valid),
        .stat_read_starts(src_cache_stat_read_starts),
        .stat_misses(src_cache_stat_misses),
        .stat_prefetch_starts(src_cache_stat_prefetch_starts),
        .stat_prefetch_hits(src_cache_stat_prefetch_hits),
        .stat_analytic_candidates(src_cache_stat_analytic_candidates),
        .stat_analytic_duplicates(src_cache_stat_analytic_duplicates),
        .stat_analytic_blocked(src_cache_stat_analytic_blocked),
        .stat_analytic_fills(src_cache_stat_analytic_fills),
        .stat_prefetch_evicted_unused(src_cache_stat_prefetch_evicted_unused),
        .stat_total_cycles(src_cache_stat_total_cycles),
        .stat_sample_req_count(src_cache_stat_sample_req_count),
        .stat_sample_accept_count(src_cache_stat_sample_accept_count),
        .stat_sample_stall_cycles(src_cache_stat_sample_stall_cycles),
        .stat_normal_prefetch_fills(src_cache_stat_normal_prefetch_fills),
        .stat_fifo_max_occupancy(src_cache_stat_fifo_max_occupancy),
        .stat_read_busy_cycles(src_cache_stat_read_busy_cycles),
        .stat_read_bytes_total_low(src_cache_stat_read_bytes_total_low),
        .stat_read_bytes_total_high(src_cache_stat_read_bytes_total_high),
        .stat_useful_source_sectors(src_cache_stat_useful_source_sectors),
        .stat_replacement_fail_cycles(src_cache_stat_replacement_fail_cycles),
        .stat_miss_service_latency_min(src_cache_stat_miss_service_latency_min),
        .stat_miss_service_latency_max(src_cache_stat_miss_service_latency_max),
        .stat_miss_service_latency_sum_low(src_cache_stat_miss_service_latency_sum_low),
        .stat_miss_service_latency_sum_high(src_cache_stat_miss_service_latency_sum_high),
        .stat_miss_service_latency_count(src_cache_stat_miss_service_latency_count),
        .stat_merge_len_hist_flat(src_cache_stat_merge_len_hist_flat),
        .stat_fifo_head_run_len(src_cache_stat_fifo_head_run_len),
        .stat_fifo_same_row_adjacent_count(src_cache_stat_fifo_same_row_adjacent_count),
        .stat_fifo_reverse_x_adjacent_count(src_cache_stat_fifo_reverse_x_adjacent_count),
        .stat_merge_opportunity_missed_count(src_cache_stat_merge_opportunity_missed_count)
    );

    assign read_error_core = src_cache_error;
    assign read_done_core  = 1'b0;

    ddr_read_engine #(
        .ADDR_W(AXI_ADDR_W),
        .PIXEL_W(PIXEL_W),
        .AXI_ID_W(AXI_ID_W),
        .BURST_MAX_LEN(`IMAGE_GEO_RD_BURST_MAX_LEN),
        .FIFO_DEPTH_WORDS(`IMAGE_GEO_RD_FIFO_DEPTH_WORDS),
        .MAX_OUTSTANDING_BURSTS(`IMAGE_GEO_RD_MAX_OUTSTANDING_BURSTS),
        .MAX_OUTSTANDING_BEATS(`IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS)
    ) u_ddr_read_engine (
        .axi_clk(axi_clk),
        .core_clk(core_clk),
        .axi_rst(axi_sys_rst),
        .core_rst(core_sys_rst),
        .task_start(cache_read_start),
        .task_addr(cache_read_addr),
        .task_row_stride(cache_read_row_stride),
        .task_byte_count(cache_read_byte_count),
        .task_row_count(cache_read_row_count),
        .task_start_ready(cache_read_start_ready),
        .task_busy(cache_read_busy),
        .task_done(cache_read_done),
        .task_error(cache_read_error),
        .out_data(read_out_data),
        .out_valid(read_out_valid),
        .out_row_last(read_out_row_last),
        .out_ready(read_out_ready),
        .m_axi_rd(m_axi_rd_if)
    );

    rotate_core_bilinear #(
        .PIXEL_W(PIXEL_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .COORD_W(GEOM_COORD_W)
    ) u_rotate_core_bilinear (
        .clk(core_clk),
        .rst(core_sys_rst),
        .start(core_start),
        .src_w(core_src_w_cfg[SRC_X_W-1:0]),
        .src_h(core_src_h_cfg[SRC_Y_W-1:0]),
        .dst_w(core_dst_w_cfg[DST_X_W-1:0]),
        .dst_h(core_dst_h_cfg[DST_Y_W-1:0]),
        .angle_cos_q16(core_rot_cos_q16),
        .angle_sin_q16(core_rot_sin_q16),
        .geom_ready(geom_ready_reg),
        .geom_error(geom_error_hold_reg),
        .geom_step_x_x(geom_hold_step_x_x_reg),
        .geom_step_y_x(geom_hold_step_y_x_reg),
        .geom_step_x_y(geom_hold_step_x_y_reg),
        .geom_step_y_y(geom_hold_step_y_y_reg),
        .geom_row0_x(geom_hold_row0_x_reg),
        .geom_row0_y(geom_hold_row0_y_reg),
        .geom_src_x_last(geom_hold_src_x_last_reg),
        .geom_src_y_last(geom_hold_src_y_last_reg),
        .geom_src_x_max_q16(geom_hold_src_x_max_q16_reg),
        .geom_src_y_max_q16(geom_hold_src_y_max_q16_reg),
        .busy(core_busy),
        .done(core_done),
        .error(core_error),
        .sample_req_valid(sample_req_valid),
        .sample_x0(sample_x0),
        .sample_y0(sample_y0),
        .sample_x1(sample_x1),
        .sample_y1(sample_y1),
        .sample_req_ready(sample_req_ready),
        .sample_p00(sample_p00),
        .sample_p01(sample_p01),
        .sample_p10(sample_p10),
        .sample_p11(sample_p11),
        .sample_rsp_valid(sample_rsp_valid),
        .scan_dir_x(sample_scan_dir_x),
        .scan_dir_y(sample_scan_dir_y),
        .scan_dir_valid(sample_scan_dir_valid),
        .pix_data(core_pix_data),
        .pix_valid(core_pix_valid),
        .pix_ready(core_pix_ready),
        .row_done(core_row_done)
    );

    row_out_buffer #(
        .PIXEL_W(PIXEL_W),
        .MAX_DST_W(MAX_DST_W)
    ) u_row_out_buffer (
        .clk(core_clk),
        .sys_rst(core_sys_rst),
        .row_start(row_start),
        .row_pixel_count(row_pixel_count),
        .row_busy(row_busy),
        .row_done(row_done_fill),
        .row_error(row_error),
        .in_data(row_in_data),
        .in_valid(row_in_valid),
        .in_ready(row_in_ready),
        .out_start(row_out_start),
        .out_data(row_out_data),
        .out_valid(row_out_valid),
        .out_ready(row_out_ready),
        .out_done(row_out_done)
    );

    assign row_in_data  = core_pix_pipe_data_reg;
    assign row_in_valid = core_pix_pipe_valid_reg;
    assign core_pix_ready = !core_pix_pipe_valid_reg || row_in_ready;

    always_ff @(posedge core_clk) begin
        if (core_sys_rst) begin
            sample_p00 <= '0;
            sample_p01 <= '0;
            sample_p10 <= '0;
            sample_p11 <= '0;
            sample_rsp_valid <= 1'b0;
            core_pix_pipe_valid_reg <= 1'b0;
            core_pix_pipe_data_reg  <= '0;
        end else begin
            sample_rsp_valid <= cache_sample_rsp_valid;
            if (cache_sample_rsp_valid) begin
                sample_p00 <= cache_sample_p00;
                sample_p01 <= cache_sample_p01;
                sample_p10 <= cache_sample_p10;
                sample_p11 <= cache_sample_p11;
            end

            if (!core_pix_pipe_valid_reg || core_pix_ready) begin
                core_pix_pipe_valid_reg <= core_pix_valid;
                if (core_pix_valid) begin
                    core_pix_pipe_data_reg <= core_pix_data;
                end
            end
        end
    end

    ddr_write_engine #(
        .DATA_W(AXI_DATA_W),
        .ADDR_W(AXI_ADDR_W),
        .PIXEL_W(PIXEL_W),
        .BURST_MAX_LEN(`IMAGE_GEO_WR_BURST_MAX_LEN),
        .AXI_ID_W(AXI_ID_W),
        .FIFO_DEPTH_PIXELS(`IMAGE_GEO_WR_FIFO_DEPTH_PIXELS)
    ) u_ddr_write_engine (
        .axi_clk(axi_clk),
        .core_clk(core_clk),
        .axi_rst(axi_sys_rst),
        .core_rst(core_sys_rst),
        .task_start(write_start),
        .task_addr(write_addr),
        .task_byte_count(write_byte_count),
        .task_busy(write_busy),
        .task_done(write_done),
        .task_error(write_error),
        .in_data(row_out_data),
        .in_valid(row_out_valid),
        .in_ready(row_out_ready),
        .m_axi_wr(m_axi_wr_if)
    );

    assign m_axi_rd_arid       = m_axi_rd_if.arid;
    assign m_axi_rd_araddr     = m_axi_rd_if.araddr;
    assign m_axi_rd_arlen      = m_axi_rd_if.arlen;
    assign m_axi_rd_arsize     = m_axi_rd_if.arsize;
    assign m_axi_rd_arburst    = m_axi_rd_if.arburst;
    assign m_axi_rd_arlock     = m_axi_rd_if.arlock;
    assign m_axi_rd_arcache    = m_axi_rd_if.arcache;
    assign m_axi_rd_arprot     = m_axi_rd_if.arprot;
    assign m_axi_rd_arqos      = m_axi_rd_if.arqos;
    assign m_axi_rd_arregion   = m_axi_rd_if.arregion;
    assign m_axi_rd_arvalid    = m_axi_rd_if.arvalid;
    assign m_axi_rd_if.arready = m_axi_rd_arready;
    assign m_axi_rd_if.rid     = m_axi_rd_rid;
    assign m_axi_rd_if.rdata   = m_axi_rd_rdata;
    assign m_axi_rd_if.rresp   = m_axi_rd_rresp;
    assign m_axi_rd_if.rlast   = m_axi_rd_rlast;
    assign m_axi_rd_if.ruser   = '0;
    assign m_axi_rd_if.rvalid  = m_axi_rd_rvalid;
    assign m_axi_rd_rready     = m_axi_rd_if.rready;

    assign m_axi_wr_awid       = m_axi_wr_if.awid;
    assign m_axi_wr_awaddr     = m_axi_wr_if.awaddr;
    assign m_axi_wr_awlen      = m_axi_wr_if.awlen;
    assign m_axi_wr_awsize     = m_axi_wr_if.awsize;
    assign m_axi_wr_awburst    = m_axi_wr_if.awburst;
    assign m_axi_wr_awlock     = m_axi_wr_if.awlock;
    assign m_axi_wr_awcache    = m_axi_wr_if.awcache;
    assign m_axi_wr_awprot     = m_axi_wr_if.awprot;
    assign m_axi_wr_awqos      = m_axi_wr_if.awqos;
    assign m_axi_wr_awregion   = m_axi_wr_if.awregion;
    assign m_axi_wr_awvalid    = m_axi_wr_if.awvalid;
    assign m_axi_wr_wdata      = m_axi_wr_if.wdata;
    assign m_axi_wr_wstrb      = m_axi_wr_if.wstrb;
    assign m_axi_wr_wlast      = m_axi_wr_if.wlast;
    assign m_axi_wr_wvalid     = m_axi_wr_if.wvalid;
    assign m_axi_wr_if.awready = m_axi_wr_awready;
    assign m_axi_wr_if.wready  = m_axi_wr_wready;
    assign m_axi_wr_if.bid     = m_axi_wr_bid;
    assign m_axi_wr_if.bresp   = m_axi_wr_bresp;
    assign m_axi_wr_if.buser   = '0;
    assign m_axi_wr_if.bvalid  = m_axi_wr_bvalid;
    assign m_axi_wr_bready     = m_axi_wr_if.bready;

    assign unused_signals = &{
        1'b0,
        s_axi_ctrl_awprot,
        s_axi_ctrl_arprot,
        read_busy_core,
        read_done_core,
        read_error_core,
        core_rstn
    };

endmodule
