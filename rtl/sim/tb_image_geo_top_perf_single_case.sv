`timescale 1ns/1ps

`ifndef IMAGE_GEO_RUNTIME_LEAD_PIXELS
`define IMAGE_GEO_RUNTIME_LEAD_PIXELS `SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS
`endif
`ifndef IMAGE_GEO_RUNTIME_MERGE_MAX_X
`define IMAGE_GEO_RUNTIME_MERGE_MAX_X `SRC_TILE_CACHE_MERGE_MAX_X
`endif
`ifndef IMAGE_GEO_RUNTIME_MERGE_MIN_X
`define IMAGE_GEO_RUNTIME_MERGE_MIN_X `SRC_TILE_CACHE_MERGE_MIN_X
`endif
`ifndef IMAGE_GEO_RUNTIME_FIFO_DEPTH
`define IMAGE_GEO_RUNTIME_FIFO_DEPTH `SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH
`endif
`ifndef IMAGE_GEO_RUNTIME_FIFO_AGE_LIMIT
`define IMAGE_GEO_RUNTIME_FIFO_AGE_LIMIT `SRC_TILE_CACHE_FIFO_AGE_LIMIT
`endif
`ifndef IMAGE_GEO_RUNTIME_PREFETCH_THROTTLE_CYCLES
`define IMAGE_GEO_RUNTIME_PREFETCH_THROTTLE_CYCLES `SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES
`endif
`ifndef IMAGE_GEO_RUNTIME_SCHEDULER_POLICY
`define IMAGE_GEO_RUNTIME_SCHEDULER_POLICY (((`SRC_TILE_CACHE_ENABLE_MERGE_MIN != 0) ? 1 : 0) | ((`SRC_TILE_CACHE_ENABLE_PREFETCH_THROTTLE != 0) ? 2 : 0))
`endif

module tb_image_geo_top_perf_single_case_base #(
    parameter string CASE_NAME = "small_rotate45",
    parameter bit PREFETCH_EN = 1'b0,
    parameter int SRC_W_CFG = 64,
    parameter int SRC_H_CFG = 64,
    parameter int DST_W_CFG = 24,
    parameter int DST_H_CFG = 24,
    parameter int signed SIN_Q16_CFG = 32'sh0000_B505,
    parameter int signed COS_Q16_CFG = 32'sh0000_B505,
    parameter int SRC_STRIDE_CFG = 64,
    parameter int DST_STRIDE_CFG = 64,
    parameter int TIMEOUT_CYCLES_CFG = 120000000
) ;

    localparam int AXIL_ADDR_W = 12;
    localparam int AXIL_DATA_W = 32;
    localparam int AXI_ADDR_W  = 32;
    localparam int AXI_DATA_W  = 32;
    localparam int AXI_ID_W    = 4;
    localparam int PIXEL_W     = 8;
    localparam int BYTE_W      = AXI_DATA_W / 8;
    localparam int SRC_BASE    = 32'h0000_0100;
    localparam int DST_BASE    = 32'h0800_0000;
    localparam int SRC_STRIDE  = 7200;
    localparam int DST_STRIDE  = 600;
    localparam int TIMEOUT_CYCLES = TIMEOUT_CYCLES_CFG;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_READS_ADDR = 12'h028;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_MISSES_ADDR = 12'h02C;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_PREFETCH_ADDR = 12'h030;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_PREFETCH_HIT_ADDR = 12'h034;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_STATS_EXT_BASE_ADDR = 12'h040;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_CTRL_ADDR = 12'h140;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_LEAD_ADDR = 12'h144;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_MERGE_ADDR = 12'h148;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_FIFO_ADDR = 12'h14C;
    localparam logic [AXIL_ADDR_W-1:0] REG_SCHED_THROTTLE_ADDR = 12'h150;
    localparam int CACHE_STAT_VERSION_WORD = 0;
    localparam int CACHE_STAT_SNAPSHOT_ID_WORD = 1;
    localparam int CACHE_STAT_FRAME_CYCLES_WORD = 2;
    localparam int CACHE_STAT_TOTAL_CYCLES_WORD = 3;
    localparam int CACHE_STAT_SAMPLE_REQ_WORD = 4;
    localparam int CACHE_STAT_SAMPLE_ACCEPT_WORD = 5;
    localparam int CACHE_STAT_SAMPLE_STALL_WORD = 6;
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
    localparam int CACHE_STAT_SCHED_POLICY_WORD = 46;
    localparam int CACHE_STAT_SCHED_LEAD_WORD = 47;
    localparam int CACHE_STAT_SCHED_MERGE_WORD = 48;
    localparam int CACHE_STAT_SCHED_FIFO_WORD = 49;
    localparam int CACHE_STAT_SCHED_THROTTLE_WORD = 50;
    localparam int CACHE_STAT_FIFO_HEAD_RUN_WORD = 51;
    localparam int CACHE_STAT_FIFO_SAME_ROW_ADJ_WORD = 52;
    localparam int CACHE_STAT_FIFO_REVERSE_X_ADJ_WORD = 53;
    localparam int CACHE_STAT_MERGE_OPPORTUNITY_MISSED_WORD = 54;

    logic axi_clk;
    logic axi_rstn;
    logic core_clk;
    logic core_rstn;
    logic irq;

    logic [AXIL_ADDR_W-1:0]     s_axi_ctrl_awaddr;
    logic [2:0]                 s_axi_ctrl_awprot;
    logic                       s_axi_ctrl_awvalid;
    logic                       s_axi_ctrl_awready;
    logic [AXIL_DATA_W-1:0]     s_axi_ctrl_wdata;
    logic [(AXIL_DATA_W/8)-1:0] s_axi_ctrl_wstrb;
    logic                       s_axi_ctrl_wvalid;
    logic                       s_axi_ctrl_wready;
    logic [1:0]                 s_axi_ctrl_bresp;
    logic                       s_axi_ctrl_bvalid;
    logic                       s_axi_ctrl_bready;
    logic [AXIL_ADDR_W-1:0]     s_axi_ctrl_araddr;
    logic [2:0]                 s_axi_ctrl_arprot;
    logic                       s_axi_ctrl_arvalid;
    logic                       s_axi_ctrl_arready;
    logic [AXIL_DATA_W-1:0]     s_axi_ctrl_rdata;
    logic [1:0]                 s_axi_ctrl_rresp;
    logic                       s_axi_ctrl_rvalid;
    logic                       s_axi_ctrl_rready;

    logic [AXI_ID_W-1:0]        m_axi_rd_arid;
    logic [AXI_ADDR_W-1:0]      m_axi_rd_araddr;
    logic [7:0]                 m_axi_rd_arlen;
    logic [2:0]                 m_axi_rd_arsize;
    logic [1:0]                 m_axi_rd_arburst;
    logic                       m_axi_rd_arlock;
    logic [3:0]                 m_axi_rd_arcache;
    logic [2:0]                 m_axi_rd_arprot;
    logic [3:0]                 m_axi_rd_arqos;
    logic [3:0]                 m_axi_rd_arregion;
    logic                       m_axi_rd_arvalid;
    logic                       m_axi_rd_arready;
    logic [AXI_ID_W-1:0]        m_axi_rd_rid;
    logic [AXI_DATA_W-1:0]      m_axi_rd_rdata;
    logic [1:0]                 m_axi_rd_rresp;
    logic                       m_axi_rd_rlast;
    logic                       m_axi_rd_rvalid;
    logic                       m_axi_rd_rready;

    logic [AXI_ID_W-1:0]        m_axi_wr_awid;
    logic [AXI_ADDR_W-1:0]      m_axi_wr_awaddr;
    logic [7:0]                 m_axi_wr_awlen;
    logic [2:0]                 m_axi_wr_awsize;
    logic [1:0]                 m_axi_wr_awburst;
    logic                       m_axi_wr_awlock;
    logic [3:0]                 m_axi_wr_awcache;
    logic [2:0]                 m_axi_wr_awprot;
    logic [3:0]                 m_axi_wr_awqos;
    logic [3:0]                 m_axi_wr_awregion;
    logic                       m_axi_wr_awvalid;
    logic                       m_axi_wr_awready;
    logic [AXI_DATA_W-1:0]      m_axi_wr_wdata;
    logic [(AXI_DATA_W/8)-1:0]  m_axi_wr_wstrb;
    logic                       m_axi_wr_wlast;
    logic                       m_axi_wr_wvalid;
    logic                       m_axi_wr_wready;
    logic [AXI_ID_W-1:0]        m_axi_wr_bid;
    logic [1:0]                 m_axi_wr_bresp;
    logic                       m_axi_wr_bvalid;
    logic                       m_axi_wr_bready;

    logic [AXI_ADDR_W-1:0] rd_active_addr_reg;
    int unsigned           rd_active_beats_reg;
    int unsigned           rd_active_idx_reg;
    bit                    rd_active_reg;
    logic [AXI_ADDR_W-1:0] rd_addr_queue [0:63];
    int unsigned           rd_beats_queue [0:63];
    int unsigned           rd_head_reg;
    int unsigned           rd_tail_reg;
    int unsigned           rd_count_reg;

    logic [AXI_ADDR_W-1:0] wr_active_addr_reg;
    int unsigned           wr_active_beats_reg;
    int unsigned           wr_active_idx_reg;
    bit                    wr_active_reg;

    int cycle_count;
    int runtime_lead_pixels_cfg;
    int runtime_merge_max_x_eff_cfg;
    int runtime_merge_min_x_cfg;
    int runtime_fifo_depth_eff_cfg;
    int runtime_fifo_age_limit_cfg;
    int runtime_throttle_cycles_cfg;
    int runtime_scheduler_policy_cfg;
    int unpack_tail_trace_count;
`ifndef IMAGE_GEO_PERF_SINGLE_LIGHTWEIGHT
    longint unsigned prof_req_cycles;
    longint unsigned prof_wait_cycles;
    longint unsigned prof_out_cycles;
    longint unsigned prof_req_accepts;
    longint unsigned prof_rsp_count;
    longint unsigned prof_pix_fire_count;
    longint unsigned prof_req_stall_miss_count;
    longint unsigned prof_req_stall_decode_count;
    longint unsigned prof_req_stall_issue_count;
    longint unsigned prof_req_stall_prefetch_fill_count;
    longint unsigned prof_req_stall_demand_fill_count;
    longint unsigned prof_req_stall_read_busy_count;
    longint unsigned prof_req_stall_allhit_busy_count;
    longint unsigned prof_wait_no_rsp_count;
    longint unsigned prof_wait_decode_count;
    longint unsigned prof_wait_issue_count;
    longint unsigned prof_fill_prefetch_cycles;
    longint unsigned prof_fill_demand_cycles;
    longint unsigned prof_fill_read_busy_cycles;
    longint unsigned prof_fill_row_inflight_cycles;
    longint unsigned prof_dom_nonempty_cycles;
    longint unsigned prof_dom_fill_count;
    longint unsigned prof_dom_blocked_by_pending_count;
    longint unsigned prof_prefetch_geom_count;
    longint unsigned prof_prefetch_eval_count;
    longint unsigned prof_prefetch_sel1_count;
    longint unsigned prof_prefetch_sel2_count;
    longint unsigned prof_pending_nonempty_cycles;
    longint unsigned prof_prefetch_primary_valid_count;
    longint unsigned prof_prefetch_secondary_valid_count;
    longint unsigned prof_prefetch_tertiary_valid_count;
    longint unsigned prof_prefetch_primary_usable_count;
    longint unsigned prof_prefetch_secondary_usable_count;
    longint unsigned prof_prefetch_tertiary_usable_count;
    longint unsigned prof_dual_axis_count;
    longint unsigned prof_dual_frontier_count;
    longint unsigned prof_aggressive_count;
    longint unsigned prof_hold_prefetch_hit_count;
    longint unsigned prof_secondary_usable_no_fill_count;
    longint unsigned prof_secondary_usable_fill_count;
    longint unsigned prof_sched_x_valid_count;
    longint unsigned prof_sched_y_valid_count;
    longint unsigned prof_sched_diag_valid_count;
    longint unsigned prof_eval_primary_from_sched_x_count;
    longint unsigned prof_eval_primary_from_sched_y_count;
    longint unsigned prof_eval_primary_from_sched_diag_count;
    longint unsigned prof_eval_primary_from_legacy_count;
    longint unsigned prof_eval_gate_open_count;
    longint unsigned prof_eval_primary_usable_count;
    longint unsigned prof_eval_select1_count;
    longint unsigned prof_sel2_window_count;
    longint unsigned prof_sel2_primary_secondary_count;
    longint unsigned prof_sel2_frontier_count;
    longint unsigned prof_pending1_fill_window_count;
    longint unsigned prof_pending1_fill_primary_count;
    longint unsigned prof_pending1_fill_secondary_count;
    longint unsigned prof_pending1_fill_tertiary_count;
    longint unsigned prof_secondary_reject_current_count;
    longint unsigned prof_secondary_reject_hit_count;
    longint unsigned prof_secondary_reject_pending_count;
    longint unsigned prof_tertiary_reject_current_count;
    longint unsigned prof_tertiary_reject_hit_count;
    longint unsigned prof_tertiary_reject_pending_count;
    longint unsigned prof_eval_primary_valid_event_count;
    longint unsigned prof_eval_secondary_valid_event_count;
    longint unsigned prof_eval_tertiary_valid_event_count;
    longint unsigned prof_eval_secondary_usable_event_count;
    longint unsigned prof_eval_tertiary_usable_event_count;
    longint unsigned prof_eval_primary_secondary_usable_event_count;
    longint unsigned prof_eval_primary_tertiary_usable_event_count;
    longint unsigned prof_eval_primary_secondary_distinct_count;
    longint unsigned prof_eval_primary_tertiary_distinct_count;
    longint unsigned prof_eval_aggr_primary_secondary_count;
    longint unsigned prof_eval_aggr_primary_tertiary_count;
    longint unsigned prof_eval_aggr_p1clear_primary_secondary_count;
    longint unsigned prof_eval_aggr_p1clear_primary_tertiary_count;
    longint unsigned prof_eval_aggr_p1set_primary_secondary_count;
    longint unsigned prof_eval_aggr_p1set_primary_tertiary_count;
    longint unsigned prof_pending2_nonempty_cycles;
    longint unsigned prof_eval_aggr_p2clear_primary_secondary_count;
    longint unsigned prof_eval_aggr_p2clear_primary_tertiary_count;
    longint unsigned prof_eval_aggr_p2set_primary_secondary_count;
    longint unsigned prof_eval_aggr_p2set_primary_tertiary_count;
    longint unsigned prof_eval_aggr_no_fill_p2clear_primary_secondary_count;
    longint unsigned prof_eval_aggr_no_fill_p2clear_primary_tertiary_count;
    longint unsigned prof_sel2_with_sel1_count;
    longint unsigned prof_sel2_without_sel1_count;
    longint unsigned prof_p2fill_eligible_count;
    longint unsigned prof_p2fill_exact_eligible_count;
    longint unsigned prof_main_gate_hold_or_frontier_count;
    longint unsigned prof_select2_next_count;
    longint unsigned prof_select2_next_with_sel1_count;
    longint unsigned prof_select2_next_without_sel1_count;
    longint unsigned prof_eval_aggr_p0clear_primary_secondary_count;
    longint unsigned prof_eval_aggr_p0set_primary_secondary_count;
    longint unsigned prof_eval_aggr_fill_primary_secondary_count;
    longint unsigned prof_eval_aggr_nofill_primary_secondary_count;
    longint unsigned prof_eval_aggr_gateblocked_primary_secondary_count;
    longint unsigned prof_eval_aggr_gateblocked_p0set_primary_secondary_count;
    longint unsigned prof_eval_aggr_gateblocked_fill_primary_secondary_count;
    longint unsigned prof_miss_overlap_primary_count;
    longint unsigned prof_miss_overlap_secondary_count;
    longint unsigned prof_miss_overlap_tertiary_count;
    longint unsigned prof_miss_overlap_any_count;
    longint unsigned prof_miss_overlap_none_count;
    longint unsigned prof_lastmiss_overlap_primary_count;
    longint unsigned prof_lastmiss_overlap_secondary_count;
    longint unsigned prof_lastmiss_overlap_tertiary_count;
    longint unsigned prof_lastmiss_overlap_any_count;
    longint unsigned prof_lastmiss_overlap_none_count;
    longint unsigned prof_lastmiss_sched_x_count;
    longint unsigned prof_lastmiss_sched_y_count;
    longint unsigned prof_lastmiss_sched_diag_count;
    longint unsigned prof_lastmiss_legacy_p_count;
    longint unsigned prof_lastmiss_legacy_s_count;
    longint unsigned prof_lastmiss_legacy_t_count;
    longint unsigned prof_lastmiss_rel_x_count;
    longint unsigned prof_lastmiss_rel_y_count;
    longint unsigned prof_lastmiss_rel_diag_count;
    longint unsigned prof_lastmiss_rel_other_count;
    logic [15:0]       prof_last_miss_age;
    logic              prof_last_miss_valid;
    logic [15:0]       prof_last_miss_tile_x;
    logic [15:0]       prof_last_miss_tile_y;
`endif

    initial axi_clk = 1'b0;
    always #2.5 axi_clk = ~axi_clk;

    initial core_clk = 1'b0;
    always #5 core_clk = ~core_clk;

    image_geo_top #(
        .AXIL_ADDR_W(AXIL_ADDR_W),
        .AXIL_DATA_W(AXIL_DATA_W),
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_DATA_W(AXI_DATA_W),
        .AXI_ID_W(AXI_ID_W),
        .PIXEL_W(PIXEL_W),
        .MAX_SRC_W(7200),
        .MAX_SRC_H(7200),
        .MAX_DST_W(600),
        .MAX_DST_H(600),
        .LINE_NUM(2)
    ) dut (
        .axi_clk(axi_clk),
        .axi_rstn(axi_rstn),
        .core_clk(core_clk),
        .core_rstn(core_rstn),
        .irq(irq),
        .s_axi_ctrl_awaddr(s_axi_ctrl_awaddr),
        .s_axi_ctrl_awprot(s_axi_ctrl_awprot),
        .s_axi_ctrl_awvalid(s_axi_ctrl_awvalid),
        .s_axi_ctrl_awready(s_axi_ctrl_awready),
        .s_axi_ctrl_wdata(s_axi_ctrl_wdata),
        .s_axi_ctrl_wstrb(s_axi_ctrl_wstrb),
        .s_axi_ctrl_wvalid(s_axi_ctrl_wvalid),
        .s_axi_ctrl_wready(s_axi_ctrl_wready),
        .s_axi_ctrl_bresp(s_axi_ctrl_bresp),
        .s_axi_ctrl_bvalid(s_axi_ctrl_bvalid),
        .s_axi_ctrl_bready(s_axi_ctrl_bready),
        .s_axi_ctrl_araddr(s_axi_ctrl_araddr),
        .s_axi_ctrl_arprot(s_axi_ctrl_arprot),
        .s_axi_ctrl_arvalid(s_axi_ctrl_arvalid),
        .s_axi_ctrl_arready(s_axi_ctrl_arready),
        .s_axi_ctrl_rdata(s_axi_ctrl_rdata),
        .s_axi_ctrl_rresp(s_axi_ctrl_rresp),
        .s_axi_ctrl_rvalid(s_axi_ctrl_rvalid),
        .s_axi_ctrl_rready(s_axi_ctrl_rready),
        .m_axi_rd_arid(m_axi_rd_arid),
        .m_axi_rd_araddr(m_axi_rd_araddr),
        .m_axi_rd_arlen(m_axi_rd_arlen),
        .m_axi_rd_arsize(m_axi_rd_arsize),
        .m_axi_rd_arburst(m_axi_rd_arburst),
        .m_axi_rd_arlock(m_axi_rd_arlock),
        .m_axi_rd_arcache(m_axi_rd_arcache),
        .m_axi_rd_arprot(m_axi_rd_arprot),
        .m_axi_rd_arqos(m_axi_rd_arqos),
        .m_axi_rd_arregion(m_axi_rd_arregion),
        .m_axi_rd_arvalid(m_axi_rd_arvalid),
        .m_axi_rd_arready(m_axi_rd_arready),
        .m_axi_rd_rid(m_axi_rd_rid),
        .m_axi_rd_rdata(m_axi_rd_rdata),
        .m_axi_rd_rresp(m_axi_rd_rresp),
        .m_axi_rd_rlast(m_axi_rd_rlast),
        .m_axi_rd_rvalid(m_axi_rd_rvalid),
        .m_axi_rd_rready(m_axi_rd_rready),
        .m_axi_wr_awid(m_axi_wr_awid),
        .m_axi_wr_awaddr(m_axi_wr_awaddr),
        .m_axi_wr_awlen(m_axi_wr_awlen),
        .m_axi_wr_awsize(m_axi_wr_awsize),
        .m_axi_wr_awburst(m_axi_wr_awburst),
        .m_axi_wr_awlock(m_axi_wr_awlock),
        .m_axi_wr_awcache(m_axi_wr_awcache),
        .m_axi_wr_awprot(m_axi_wr_awprot),
        .m_axi_wr_awqos(m_axi_wr_awqos),
        .m_axi_wr_awregion(m_axi_wr_awregion),
        .m_axi_wr_awvalid(m_axi_wr_awvalid),
        .m_axi_wr_awready(m_axi_wr_awready),
        .m_axi_wr_wdata(m_axi_wr_wdata),
        .m_axi_wr_wstrb(m_axi_wr_wstrb),
        .m_axi_wr_wlast(m_axi_wr_wlast),
        .m_axi_wr_wvalid(m_axi_wr_wvalid),
        .m_axi_wr_wready(m_axi_wr_wready),
        .m_axi_wr_bid(m_axi_wr_bid),
        .m_axi_wr_bresp(m_axi_wr_bresp),
        .m_axi_wr_bvalid(m_axi_wr_bvalid),
        .m_axi_wr_bready(m_axi_wr_bready)
    );

    function automatic byte src_byte_at_addr(input logic [AXI_ADDR_W-1:0] addr);
        int unsigned offset;
        int unsigned x;
        int unsigned y;
        begin
            if (addr < SRC_BASE) begin
                src_byte_at_addr = 8'h00;
            end else begin
                offset = addr - SRC_BASE;
                y = offset / SRC_STRIDE;
                x = offset % SRC_STRIDE;
                src_byte_at_addr = byte'(((y * 29) + (x * 17) + ((x ^ y) * 3) + 7) & 8'hFF);
            end
        end
    endfunction

    task automatic reset_dut;
        begin
            axi_rstn           = 1'b0;
            core_rstn          = 1'b0;
            s_axi_ctrl_awaddr  = '0;
            s_axi_ctrl_awprot  = '0;
            s_axi_ctrl_awvalid = 1'b0;
            s_axi_ctrl_wdata   = '0;
            s_axi_ctrl_wstrb   = '0;
            s_axi_ctrl_wvalid  = 1'b0;
            s_axi_ctrl_bready  = 1'b0;
            s_axi_ctrl_araddr  = '0;
            s_axi_ctrl_arprot  = '0;
            s_axi_ctrl_arvalid = 1'b0;
            s_axi_ctrl_rready  = 1'b0;
            m_axi_rd_arready   = 1'b0;
            m_axi_rd_rid       = '0;
            m_axi_rd_rdata     = '0;
            m_axi_rd_rresp     = 2'b00;
            m_axi_rd_rlast     = 1'b0;
            m_axi_rd_rvalid    = 1'b0;
            m_axi_wr_awready   = 1'b0;
            m_axi_wr_wready    = 1'b0;
            m_axi_wr_bid       = '0;
            m_axi_wr_bresp     = 2'b00;
            m_axi_wr_bvalid    = 1'b0;
            rd_active_reg      = 1'b0;
            rd_head_reg        = 0;
            rd_tail_reg        = 0;
            rd_count_reg       = 0;
            wr_active_reg      = 1'b0;
            cycle_count        = 0;
            repeat (6) @(posedge axi_clk);
            axi_rstn  = 1'b1;
            core_rstn = 1'b1;
            repeat (2) @(posedge axi_clk);
        end
    endtask

    task automatic axil_write(input logic [AXIL_ADDR_W-1:0] addr, input logic [31:0] data);
        begin
            @(posedge axi_clk);
            s_axi_ctrl_awaddr  <= addr;
            s_axi_ctrl_awvalid <= 1'b1;
            s_axi_ctrl_wdata   <= data;
            s_axi_ctrl_wstrb   <= 4'hF;
            s_axi_ctrl_wvalid  <= 1'b1;
            s_axi_ctrl_bready  <= 1'b1;

            while (!(s_axi_ctrl_awready && s_axi_ctrl_wready)) begin
                @(posedge axi_clk);
            end

            @(posedge axi_clk);
            s_axi_ctrl_awvalid <= 1'b0;
            s_axi_ctrl_wvalid  <= 1'b0;

            while (!s_axi_ctrl_bvalid) begin
                @(posedge axi_clk);
            end

            if (s_axi_ctrl_bresp != 2'b00) begin
                $fatal(1, "AXI-Lite write response error at addr %h", addr);
            end

            @(posedge axi_clk);
            s_axi_ctrl_bready <= 1'b0;
        end
    endtask

    task automatic axil_read(input logic [AXIL_ADDR_W-1:0] addr, output logic [31:0] data);
        begin
            @(posedge axi_clk);
            s_axi_ctrl_araddr  <= addr;
            s_axi_ctrl_arvalid <= 1'b1;
            s_axi_ctrl_rready  <= 1'b1;

            while (!s_axi_ctrl_arready) begin
                @(posedge axi_clk);
            end

            @(posedge axi_clk);
            s_axi_ctrl_arvalid <= 1'b0;

            while (!s_axi_ctrl_rvalid) begin
                @(posedge axi_clk);
            end

            if (s_axi_ctrl_rresp != 2'b00) begin
                $fatal(1, "AXI-Lite read response error at addr %h", addr);
            end

            data = s_axi_ctrl_rdata;
            @(posedge axi_clk);
            s_axi_ctrl_rready <= 1'b0;
        end
    endtask

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn) begin
            m_axi_rd_arready    <= 1'b0;
            m_axi_rd_rvalid     <= 1'b0;
            m_axi_rd_rdata      <= '0;
            m_axi_rd_rresp      <= 2'b00;
            m_axi_rd_rlast      <= 1'b0;
            rd_active_reg       <= 1'b0;
            rd_active_addr_reg  <= '0;
            rd_active_beats_reg <= 0;
            rd_active_idx_reg   <= 0;
            rd_head_reg         <= 0;
            rd_tail_reg         <= 0;
            rd_count_reg        <= 0;
        end else begin
            m_axi_rd_arready <= (rd_count_reg < 63) && !( !rd_active_reg && (rd_count_reg != 0));

            if (m_axi_rd_arvalid && m_axi_rd_arready) begin
                if (rd_count_reg >= 64) begin
                    $fatal(1, "Read address queue overflow");
                end
                rd_addr_queue[rd_tail_reg]  <= m_axi_rd_araddr;
                rd_beats_queue[rd_tail_reg] <= m_axi_rd_arlen + 1;
                rd_tail_reg                 <= (rd_tail_reg + 1) % 64;
                rd_count_reg                <= rd_count_reg + 1;
            end

            if (!rd_active_reg && (rd_count_reg != 0)) begin
                rd_active_reg       <= 1'b1;
                rd_active_addr_reg  <= rd_addr_queue[rd_head_reg];
                rd_active_beats_reg <= rd_beats_queue[rd_head_reg];
                rd_active_idx_reg   <= 0;
                rd_head_reg         <= (rd_head_reg + 1) % 64;
                rd_count_reg        <= rd_count_reg - 1;
                m_axi_rd_rvalid     <= 1'b1;
                m_axi_rd_rdata      <= {
                    src_byte_at_addr(rd_addr_queue[rd_head_reg] + 3),
                    src_byte_at_addr(rd_addr_queue[rd_head_reg] + 2),
                    src_byte_at_addr(rd_addr_queue[rd_head_reg] + 1),
                    src_byte_at_addr(rd_addr_queue[rd_head_reg] + 0)
                };
                m_axi_rd_rresp      <= 2'b00;
                m_axi_rd_rlast      <= (rd_beats_queue[rd_head_reg] == 1);
            end else if (rd_active_reg && m_axi_rd_rvalid && m_axi_rd_rready) begin
                if (rd_active_idx_reg == (rd_active_beats_reg - 1)) begin
                    rd_active_reg   <= 1'b0;
                    m_axi_rd_rvalid <= 1'b0;
                    m_axi_rd_rlast  <= 1'b0;
                end else begin
                    rd_active_idx_reg <= rd_active_idx_reg + 1;
                    m_axi_rd_rvalid   <= 1'b1;
                    m_axi_rd_rdata    <= {
                        src_byte_at_addr(rd_active_addr_reg + (rd_active_idx_reg + 1)*BYTE_W + 3),
                        src_byte_at_addr(rd_active_addr_reg + (rd_active_idx_reg + 1)*BYTE_W + 2),
                        src_byte_at_addr(rd_active_addr_reg + (rd_active_idx_reg + 1)*BYTE_W + 1),
                        src_byte_at_addr(rd_active_addr_reg + (rd_active_idx_reg + 1)*BYTE_W + 0)
                    };
                    m_axi_rd_rresp <= 2'b00;
                    m_axi_rd_rlast <= ((rd_active_idx_reg + 1) == (rd_active_beats_reg - 1));
                end
            end else if (!rd_active_reg) begin
                m_axi_rd_rvalid <= 1'b0;
                m_axi_rd_rlast  <= 1'b0;
            end
        end
    end

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn) begin
            m_axi_wr_awready    <= 1'b0;
            m_axi_wr_wready     <= 1'b0;
            m_axi_wr_bvalid     <= 1'b0;
            m_axi_wr_bresp      <= 2'b00;
            wr_active_reg       <= 1'b0;
            wr_active_addr_reg  <= '0;
            wr_active_beats_reg <= 0;
            wr_active_idx_reg   <= 0;
        end else begin
            m_axi_wr_awready <= 1'b1;
            m_axi_wr_wready  <= 1'b1;

            if (m_axi_wr_awvalid && m_axi_wr_awready) begin
                wr_active_reg       <= 1'b1;
                wr_active_addr_reg  <= m_axi_wr_awaddr;
                wr_active_beats_reg <= m_axi_wr_awlen + 1;
                wr_active_idx_reg   <= 0;
            end

            if (m_axi_wr_wvalid && m_axi_wr_wready) begin
                if (!wr_active_reg) begin
                    $fatal(1, "Write data arrived before write address");
                end

                if (m_axi_wr_wlast != (wr_active_idx_reg == (wr_active_beats_reg - 1))) begin
                    $fatal(1, "WLAST mismatch");
                end

                if (wr_active_idx_reg == (wr_active_beats_reg - 1)) begin
                    wr_active_reg   <= 1'b0;
                    m_axi_wr_bvalid <= 1'b1;
                    m_axi_wr_bresp  <= 2'b00;
                end else begin
                    wr_active_idx_reg <= wr_active_idx_reg + 1;
                end
            end

            if (m_axi_wr_bvalid && m_axi_wr_bready) begin
                m_axi_wr_bvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

`ifndef IMAGE_GEO_PERF_SINGLE_LIGHTWEIGHT
    always_ff @(posedge core_clk) begin
        if (!core_rstn) begin
            unpack_tail_trace_count <= 0;
            prof_req_cycles <= 0;
            prof_wait_cycles <= 0;
            prof_out_cycles <= 0;
            prof_req_accepts <= 0;
            prof_rsp_count <= 0;
            prof_pix_fire_count <= 0;
            prof_req_stall_miss_count <= 0;
            prof_req_stall_decode_count <= 0;
            prof_req_stall_issue_count <= 0;
            prof_req_stall_prefetch_fill_count <= 0;
            prof_req_stall_demand_fill_count <= 0;
            prof_req_stall_read_busy_count <= 0;
            prof_req_stall_allhit_busy_count <= 0;
            prof_wait_no_rsp_count <= 0;
            prof_wait_decode_count <= 0;
            prof_wait_issue_count <= 0;
            prof_fill_prefetch_cycles <= 0;
            prof_fill_demand_cycles <= 0;
            prof_fill_read_busy_cycles <= 0;
            prof_fill_row_inflight_cycles <= 0;
            prof_dom_nonempty_cycles <= 0;
            prof_dom_fill_count <= 0;
            prof_dom_blocked_by_pending_count <= 0;
            prof_prefetch_geom_count <= 0;
            prof_prefetch_eval_count <= 0;
            prof_prefetch_sel1_count <= 0;
            prof_prefetch_sel2_count <= 0;
            prof_pending_nonempty_cycles <= 0;
            prof_prefetch_primary_valid_count <= 0;
            prof_prefetch_secondary_valid_count <= 0;
            prof_prefetch_tertiary_valid_count <= 0;
            prof_prefetch_primary_usable_count <= 0;
            prof_prefetch_secondary_usable_count <= 0;
            prof_prefetch_tertiary_usable_count <= 0;
            prof_dual_axis_count <= 0;
            prof_dual_frontier_count <= 0;
            prof_aggressive_count <= 0;
            prof_hold_prefetch_hit_count <= 0;
            prof_secondary_usable_no_fill_count <= 0;
            prof_secondary_usable_fill_count <= 0;
            prof_sched_x_valid_count <= 0;
            prof_sched_y_valid_count <= 0;
            prof_sched_diag_valid_count <= 0;
            prof_eval_primary_from_sched_x_count <= 0;
            prof_eval_primary_from_sched_y_count <= 0;
            prof_eval_primary_from_sched_diag_count <= 0;
            prof_eval_primary_from_legacy_count <= 0;
            prof_eval_gate_open_count <= 0;
            prof_eval_primary_usable_count <= 0;
            prof_eval_select1_count <= 0;
            prof_sel2_window_count <= 0;
            prof_sel2_primary_secondary_count <= 0;
            prof_sel2_frontier_count <= 0;
            prof_pending1_fill_window_count <= 0;
            prof_pending1_fill_primary_count <= 0;
            prof_pending1_fill_secondary_count <= 0;
            prof_pending1_fill_tertiary_count <= 0;
            prof_secondary_reject_current_count <= 0;
            prof_secondary_reject_hit_count <= 0;
            prof_secondary_reject_pending_count <= 0;
            prof_tertiary_reject_current_count <= 0;
            prof_tertiary_reject_hit_count <= 0;
            prof_tertiary_reject_pending_count <= 0;
            prof_eval_primary_valid_event_count <= 0;
            prof_eval_secondary_valid_event_count <= 0;
            prof_eval_tertiary_valid_event_count <= 0;
            prof_eval_secondary_usable_event_count <= 0;
            prof_eval_tertiary_usable_event_count <= 0;
            prof_eval_primary_secondary_usable_event_count <= 0;
            prof_eval_primary_tertiary_usable_event_count <= 0;
            prof_eval_primary_secondary_distinct_count <= 0;
            prof_eval_primary_tertiary_distinct_count <= 0;
            prof_eval_aggr_primary_secondary_count <= 0;
            prof_eval_aggr_primary_tertiary_count <= 0;
            prof_eval_aggr_p1clear_primary_secondary_count <= 0;
            prof_eval_aggr_p1clear_primary_tertiary_count <= 0;
            prof_eval_aggr_p1set_primary_secondary_count <= 0;
            prof_eval_aggr_p1set_primary_tertiary_count <= 0;
            prof_pending2_nonempty_cycles <= 0;
            prof_eval_aggr_p2clear_primary_secondary_count <= 0;
            prof_eval_aggr_p2clear_primary_tertiary_count <= 0;
            prof_eval_aggr_p2set_primary_secondary_count <= 0;
            prof_eval_aggr_p2set_primary_tertiary_count <= 0;
            prof_eval_aggr_no_fill_p2clear_primary_secondary_count <= 0;
            prof_eval_aggr_no_fill_p2clear_primary_tertiary_count <= 0;
            prof_sel2_with_sel1_count <= 0;
            prof_sel2_without_sel1_count <= 0;
            prof_p2fill_eligible_count <= 0;
            prof_p2fill_exact_eligible_count <= 0;
            prof_main_gate_hold_or_frontier_count <= 0;
            prof_select2_next_count <= 0;
            prof_select2_next_with_sel1_count <= 0;
            prof_select2_next_without_sel1_count <= 0;
            prof_eval_aggr_p0clear_primary_secondary_count <= 0;
            prof_eval_aggr_p0set_primary_secondary_count <= 0;
            prof_eval_aggr_fill_primary_secondary_count <= 0;
            prof_eval_aggr_nofill_primary_secondary_count <= 0;
            prof_eval_aggr_gateblocked_primary_secondary_count <= 0;
            prof_eval_aggr_gateblocked_p0set_primary_secondary_count <= 0;
            prof_eval_aggr_gateblocked_fill_primary_secondary_count <= 0;
            prof_miss_overlap_primary_count <= 0;
            prof_miss_overlap_secondary_count <= 0;
            prof_miss_overlap_tertiary_count <= 0;
            prof_miss_overlap_any_count <= 0;
            prof_miss_overlap_none_count <= 0;
            prof_lastmiss_overlap_primary_count <= 0;
            prof_lastmiss_overlap_secondary_count <= 0;
            prof_lastmiss_overlap_tertiary_count <= 0;
            prof_lastmiss_overlap_any_count <= 0;
            prof_lastmiss_overlap_none_count <= 0;
            prof_lastmiss_sched_x_count <= 0;
            prof_lastmiss_sched_y_count <= 0;
            prof_lastmiss_sched_diag_count <= 0;
            prof_lastmiss_legacy_p_count <= 0;
            prof_lastmiss_legacy_s_count <= 0;
            prof_lastmiss_legacy_t_count <= 0;
            prof_lastmiss_rel_x_count <= 0;
            prof_lastmiss_rel_y_count <= 0;
            prof_lastmiss_rel_diag_count <= 0;
            prof_lastmiss_rel_other_count <= 0;
            prof_last_miss_age <= '0;
            prof_last_miss_valid <= 1'b0;
            prof_last_miss_tile_x <= '0;
            prof_last_miss_tile_y <= '0;
        end else if (dut.u_ddr_read_engine.u_pixel_unpacker.task_active_reg &&
                     (dut.u_ddr_read_engine.u_pixel_unpacker.bytes_remaining_reg <= 2) &&
                     (unpack_tail_trace_count < 16)) begin
            unpack_tail_trace_count <= unpack_tail_trace_count + 1;
            $display("UNPACK_TAIL_TRACE cycle=%0d bytes=%0d word_valid=%0d valid_bytes=%0d done_seen=%0d out_v=%0d out_r=%0d fire=%0d fill_col=%0d row_inflight=%0d read_done=%0d",
                cycle_count,
                dut.u_ddr_read_engine.u_pixel_unpacker.bytes_remaining_reg,
                dut.u_ddr_read_engine.u_pixel_unpacker.current_word_valid_reg,
                dut.u_ddr_read_engine.u_pixel_unpacker.current_valid_bytes_reg,
                dut.u_ddr_read_engine.u_pixel_unpacker.reader_done_seen_reg,
                dut.read_out_valid,
                dut.read_out_ready,
                dut.u_ddr_read_engine.u_pixel_unpacker.pixel_fire,
                dut.u_src_tile_cache.fill_col_idx_reg,
                dut.u_src_tile_cache.row_inflight_reg,
                dut.cache_read_done);
        end else begin
            if (dut.u_rotate_core_bilinear.state_reg == dut.u_rotate_core_bilinear.S_REQ) begin
                prof_req_cycles <= prof_req_cycles + 1;
                if (dut.u_rotate_core_bilinear.sample_req_valid &&
                    !dut.u_rotate_core_bilinear.sample_req_ready) begin
                    if (!dut.u_src_tile_cache.hit00 || !dut.u_src_tile_cache.hit01 ||
                        !dut.u_src_tile_cache.hit10 || !dut.u_src_tile_cache.hit11) begin
                        prof_req_stall_miss_count <= prof_req_stall_miss_count + 1;
                    end
                    if (dut.u_src_tile_cache.sample_decode_valid_reg) begin
                        prof_req_stall_decode_count <= prof_req_stall_decode_count + 1;
                    end
                    if (dut.u_src_tile_cache.sample_issue_valid_reg) begin
                        prof_req_stall_issue_count <= prof_req_stall_issue_count + 1;
                    end
                    if (dut.u_src_tile_cache.fill_active_reg && dut.u_src_tile_cache.fill_is_prefetch_reg) begin
                        prof_req_stall_prefetch_fill_count <= prof_req_stall_prefetch_fill_count + 1;
                    end
                    if (dut.u_src_tile_cache.fill_active_reg && !dut.u_src_tile_cache.fill_is_prefetch_reg) begin
                        prof_req_stall_demand_fill_count <= prof_req_stall_demand_fill_count + 1;
                    end
                    if (dut.u_src_tile_cache.read_busy) begin
                        prof_req_stall_read_busy_count <= prof_req_stall_read_busy_count + 1;
                    end
                    if (dut.u_src_tile_cache.hit00 && dut.u_src_tile_cache.hit01 &&
                        dut.u_src_tile_cache.hit10 && dut.u_src_tile_cache.hit11) begin
                        prof_req_stall_allhit_busy_count <= prof_req_stall_allhit_busy_count + 1;
                    end
                end
            end
            if (dut.u_rotate_core_bilinear.state_reg == dut.u_rotate_core_bilinear.S_WAIT) begin
                prof_wait_cycles <= prof_wait_cycles + 1;
                if (!dut.u_src_tile_cache.sample_rsp_valid) begin
                    prof_wait_no_rsp_count <= prof_wait_no_rsp_count + 1;
                end
                if (dut.u_src_tile_cache.sample_decode_valid_reg) begin
                    prof_wait_decode_count <= prof_wait_decode_count + 1;
                end
                if (dut.u_src_tile_cache.sample_issue_valid_reg) begin
                    prof_wait_issue_count <= prof_wait_issue_count + 1;
                end
            end
            if (dut.u_rotate_core_bilinear.state_reg == dut.u_rotate_core_bilinear.S_OUT) begin
                prof_out_cycles <= prof_out_cycles + 1;
            end
            if (dut.u_rotate_core_bilinear.sample_req_valid && dut.u_rotate_core_bilinear.sample_req_ready) begin
                prof_req_accepts <= prof_req_accepts + 1;
            end
            if (dut.u_src_tile_cache.sample_rsp_valid) begin
                prof_rsp_count <= prof_rsp_count + 1;
            end
            if (dut.u_rotate_core_bilinear.pix_valid_reg && dut.u_rotate_core_bilinear.pix_ready) begin
                prof_pix_fire_count <= prof_pix_fire_count + 1;
            end
            if (dut.u_src_tile_cache.fill_active_reg && dut.u_src_tile_cache.fill_is_prefetch_reg) begin
                prof_fill_prefetch_cycles <= prof_fill_prefetch_cycles + 1;
            end
            if (dut.u_src_tile_cache.fill_active_reg && !dut.u_src_tile_cache.fill_is_prefetch_reg) begin
                prof_fill_demand_cycles <= prof_fill_demand_cycles + 1;
            end
            if (dut.u_src_tile_cache.fill_active_reg && dut.u_src_tile_cache.read_busy) begin
                prof_fill_read_busy_cycles <= prof_fill_read_busy_cycles + 1;
            end
            if (dut.u_src_tile_cache.fill_active_reg && dut.u_src_tile_cache.row_inflight_reg) begin
                prof_fill_row_inflight_cycles <= prof_fill_row_inflight_cycles + 1;
            end
            if (dut.u_src_tile_cache.prefetch_dom0_valid_reg ||
                dut.u_src_tile_cache.prefetch_dom1_valid_reg) begin
                prof_dom_nonempty_cycles <= prof_dom_nonempty_cycles + 1;
                if (dut.u_src_tile_cache.prefetch_pending0_valid_reg ||
                    dut.u_src_tile_cache.prefetch_pending1_valid_reg ||
                    dut.u_src_tile_cache.prefetch_pending2_valid_reg) begin
                    prof_dom_blocked_by_pending_count <= prof_dom_blocked_by_pending_count + 1;
                end
            end
            if (dut.u_src_tile_cache.fill_request_present &&
                dut.u_src_tile_cache.fill_request_is_prefetch &&
                ((dut.u_src_tile_cache.prefetch_dom0_valid_reg &&
                  (dut.u_src_tile_cache.prefetch_dom0_tile_x_reg == dut.u_src_tile_cache.fill_request_tile_x) &&
                  (dut.u_src_tile_cache.prefetch_dom0_tile_y_reg == dut.u_src_tile_cache.fill_request_tile_y)) ||
                 (dut.u_src_tile_cache.prefetch_dom1_valid_reg &&
                  (dut.u_src_tile_cache.prefetch_dom1_tile_x_reg == dut.u_src_tile_cache.fill_request_tile_x) &&
                  (dut.u_src_tile_cache.prefetch_dom1_tile_y_reg == dut.u_src_tile_cache.fill_request_tile_y)))) begin
                prof_dom_fill_count <= prof_dom_fill_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_geom_valid_reg) begin
                prof_prefetch_geom_count <= prof_prefetch_geom_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_eval_valid_reg) begin
                prof_prefetch_eval_count <= prof_prefetch_eval_count + 1;
                if (!dut.u_src_tile_cache.prefetch_eval_dual_axis_reg ||
                    dut.u_src_tile_cache.hold_prefetched_hit_now ||
                    dut.u_src_tile_cache.prefetch_eval_dual_frontier_reg ||
                    (dut.u_src_tile_cache.prefetch_eval_aggressive_reg &&
                     !dut.u_src_tile_cache.fill_active_reg &&
                     !dut.u_src_tile_cache.prefetch_pending0_valid_reg &&
                     !dut.u_src_tile_cache.prefetch_pending1_valid_reg &&
                     !dut.u_src_tile_cache.prefetch_pending2_valid_reg)) begin
                    prof_eval_gate_open_count <= prof_eval_gate_open_count + 1;
                end
                if (dut.u_src_tile_cache.prefetch_primary_usable) begin
                    prof_eval_primary_usable_count <= prof_eval_primary_usable_count + 1;
                end
                if (dut.u_src_tile_cache.prefetch_eval_primary_valid_reg) begin
                    prof_eval_primary_valid_event_count <= prof_eval_primary_valid_event_count + 1;
                end
                if (dut.u_src_tile_cache.prefetch_eval_secondary_valid_reg) begin
                    prof_eval_secondary_valid_event_count <= prof_eval_secondary_valid_event_count + 1;
                end
                if (dut.u_src_tile_cache.prefetch_eval_tertiary_valid_reg) begin
                    prof_eval_tertiary_valid_event_count <= prof_eval_tertiary_valid_event_count + 1;
                end
                if (dut.u_src_tile_cache.prefetch_secondary_usable) begin
                    prof_eval_secondary_usable_event_count <= prof_eval_secondary_usable_event_count + 1;
                end
                if (dut.u_src_tile_cache.prefetch_tertiary_usable) begin
                    prof_eval_tertiary_usable_event_count <= prof_eval_tertiary_usable_event_count + 1;
                end
                if (dut.u_src_tile_cache.prefetch_primary_usable &&
                    dut.u_src_tile_cache.prefetch_secondary_usable) begin
                    prof_eval_primary_secondary_usable_event_count <= prof_eval_primary_secondary_usable_event_count + 1;
                    if ((dut.u_src_tile_cache.prefetch_eval_primary_tile_x_reg != dut.u_src_tile_cache.prefetch_eval_secondary_tile_x_reg) ||
                        (dut.u_src_tile_cache.prefetch_eval_primary_tile_y_reg != dut.u_src_tile_cache.prefetch_eval_secondary_tile_y_reg)) begin
                        prof_eval_primary_secondary_distinct_count <= prof_eval_primary_secondary_distinct_count + 1;
                    end
                    if (dut.u_src_tile_cache.prefetch_eval_aggressive_reg) begin
                        prof_eval_aggr_primary_secondary_count <= prof_eval_aggr_primary_secondary_count + 1;
                        if (!dut.u_src_tile_cache.prefetch_pending0_valid_reg) begin
                            prof_eval_aggr_p0clear_primary_secondary_count <= prof_eval_aggr_p0clear_primary_secondary_count + 1;
                        end else begin
                            prof_eval_aggr_p0set_primary_secondary_count <= prof_eval_aggr_p0set_primary_secondary_count + 1;
                        end
                        if (!dut.u_src_tile_cache.prefetch_pending1_valid_reg) begin
                            prof_eval_aggr_p1clear_primary_secondary_count <= prof_eval_aggr_p1clear_primary_secondary_count + 1;
                        end else begin
                            prof_eval_aggr_p1set_primary_secondary_count <= prof_eval_aggr_p1set_primary_secondary_count + 1;
                        end
                        if (dut.u_src_tile_cache.fill_active_reg) begin
                            prof_eval_aggr_fill_primary_secondary_count <= prof_eval_aggr_fill_primary_secondary_count + 1;
                        end else begin
                            prof_eval_aggr_nofill_primary_secondary_count <= prof_eval_aggr_nofill_primary_secondary_count + 1;
                        end
                        if (!dut.u_src_tile_cache.prefetch_pending2_valid_reg) begin
                            prof_eval_aggr_p2clear_primary_secondary_count <= prof_eval_aggr_p2clear_primary_secondary_count + 1;
                            if (!dut.u_src_tile_cache.fill_active_reg) begin
                                prof_eval_aggr_no_fill_p2clear_primary_secondary_count <= prof_eval_aggr_no_fill_p2clear_primary_secondary_count + 1;
                            end
                        end else begin
                            prof_eval_aggr_p2set_primary_secondary_count <= prof_eval_aggr_p2set_primary_secondary_count + 1;
                        end
                        if (!(dut.u_src_tile_cache.hold_prefetched_hit_now ||
                              dut.u_src_tile_cache.prefetch_eval_dual_frontier_reg ||
                              (!dut.u_src_tile_cache.fill_active_reg &&
                               !dut.u_src_tile_cache.prefetch_pending0_valid_reg &&
                               !dut.u_src_tile_cache.prefetch_pending1_valid_reg &&
                               !dut.u_src_tile_cache.prefetch_pending2_valid_reg))) begin
                            prof_eval_aggr_gateblocked_primary_secondary_count <= prof_eval_aggr_gateblocked_primary_secondary_count + 1;
                            if (dut.u_src_tile_cache.prefetch_pending0_valid_reg) begin
                                prof_eval_aggr_gateblocked_p0set_primary_secondary_count <= prof_eval_aggr_gateblocked_p0set_primary_secondary_count + 1;
                            end
                            if (dut.u_src_tile_cache.fill_active_reg) begin
                                prof_eval_aggr_gateblocked_fill_primary_secondary_count <= prof_eval_aggr_gateblocked_fill_primary_secondary_count + 1;
                            end
                        end
                    end
                end
                if (dut.u_src_tile_cache.prefetch_primary_usable &&
                    dut.u_src_tile_cache.prefetch_tertiary_usable) begin
                    prof_eval_primary_tertiary_usable_event_count <= prof_eval_primary_tertiary_usable_event_count + 1;
                    if ((dut.u_src_tile_cache.prefetch_eval_primary_tile_x_reg != dut.u_src_tile_cache.prefetch_eval_tertiary_tile_x_reg) ||
                        (dut.u_src_tile_cache.prefetch_eval_primary_tile_y_reg != dut.u_src_tile_cache.prefetch_eval_tertiary_tile_y_reg)) begin
                        prof_eval_primary_tertiary_distinct_count <= prof_eval_primary_tertiary_distinct_count + 1;
                    end
                    if (dut.u_src_tile_cache.prefetch_eval_aggressive_reg) begin
                        prof_eval_aggr_primary_tertiary_count <= prof_eval_aggr_primary_tertiary_count + 1;
                        if (!dut.u_src_tile_cache.prefetch_pending1_valid_reg) begin
                            prof_eval_aggr_p1clear_primary_tertiary_count <= prof_eval_aggr_p1clear_primary_tertiary_count + 1;
                        end else begin
                            prof_eval_aggr_p1set_primary_tertiary_count <= prof_eval_aggr_p1set_primary_tertiary_count + 1;
                        end
                        if (!dut.u_src_tile_cache.prefetch_pending2_valid_reg) begin
                            prof_eval_aggr_p2clear_primary_tertiary_count <= prof_eval_aggr_p2clear_primary_tertiary_count + 1;
                            if (!dut.u_src_tile_cache.fill_active_reg) begin
                                prof_eval_aggr_no_fill_p2clear_primary_tertiary_count <= prof_eval_aggr_no_fill_p2clear_primary_tertiary_count + 1;
                            end
                        end else begin
                            prof_eval_aggr_p2set_primary_tertiary_count <= prof_eval_aggr_p2set_primary_tertiary_count + 1;
                        end
                    end
                end
                if (dut.u_src_tile_cache.prefetch_eval_aggressive_reg &&
                    !dut.u_src_tile_cache.prefetch_pending1_valid_reg) begin
                    prof_sel2_window_count <= prof_sel2_window_count + 1;
                    if (dut.u_src_tile_cache.prefetch_primary_usable &&
                        dut.u_src_tile_cache.prefetch_secondary_usable &&
                        ((dut.u_src_tile_cache.prefetch_eval_primary_tile_x_reg != dut.u_src_tile_cache.prefetch_eval_secondary_tile_x_reg) ||
                         (dut.u_src_tile_cache.prefetch_eval_primary_tile_y_reg != dut.u_src_tile_cache.prefetch_eval_secondary_tile_y_reg))) begin
                        prof_sel2_primary_secondary_count <= prof_sel2_primary_secondary_count + 1;
                    end
                    if (dut.u_src_tile_cache.prefetch_eval_dual_frontier_reg &&
                        dut.u_src_tile_cache.prefetch_tertiary_usable) begin
                        prof_sel2_frontier_count <= prof_sel2_frontier_count + 1;
                    end
                end
                if (dut.u_src_tile_cache.prefetch_eval_aggressive_reg &&
                    !dut.u_src_tile_cache.fill_active_reg &&
                    dut.u_src_tile_cache.prefetch_pending0_valid_reg &&
                    !dut.u_src_tile_cache.prefetch_pending1_valid_reg) begin
                    prof_pending1_fill_window_count <= prof_pending1_fill_window_count + 1;
                    if (dut.u_src_tile_cache.prefetch_primary_usable) begin
                        prof_pending1_fill_primary_count <= prof_pending1_fill_primary_count + 1;
                    end
                    if (dut.u_src_tile_cache.prefetch_secondary_usable) begin
                        prof_pending1_fill_secondary_count <= prof_pending1_fill_secondary_count + 1;
                    end
                    if (dut.u_src_tile_cache.prefetch_tertiary_usable) begin
                        prof_pending1_fill_tertiary_count <= prof_pending1_fill_tertiary_count + 1;
                    end
                end
                if (dut.u_src_tile_cache.prefetch_eval_aggressive_reg &&
                    !dut.u_src_tile_cache.fill_active_reg &&
                    !dut.u_src_tile_cache.prefetch_pending2_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_pending0_valid_reg ||
                     dut.u_src_tile_cache.prefetch_pending1_valid_reg) &&
                    (dut.u_src_tile_cache.prefetch_primary_usable ||
                     dut.u_src_tile_cache.prefetch_secondary_usable ||
                     dut.u_src_tile_cache.prefetch_tertiary_usable)) begin
                    prof_p2fill_eligible_count <= prof_p2fill_eligible_count + 1;
                end
                if (dut.u_src_tile_cache.prefetch_eval_aggressive_reg &&
                    !dut.u_src_tile_cache.prefetch_pending2_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_pending0_valid_reg ||
                     dut.u_src_tile_cache.prefetch_pending1_valid_reg) &&
                    (dut.u_src_tile_cache.prefetch_primary_usable ||
                     dut.u_src_tile_cache.prefetch_secondary_usable ||
                     dut.u_src_tile_cache.prefetch_tertiary_usable)) begin
                    prof_p2fill_exact_eligible_count <= prof_p2fill_exact_eligible_count + 1;
                    if (dut.u_src_tile_cache.hold_prefetched_hit_now ||
                        dut.u_src_tile_cache.prefetch_eval_dual_frontier_reg) begin
                        prof_main_gate_hold_or_frontier_count <= prof_main_gate_hold_or_frontier_count + 1;
                    end
                end
                if (dut.u_src_tile_cache.prefetch_select2_valid_next) begin
                    prof_select2_next_count <= prof_select2_next_count + 1;
                    if (dut.u_src_tile_cache.prefetch_select_valid_next) begin
                        prof_select2_next_with_sel1_count <= prof_select2_next_with_sel1_count + 1;
                    end else begin
                        prof_select2_next_without_sel1_count <= prof_select2_next_without_sel1_count + 1;
                    end
                end
                if (dut.u_src_tile_cache.prefetch_eval_secondary_valid_reg &&
                    !dut.u_src_tile_cache.prefetch_secondary_usable) begin
                    if (dut.u_src_tile_cache.tile_is_current_request(
                            dut.u_src_tile_cache.prefetch_eval_secondary_tile_x_reg,
                            dut.u_src_tile_cache.prefetch_eval_secondary_tile_y_reg)) begin
                        prof_secondary_reject_current_count <= prof_secondary_reject_current_count + 1;
                    end else if (dut.u_src_tile_cache.hit_tile(
                                       dut.u_src_tile_cache.prefetch_eval_secondary_tile_x_reg,
                                       dut.u_src_tile_cache.prefetch_eval_secondary_tile_y_reg,
                                       dut.u_src_tile_cache.prefetch_secondary_hit_slot_unused)) begin
                        prof_secondary_reject_hit_count <= prof_secondary_reject_hit_count + 1;
                    end else if (dut.u_src_tile_cache.tile_is_pending(
                                       dut.u_src_tile_cache.prefetch_eval_secondary_tile_x_reg,
                                       dut.u_src_tile_cache.prefetch_eval_secondary_tile_y_reg)) begin
                        prof_secondary_reject_pending_count <= prof_secondary_reject_pending_count + 1;
                    end
                end
                if (dut.u_src_tile_cache.prefetch_eval_tertiary_valid_reg &&
                    !dut.u_src_tile_cache.prefetch_tertiary_usable) begin
                    if (dut.u_src_tile_cache.tile_is_current_request(
                            dut.u_src_tile_cache.prefetch_eval_tertiary_tile_x_reg,
                            dut.u_src_tile_cache.prefetch_eval_tertiary_tile_y_reg)) begin
                        prof_tertiary_reject_current_count <= prof_tertiary_reject_current_count + 1;
                    end else if (dut.u_src_tile_cache.hit_tile(
                                       dut.u_src_tile_cache.prefetch_eval_tertiary_tile_x_reg,
                                       dut.u_src_tile_cache.prefetch_eval_tertiary_tile_y_reg,
                                       dut.u_src_tile_cache.prefetch_tertiary_hit_slot_unused)) begin
                        prof_tertiary_reject_hit_count <= prof_tertiary_reject_hit_count + 1;
                    end else if (dut.u_src_tile_cache.tile_is_pending(
                                       dut.u_src_tile_cache.prefetch_eval_tertiary_tile_x_reg,
                                       dut.u_src_tile_cache.prefetch_eval_tertiary_tile_y_reg)) begin
                        prof_tertiary_reject_pending_count <= prof_tertiary_reject_pending_count + 1;
                    end
                end
            end
            if (dut.u_src_tile_cache.prefetch_eval_primary_valid_reg) begin
                prof_prefetch_primary_valid_count <= prof_prefetch_primary_valid_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_eval_secondary_valid_reg) begin
                prof_prefetch_secondary_valid_count <= prof_prefetch_secondary_valid_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_eval_tertiary_valid_reg) begin
                prof_prefetch_tertiary_valid_count <= prof_prefetch_tertiary_valid_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_primary_usable) begin
                prof_prefetch_primary_usable_count <= prof_prefetch_primary_usable_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_secondary_usable) begin
                prof_prefetch_secondary_usable_count <= prof_prefetch_secondary_usable_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_tertiary_usable) begin
                prof_prefetch_tertiary_usable_count <= prof_prefetch_tertiary_usable_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_eval_dual_axis_reg) begin
                prof_dual_axis_count <= prof_dual_axis_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_eval_dual_frontier_reg) begin
                prof_dual_frontier_count <= prof_dual_frontier_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_eval_aggressive_reg) begin
                prof_aggressive_count <= prof_aggressive_count + 1;
            end
            if (dut.u_src_tile_cache.hold_prefetched_hit_now) begin
                prof_hold_prefetch_hit_count <= prof_hold_prefetch_hit_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_geom_scheduler_x_valid_reg) begin
                prof_sched_x_valid_count <= prof_sched_x_valid_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_geom_scheduler_y_valid_reg) begin
                prof_sched_y_valid_count <= prof_sched_y_valid_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_geom_scheduler_diag_valid_reg) begin
                prof_sched_diag_valid_count <= prof_sched_diag_valid_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_secondary_usable && !dut.u_src_tile_cache.fill_active_reg) begin
                prof_secondary_usable_no_fill_count <= prof_secondary_usable_no_fill_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_secondary_usable && dut.u_src_tile_cache.fill_active_reg) begin
                prof_secondary_usable_fill_count <= prof_secondary_usable_fill_count + 1;
            end
            if (dut.u_src_tile_cache.prefetch_eval_primary_valid_reg) begin
                if (dut.u_src_tile_cache.prefetch_eval_primary_tile_x_reg == dut.u_src_tile_cache.prefetch_geom_scheduler_x_tile_x_reg &&
                    dut.u_src_tile_cache.prefetch_eval_primary_tile_y_reg == dut.u_src_tile_cache.prefetch_geom_scheduler_x_tile_y_reg &&
                    dut.u_src_tile_cache.prefetch_geom_scheduler_x_valid_reg) begin
                    prof_eval_primary_from_sched_x_count <= prof_eval_primary_from_sched_x_count + 1;
                end else if (dut.u_src_tile_cache.prefetch_eval_primary_tile_x_reg == dut.u_src_tile_cache.prefetch_geom_scheduler_y_tile_x_reg &&
                             dut.u_src_tile_cache.prefetch_eval_primary_tile_y_reg == dut.u_src_tile_cache.prefetch_geom_scheduler_y_tile_y_reg &&
                             dut.u_src_tile_cache.prefetch_geom_scheduler_y_valid_reg) begin
                    prof_eval_primary_from_sched_y_count <= prof_eval_primary_from_sched_y_count + 1;
                end else if (dut.u_src_tile_cache.prefetch_eval_primary_tile_x_reg == dut.u_src_tile_cache.prefetch_geom_scheduler_diag_tile_x_reg &&
                             dut.u_src_tile_cache.prefetch_eval_primary_tile_y_reg == dut.u_src_tile_cache.prefetch_geom_scheduler_diag_tile_y_reg &&
                             dut.u_src_tile_cache.prefetch_geom_scheduler_diag_valid_reg) begin
                    prof_eval_primary_from_sched_diag_count <= prof_eval_primary_from_sched_diag_count + 1;
                end else begin
                    prof_eval_primary_from_legacy_count <= prof_eval_primary_from_legacy_count + 1;
                end
            end
            if (dut.u_src_tile_cache.prefetch_select_valid_reg) begin
                prof_prefetch_sel1_count <= prof_prefetch_sel1_count + 1;
                if (dut.u_src_tile_cache.prefetch_eval_valid_reg) begin
                    prof_eval_select1_count <= prof_eval_select1_count + 1;
                end
            end
            if (dut.u_src_tile_cache.prefetch_select2_valid_reg) begin
                prof_prefetch_sel2_count <= prof_prefetch_sel2_count + 1;
                if (dut.u_src_tile_cache.prefetch_select_valid_reg) begin
                    prof_sel2_with_sel1_count <= prof_sel2_with_sel1_count + 1;
                end else begin
                    prof_sel2_without_sel1_count <= prof_sel2_without_sel1_count + 1;
                end
            end
            if (dut.u_src_tile_cache.prefetch_pending0_valid_reg || dut.u_src_tile_cache.prefetch_pending1_valid_reg) begin
                prof_pending_nonempty_cycles <= prof_pending_nonempty_cycles + 1;
            end
            if (dut.u_src_tile_cache.prefetch_pending2_valid_reg) begin
                prof_pending2_nonempty_cycles <= prof_pending2_nonempty_cycles + 1;
            end
            if (dut.u_src_tile_cache.miss_present) begin
                prof_last_miss_valid <= 1'b1;
                prof_last_miss_age <= '0;
                prof_last_miss_tile_x <= dut.u_src_tile_cache.miss_tile_x;
                prof_last_miss_tile_y <= dut.u_src_tile_cache.miss_tile_y;
            end else if (prof_last_miss_valid && (prof_last_miss_age != 16'hffff)) begin
                prof_last_miss_age <= prof_last_miss_age + 1'b1;
            end

            if (dut.u_src_tile_cache.miss_present && dut.u_src_tile_cache.prefetch_eval_valid_reg) begin
                bit miss_on_primary;
                bit miss_on_secondary;
                bit miss_on_tertiary;

                miss_on_primary =
                    dut.u_src_tile_cache.prefetch_eval_primary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_eval_primary_tile_x_reg == dut.u_src_tile_cache.miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_eval_primary_tile_y_reg == dut.u_src_tile_cache.miss_tile_y);
                miss_on_secondary =
                    dut.u_src_tile_cache.prefetch_eval_secondary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_eval_secondary_tile_x_reg == dut.u_src_tile_cache.miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_eval_secondary_tile_y_reg == dut.u_src_tile_cache.miss_tile_y);
                miss_on_tertiary =
                    dut.u_src_tile_cache.prefetch_eval_tertiary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_eval_tertiary_tile_x_reg == dut.u_src_tile_cache.miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_eval_tertiary_tile_y_reg == dut.u_src_tile_cache.miss_tile_y);

                if (miss_on_primary) begin
                    prof_miss_overlap_primary_count <= prof_miss_overlap_primary_count + 1;
                end
                if (miss_on_secondary) begin
                    prof_miss_overlap_secondary_count <= prof_miss_overlap_secondary_count + 1;
                end
                if (miss_on_tertiary) begin
                    prof_miss_overlap_tertiary_count <= prof_miss_overlap_tertiary_count + 1;
                end
                if (miss_on_primary || miss_on_secondary || miss_on_tertiary) begin
                    prof_miss_overlap_any_count <= prof_miss_overlap_any_count + 1;
                end else begin
                    prof_miss_overlap_none_count <= prof_miss_overlap_none_count + 1;
                end
            end
            if (prof_last_miss_valid &&
                (prof_last_miss_age <= 16'd8) &&
                dut.u_src_tile_cache.prefetch_eval_valid_reg) begin
                bit lastmiss_on_primary;
                bit lastmiss_on_secondary;
                bit lastmiss_on_tertiary;
                bit lastmiss_on_sched_x;
                bit lastmiss_on_sched_y;
                bit lastmiss_on_sched_diag;
                bit lastmiss_on_legacy_p;
                bit lastmiss_on_legacy_s;
                bit lastmiss_on_legacy_t;
                bit lastmiss_rel_x;
                bit lastmiss_rel_y;
                bit lastmiss_rel_diag;

                lastmiss_on_primary =
                    dut.u_src_tile_cache.prefetch_eval_primary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_eval_primary_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_eval_primary_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_on_secondary =
                    dut.u_src_tile_cache.prefetch_eval_secondary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_eval_secondary_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_eval_secondary_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_on_tertiary =
                    dut.u_src_tile_cache.prefetch_eval_tertiary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_eval_tertiary_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_eval_tertiary_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_on_sched_x =
                    dut.u_src_tile_cache.prefetch_geom_scheduler_x_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_geom_scheduler_x_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_geom_scheduler_x_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_on_sched_y =
                    dut.u_src_tile_cache.prefetch_geom_scheduler_y_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_geom_scheduler_y_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_geom_scheduler_y_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_on_sched_diag =
                    dut.u_src_tile_cache.prefetch_geom_scheduler_diag_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_geom_scheduler_diag_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_geom_scheduler_diag_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_on_legacy_p =
                    dut.u_src_tile_cache.prefetch_geom_primary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_geom_primary_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_geom_primary_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_on_legacy_s =
                    dut.u_src_tile_cache.prefetch_geom_secondary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_geom_secondary_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_geom_secondary_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_on_legacy_t =
                    dut.u_src_tile_cache.prefetch_geom_tertiary_valid_reg &&
                    (dut.u_src_tile_cache.prefetch_geom_tertiary_tile_x_reg == prof_last_miss_tile_x) &&
                    (dut.u_src_tile_cache.prefetch_geom_tertiary_tile_y_reg == prof_last_miss_tile_y);
                lastmiss_rel_x =
                    ((prof_last_miss_tile_x == (dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg + 1'b1)) &&
                     ((prof_last_miss_tile_y == dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg) ||
                      (prof_last_miss_tile_y == dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg))) ||
                    ((dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg != 0) &&
                     (prof_last_miss_tile_x == (dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg - 1'b1)) &&
                     ((prof_last_miss_tile_y == dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg) ||
                      (prof_last_miss_tile_y == dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg))) ||
                    ((prof_last_miss_tile_x == (dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg + 1'b1)) &&
                     ((prof_last_miss_tile_y == dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg) ||
                      (prof_last_miss_tile_y == dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg))) ||
                    ((dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg != 0) &&
                     (prof_last_miss_tile_x == (dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg - 1'b1)) &&
                     ((prof_last_miss_tile_y == dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg) ||
                      (prof_last_miss_tile_y == dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg)));
                lastmiss_rel_y =
                    ((prof_last_miss_tile_y == (dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg + 1'b1)) &&
                     ((prof_last_miss_tile_x == dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg) ||
                      (prof_last_miss_tile_x == dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg))) ||
                    ((dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg != 0) &&
                     (prof_last_miss_tile_y == (dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg - 1'b1)) &&
                     ((prof_last_miss_tile_x == dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg) ||
                      (prof_last_miss_tile_x == dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg))) ||
                    ((prof_last_miss_tile_y == (dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg + 1'b1)) &&
                     ((prof_last_miss_tile_x == dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg) ||
                      (prof_last_miss_tile_x == dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg))) ||
                    ((dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg != 0) &&
                     (prof_last_miss_tile_y == (dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg - 1'b1)) &&
                     ((prof_last_miss_tile_x == dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg) ||
                      (prof_last_miss_tile_x == dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg)));
                lastmiss_rel_diag =
                    (((prof_last_miss_tile_x == (dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg + 1'b1)) ||
                      ((dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg != 0) &&
                       (prof_last_miss_tile_x == (dut.u_src_tile_cache.prefetch_eval_req_tile_x00_reg - 1'b1)))) &&
                     ((prof_last_miss_tile_y == (dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg + 1'b1)) ||
                      ((dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg != 0) &&
                       (prof_last_miss_tile_y == (dut.u_src_tile_cache.prefetch_eval_req_tile_y00_reg - 1'b1))))) ||
                    (((prof_last_miss_tile_x == (dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg + 1'b1)) ||
                      ((dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg != 0) &&
                       (prof_last_miss_tile_x == (dut.u_src_tile_cache.prefetch_eval_req_tile_x01_reg - 1'b1)))) &&
                     ((prof_last_miss_tile_y == (dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg + 1'b1)) ||
                      ((dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg != 0) &&
                       (prof_last_miss_tile_y == (dut.u_src_tile_cache.prefetch_eval_req_tile_y10_reg - 1'b1)))));

                if (lastmiss_on_primary) begin
                    prof_lastmiss_overlap_primary_count <= prof_lastmiss_overlap_primary_count + 1;
                end
                if (lastmiss_on_secondary) begin
                    prof_lastmiss_overlap_secondary_count <= prof_lastmiss_overlap_secondary_count + 1;
                end
                if (lastmiss_on_tertiary) begin
                    prof_lastmiss_overlap_tertiary_count <= prof_lastmiss_overlap_tertiary_count + 1;
                end
                if (lastmiss_on_primary || lastmiss_on_secondary || lastmiss_on_tertiary) begin
                    prof_lastmiss_overlap_any_count <= prof_lastmiss_overlap_any_count + 1;
                end else begin
                    prof_lastmiss_overlap_none_count <= prof_lastmiss_overlap_none_count + 1;
                end
                if (lastmiss_on_sched_x) begin
                    prof_lastmiss_sched_x_count <= prof_lastmiss_sched_x_count + 1;
                end
                if (lastmiss_on_sched_y) begin
                    prof_lastmiss_sched_y_count <= prof_lastmiss_sched_y_count + 1;
                end
                if (lastmiss_on_sched_diag) begin
                    prof_lastmiss_sched_diag_count <= prof_lastmiss_sched_diag_count + 1;
                end
                if (lastmiss_on_legacy_p) begin
                    prof_lastmiss_legacy_p_count <= prof_lastmiss_legacy_p_count + 1;
                end
                if (lastmiss_on_legacy_s) begin
                    prof_lastmiss_legacy_s_count <= prof_lastmiss_legacy_s_count + 1;
                end
                if (lastmiss_on_legacy_t) begin
                    prof_lastmiss_legacy_t_count <= prof_lastmiss_legacy_t_count + 1;
                end
                if (lastmiss_rel_diag) begin
                    prof_lastmiss_rel_diag_count <= prof_lastmiss_rel_diag_count + 1;
                end else if (lastmiss_rel_x) begin
                    prof_lastmiss_rel_x_count <= prof_lastmiss_rel_x_count + 1;
                end else if (lastmiss_rel_y) begin
                    prof_lastmiss_rel_y_count <= prof_lastmiss_rel_y_count + 1;
                end else begin
                    prof_lastmiss_rel_other_count <= prof_lastmiss_rel_other_count + 1;
                end
            end
        end
    end
`endif

    task automatic wait_for_irq;
        logic [31:0] status_data;
        logic [31:0] reads;
        logic [31:0] misses;
        logic [31:0] prefetches;
        logic [31:0] prefetch_hits;
        begin
            while (!irq) begin
                @(posedge axi_clk);
                if (cycle_count > TIMEOUT_CYCLES) begin
                    axil_read(12'h01C, status_data);
                    read_cache_stats(reads, misses, prefetches, prefetch_hits);
`ifdef IMAGE_GEO_PERF_SINGLE_LIGHTWEIGHT
                    $display("PERF_SINGLE_TIMEOUT case=%s prefetch=%0d cycles=%0d status=0x%08h reads=%0d misses=%0d prefetches=%0d hits=%0d",
                        CASE_NAME, PREFETCH_EN, cycle_count, status_data,
                        reads, misses, prefetches, prefetch_hits);
`else
                    $display("PERF_SINGLE_TIMEOUT_TRACE2 case=%s prefetch=%0d cycles=%0d status=0x%08h reads=%0d misses=%0d prefetches=%0d hits=%0d core_state=%0d dst=(%0d,%0d) precalc_idx=%0d row_adv_done=%0d cache_req_ready=%0d miss_present=%0d miss_tile=(%0d,%0d) fill_req=%0d fill_active=%0d fill_plan=%0d row_inflight=%0d read_busy=%0d read_start=%0d read_pending=%0d start_ready=%0d read_addr=0x%08h read_bytes=%0d fill_row=%0d fill_col=%0d geom_init=%0d hits4=%0d%0d%0d%0d rd_task_active=%0d rd_task_accept=%0d rd_task_input_start=%0d rd_task_input_bytes=%0d rd_task_ready_core=%0d rd_task_valid_axi=%0d rd_task_ready_axi=%0d rd_done_level=%0d rd_err_level=%0d rd_reader_state=%0d rd_arvalid=%0d rd_arready=%0d rd_rvalid=%0d rd_rready=%0d rd_beats=%0d rd_bursts=%0d cdc_req_src=%0d cdc_ack_dst=%0d cdc_ack_s1=%0d cdc_ack_s2=%0d cdc_req_d1=%0d cdc_req_d2=%0d cdc_seen=%0d res_valid_axi=%0d res_done_axi=%0d res_err_axi=%0d res_valid_core=%0d res_done_core=%0d res_err_core=%0d read_out_valid=%0d read_out_ready=%0d pixel_fire=%0d unpack_start=%0d unpack_active=%0d unpack_bytes=%0d unpack_done_seen=%0d unpack_err=%0d unpack_done_calc=%0d unpack_err_calc=%0d unpack_done_level=%0d unpack_err_level=%0d unpack_done_pulse=%0d unpack_err_pulse=%0d unpack_word_valid=%0d unpack_valid_bytes=%0d fifo_empty=%0d",
                        CASE_NAME, PREFETCH_EN, cycle_count, status_data, reads, misses, prefetches, prefetch_hits,
                        dut.u_rotate_core_bilinear.state_reg,
                        dut.u_rotate_core_bilinear.dst_x_reg,
                        dut.u_rotate_core_bilinear.dst_y_reg,
                        dut.u_rotate_core_bilinear.precalc_idx_reg,
                        dut.u_rotate_core_bilinear.row_adv_done_reg,
                        dut.u_src_tile_cache.sample_req_ready,
                        dut.u_src_tile_cache.miss_present,
                        dut.u_src_tile_cache.miss_tile_x,
                        dut.u_src_tile_cache.miss_tile_y,
                        dut.u_src_tile_cache.fill_request_present,
                        dut.u_src_tile_cache.fill_active_reg,
                        dut.u_src_tile_cache.fill_plan_valid_reg,
                        dut.u_src_tile_cache.row_inflight_reg,
                        dut.u_src_tile_cache.read_busy,
                        dut.u_src_tile_cache.read_start_reg,
                        dut.u_src_tile_cache.read_issue_pending_reg,
                        dut.cache_read_start_ready,
                        dut.u_src_tile_cache.read_addr_reg,
                        dut.u_src_tile_cache.read_byte_count_reg,
                        dut.u_src_tile_cache.fill_row_idx_reg,
                        dut.u_src_tile_cache.fill_col_idx_reg,
                        dut.u_src_tile_cache.cfg_geom_init_pending_reg,
                        dut.u_src_tile_cache.hit00,
                        dut.u_src_tile_cache.hit01,
                        dut.u_src_tile_cache.hit10,
                        dut.u_src_tile_cache.hit11,
                        dut.u_ddr_read_engine.task_active_reg,
                        dut.u_ddr_read_engine.task_start_accept,
                        dut.u_ddr_read_engine.task_start,
                        dut.u_ddr_read_engine.task_byte_count,
                        dut.u_ddr_read_engine.task_ready_core,
                        dut.u_ddr_read_engine.task_valid_axi,
                        dut.u_ddr_read_engine.task_ready_axi,
                        dut.u_ddr_read_engine.unpacker_done_level,
                        dut.u_ddr_read_engine.unpacker_error_level,
                        dut.u_ddr_read_engine.u_axi_burst_reader.state_reg,
                        dut.u_ddr_read_engine.m_axi_rd.arvalid,
                        dut.u_ddr_read_engine.m_axi_rd.arready,
                        dut.u_ddr_read_engine.m_axi_rd.rvalid,
                        dut.u_ddr_read_engine.m_axi_rd.rready,
                        dut.u_ddr_read_engine.u_axi_burst_reader.beats_inflight_reg,
                        dut.u_ddr_read_engine.u_axi_burst_reader.bursts_inflight_reg,
                        dut.u_ddr_read_engine.u_task_cdc.req_toggle_src_reg,
                        dut.u_ddr_read_engine.u_task_cdc.ack_toggle_dst_reg,
                        dut.u_ddr_read_engine.u_task_cdc.ack_toggle_src_sync1_reg,
                        dut.u_ddr_read_engine.u_task_cdc.ack_toggle_src_sync2_reg,
                        dut.u_ddr_read_engine.u_task_cdc.req_toggle_dst_sync1_reg,
                        dut.u_ddr_read_engine.u_task_cdc.req_toggle_dst_sync2_reg,
                        dut.u_ddr_read_engine.u_task_cdc.req_toggle_dst_seen_reg,
                        dut.u_ddr_read_engine.result_valid_axi,
                        dut.u_ddr_read_engine.result_done_axi,
                        dut.u_ddr_read_engine.result_error_axi,
                        dut.u_ddr_read_engine.result_valid_core,
                        dut.u_ddr_read_engine.result_done_evt_core,
                        dut.u_ddr_read_engine.result_error_evt_core,
                        dut.read_out_valid,
                        dut.read_out_ready,
                        dut.u_ddr_read_engine.u_pixel_unpacker.pixel_fire,
                        dut.u_ddr_read_engine.task_start_accept,
                        dut.u_ddr_read_engine.u_pixel_unpacker.task_active_reg,
                        dut.u_ddr_read_engine.u_pixel_unpacker.bytes_remaining_reg,
                        dut.u_ddr_read_engine.u_pixel_unpacker.reader_done_seen_reg,
                        dut.u_ddr_read_engine.u_pixel_unpacker.task_error_flag,
                        dut.u_ddr_read_engine.u_pixel_unpacker.terminal_done_calc,
                        dut.u_ddr_read_engine.u_pixel_unpacker.terminal_error_calc,
                        dut.u_ddr_read_engine.u_pixel_unpacker.task_done_level,
                        dut.u_ddr_read_engine.u_pixel_unpacker.task_error_level,
                        dut.u_ddr_read_engine.unpacker_done_pulse,
                        dut.u_ddr_read_engine.unpacker_error_pulse,
                        dut.u_ddr_read_engine.u_pixel_unpacker.current_word_valid_reg,
                        dut.u_ddr_read_engine.u_pixel_unpacker.current_valid_bytes_reg,
                        dut.u_ddr_read_engine.u_pixel_unpacker.fifo_empty);
                    $display("PERF_SINGLE_PROFILE req_cycles=%0d wait_cycles=%0d out_cycles=%0d req_accepts=%0d rsp=%0d pix=%0d cache_reads=%0d cache_misses=%0d cache_prefetch=%0d cache_hits=%0d corewait=%0d/%0d/%0d/%0d/%0d/%0d/%0d waitpipe=%0d/%0d/%0d fillcyc=%0d/%0d/%0d/%0d prefetch_geom=%0d prefetch_eval=%0d prefetch_sel1=%0d prefetch_sel2=%0d pending_cycles=%0d/%0d p_valid=%0d/%0d/%0d p_usable=%0d/%0d/%0d rej2=%0d/%0d/%0d rej3=%0d/%0d/%0d eval_evt=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d aggr_evt=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d sel2_src=%0d/%0d/%0d/%0d/%0d sel2_next=%0d/%0d/%0d gate=%0d/%0d/%0d/%0d sec_fill=%0d/%0d sched=%0d/%0d/%0d primary_src=%0d/%0d/%0d/%0d eval=%0d/%0d/%0d sel2_opp=%0d/%0d/%0d p1fill=%0d/%0d/%0d/%0d p0blk=%0d/%0d/%0d/%0d/%0d/%0d/%0d missov=%0d/%0d/%0d/%0d/%0d lastmiss=%0d/%0d/%0d/%0d/%0d lm_src=%0d/%0d/%0d/%0d/%0d/%0d lm_rel=%0d/%0d/%0d/%0d domq=%0d/%0d/%0d",
                        prof_req_cycles, prof_wait_cycles, prof_out_cycles,
                        prof_req_accepts, prof_rsp_count, prof_pix_fire_count,
                        dut.u_src_tile_cache.stat_read_starts_reg,
                        dut.u_src_tile_cache.stat_misses_reg,
                        dut.u_src_tile_cache.stat_prefetch_starts_reg,
                        dut.u_src_tile_cache.stat_prefetch_hits_reg,
                        prof_req_stall_miss_count,
                        prof_req_stall_decode_count,
                        prof_req_stall_issue_count,
                        prof_req_stall_prefetch_fill_count,
                        prof_req_stall_demand_fill_count,
                        prof_req_stall_read_busy_count,
                        prof_req_stall_allhit_busy_count,
                        prof_wait_no_rsp_count,
                        prof_wait_decode_count,
                        prof_wait_issue_count,
                        prof_fill_prefetch_cycles,
                        prof_fill_demand_cycles,
                        prof_fill_read_busy_cycles,
                        prof_fill_row_inflight_cycles,
                        prof_prefetch_geom_count, prof_prefetch_eval_count,
                        prof_prefetch_sel1_count, prof_prefetch_sel2_count,
                        prof_pending_nonempty_cycles,
                        prof_pending2_nonempty_cycles,
                        prof_prefetch_primary_valid_count,
                        prof_prefetch_secondary_valid_count,
                        prof_prefetch_tertiary_valid_count,
                        prof_prefetch_primary_usable_count,
                        prof_prefetch_secondary_usable_count,
                        prof_prefetch_tertiary_usable_count,
                        prof_secondary_reject_current_count,
                        prof_secondary_reject_hit_count,
                        prof_secondary_reject_pending_count,
                        prof_tertiary_reject_current_count,
                        prof_tertiary_reject_hit_count,
                        prof_tertiary_reject_pending_count,
                        prof_eval_primary_valid_event_count,
                        prof_eval_secondary_valid_event_count,
                        prof_eval_tertiary_valid_event_count,
                        prof_eval_secondary_usable_event_count,
                        prof_eval_tertiary_usable_event_count,
                        prof_eval_primary_secondary_usable_event_count,
                        prof_eval_primary_tertiary_usable_event_count,
                        prof_eval_primary_secondary_distinct_count,
                        prof_eval_primary_tertiary_distinct_count,
                        prof_eval_aggr_primary_secondary_count,
                        prof_eval_aggr_primary_tertiary_count,
                        prof_eval_aggr_p1clear_primary_secondary_count,
                        prof_eval_aggr_p1clear_primary_tertiary_count,
                        prof_eval_aggr_p1set_primary_secondary_count,
                        prof_eval_aggr_p1set_primary_tertiary_count,
                        prof_eval_aggr_p2clear_primary_secondary_count,
                        prof_eval_aggr_p2clear_primary_tertiary_count,
                        prof_eval_aggr_p2set_primary_secondary_count,
                        prof_eval_aggr_p2set_primary_tertiary_count,
                        prof_eval_aggr_no_fill_p2clear_primary_secondary_count,
                        prof_eval_aggr_no_fill_p2clear_primary_tertiary_count,
                        prof_sel2_with_sel1_count,
                        prof_sel2_without_sel1_count,
                        prof_p2fill_eligible_count,
                        prof_p2fill_exact_eligible_count,
                        prof_main_gate_hold_or_frontier_count,
                        prof_select2_next_count,
                        prof_select2_next_with_sel1_count,
                        prof_select2_next_without_sel1_count,
                        prof_dual_axis_count,
                        prof_dual_frontier_count,
                        prof_aggressive_count,
                        prof_hold_prefetch_hit_count,
                        prof_secondary_usable_no_fill_count,
                        prof_secondary_usable_fill_count,
                        prof_sched_x_valid_count,
                        prof_sched_y_valid_count,
                        prof_sched_diag_valid_count,
                        prof_eval_primary_from_sched_x_count,
                        prof_eval_primary_from_sched_y_count,
                        prof_eval_primary_from_sched_diag_count,
                        prof_eval_primary_from_legacy_count,
                        prof_eval_gate_open_count,
                        prof_eval_primary_usable_count,
                        prof_eval_select1_count,
                        prof_sel2_window_count,
                        prof_sel2_primary_secondary_count,
                        prof_sel2_frontier_count,
                        prof_pending1_fill_window_count,
                        prof_pending1_fill_primary_count,
                        prof_pending1_fill_secondary_count,
                        prof_pending1_fill_tertiary_count,
                        prof_eval_aggr_p0clear_primary_secondary_count,
                        prof_eval_aggr_p0set_primary_secondary_count,
                        prof_eval_aggr_fill_primary_secondary_count,
                        prof_eval_aggr_nofill_primary_secondary_count,
                        prof_eval_aggr_gateblocked_primary_secondary_count,
                        prof_eval_aggr_gateblocked_p0set_primary_secondary_count,
                        prof_eval_aggr_gateblocked_fill_primary_secondary_count,
                        prof_miss_overlap_primary_count,
                        prof_miss_overlap_secondary_count,
                        prof_miss_overlap_tertiary_count,
                        prof_miss_overlap_any_count,
                        prof_miss_overlap_none_count,
                        prof_lastmiss_overlap_primary_count,
                        prof_lastmiss_overlap_secondary_count,
                        prof_lastmiss_overlap_tertiary_count,
                        prof_lastmiss_overlap_any_count,
                        prof_lastmiss_overlap_none_count,
                        prof_lastmiss_sched_x_count,
                        prof_lastmiss_sched_y_count,
                        prof_lastmiss_sched_diag_count,
                        prof_lastmiss_legacy_p_count,
                        prof_lastmiss_legacy_s_count,
                        prof_lastmiss_legacy_t_count,
                        prof_lastmiss_rel_x_count,
                        prof_lastmiss_rel_y_count,
                        prof_lastmiss_rel_diag_count,
                        prof_lastmiss_rel_other_count,
                        prof_dom_nonempty_cycles,
                        prof_dom_fill_count,
                        prof_dom_blocked_by_pending_count);
`endif
                    $fatal(1, "Perf single-case simulation timed out waiting for irq");
                end
            end
        end
    endtask

    task automatic check_status_done_ok;
        logic [31:0] status_data;
        begin
            axil_read(12'h01C, status_data);
            if (!status_data[1]) begin
                $fatal(1, "Perf single-case status did not report done: 0x%08h", status_data);
            end
            if (status_data[2]) begin
                $fatal(1, "Perf single-case status reported error: 0x%08h", status_data);
            end
        end
    endtask

    task automatic read_cache_stats(
        output logic [31:0] reads,
        output logic [31:0] misses,
        output logic [31:0] prefetches,
        output logic [31:0] prefetch_hits
    );
        begin
            axil_read(REG_CACHE_READS_ADDR, reads);
            axil_read(REG_CACHE_MISSES_ADDR, misses);
            axil_read(REG_CACHE_PREFETCH_ADDR, prefetches);
            axil_read(REG_CACHE_PREFETCH_HIT_ADDR, prefetch_hits);
        end
    endtask

    task automatic read_cache_ext_word(input int word_idx, output logic [31:0] data);
        begin
            axil_read(REG_CACHE_STATS_EXT_BASE_ADDR + AXIL_ADDR_W'(word_idx * 4), data);
        end
    endtask

    task automatic wait_for_cache_stats_snapshot;
        int tries;
        logic [31:0] version;
        logic [31:0] snapshot_id;
        begin
            version = '0;
            snapshot_id = '0;
            for (tries = 0; tries < 200; tries = tries + 1) begin
                read_cache_ext_word(CACHE_STAT_VERSION_WORD, version);
                read_cache_ext_word(CACHE_STAT_SNAPSHOT_ID_WORD, snapshot_id);
                if ((version == 32'h0001_0000) && (snapshot_id != 0)) begin
                    return;
                end
                repeat (2) @(posedge axi_clk);
            end
            $fatal(1, "Timed out waiting for cache stats snapshot, version=0x%08h snapshot=%0d",
                   version, snapshot_id);
        end
    endtask

    task automatic program_case(
        input int src_w,
        input int src_h,
        input int dst_w,
        input int dst_h,
        input int signed sin_q16,
        input int signed cos_q16,
        input bit prefetch_en,
        input int src_stride_cfg,
        input int dst_stride_cfg
    );
        begin
            runtime_lead_pixels_cfg = `IMAGE_GEO_RUNTIME_LEAD_PIXELS;
            runtime_merge_max_x_eff_cfg = `IMAGE_GEO_RUNTIME_MERGE_MAX_X;
            runtime_merge_min_x_cfg = `IMAGE_GEO_RUNTIME_MERGE_MIN_X;
            runtime_fifo_depth_eff_cfg = `IMAGE_GEO_RUNTIME_FIFO_DEPTH;
            runtime_fifo_age_limit_cfg = `IMAGE_GEO_RUNTIME_FIFO_AGE_LIMIT;
            runtime_throttle_cycles_cfg = `IMAGE_GEO_RUNTIME_PREFETCH_THROTTLE_CYCLES;
            runtime_scheduler_policy_cfg = `IMAGE_GEO_RUNTIME_SCHEDULER_POLICY;
            axil_write(12'h004, SRC_BASE);
            axil_write(12'h008, DST_BASE);
            axil_write(12'h00C, src_stride_cfg);
            axil_write(12'h010, dst_stride_cfg);
            axil_write(12'h014, {src_h[15:0], src_w[15:0]});
            axil_write(12'h018, {dst_h[15:0], dst_w[15:0]});
            axil_write(12'h020, sin_q16);
            axil_write(12'h024, cos_q16);
            axil_write(12'h038, {31'd0, prefetch_en});
            axil_write(REG_SCHED_CTRL_ADDR, {22'd0, runtime_scheduler_policy_cfg[1:0], 7'd0, prefetch_en});
            axil_write(REG_SCHED_LEAD_ADDR, {16'd0, runtime_lead_pixels_cfg[15:0]});
            axil_write(REG_SCHED_MERGE_ADDR, {16'd0, runtime_merge_min_x_cfg[7:0], runtime_merge_max_x_eff_cfg[7:0]});
            axil_write(REG_SCHED_FIFO_ADDR, {runtime_fifo_age_limit_cfg[15:0], runtime_fifo_depth_eff_cfg[15:0]});
            axil_write(REG_SCHED_THROTTLE_ADDR, {16'd0, runtime_throttle_cycles_cfg[15:0]});
            axil_write(12'h000, 32'h0000_0003);
        end
    endtask

    task automatic run_case(
        input string case_name,
        input int src_w,
        input int src_h,
        input int dst_w,
        input int dst_h,
        input int signed sin_q16,
        input int signed cos_q16,
        input bit prefetch_en,
        input int src_stride_cfg,
        input int dst_stride_cfg
    );
        logic [31:0] reads;
        logic [31:0] misses;
        logic [31:0] prefetches;
        logic [31:0] prefetch_hits;
        logic [31:0] ext_version;
        logic [31:0] ext_snapshot_id;
        logic [31:0] ext_frame_cycles;
        logic [31:0] ext_total_cycles;
        logic [31:0] ext_sample_req;
        logic [31:0] ext_sample_accept;
        logic [31:0] ext_sample_stall;
        logic [31:0] ext_normal_prefetch_fills;
        logic [31:0] ext_prefetch_evicted_unused;
        logic [31:0] ext_fifo_max;
        logic [31:0] ext_read_busy_cycles;
        logic [31:0] ext_read_bytes_low;
        logic [31:0] ext_read_bytes_high;
        logic [31:0] ext_useful_source_sectors;
        logic [31:0] ext_replacement_fail;
        logic [31:0] ext_miss_latency_min;
        logic [31:0] ext_miss_latency_max;
        logic [31:0] ext_miss_latency_sum_low;
        logic [31:0] ext_miss_latency_sum_high;
        logic [31:0] ext_miss_latency_count;
        logic [31:0] ext_sched_policy;
        logic [31:0] ext_sched_lead;
        logic [31:0] ext_sched_merge;
        logic [31:0] ext_sched_fifo;
        logic [31:0] ext_sched_throttle;
        logic [31:0] ext_fifo_head_run;
        logic [31:0] ext_fifo_same_row_adj;
        logic [31:0] ext_fifo_reverse_x_adj;
        logic [31:0] ext_merge_opp_missed;
        logic [31:0] ext_merge_hist [0:16];
        longint unsigned ext_read_bytes;
        longint unsigned ext_miss_latency_sum;
        int start_cycles;
        int cycles;
        int h;
        begin
            reset_dut();
            start_cycles = cycle_count;
            program_case(src_w, src_h, dst_w, dst_h, sin_q16, cos_q16, prefetch_en, src_stride_cfg, dst_stride_cfg);
            wait_for_irq();
            check_status_done_ok();
            cycles = cycle_count - start_cycles;
            wait_for_cache_stats_snapshot();
            read_cache_stats(reads, misses, prefetches, prefetch_hits);
            read_cache_ext_word(CACHE_STAT_VERSION_WORD, ext_version);
            read_cache_ext_word(CACHE_STAT_SNAPSHOT_ID_WORD, ext_snapshot_id);
            read_cache_ext_word(CACHE_STAT_FRAME_CYCLES_WORD, ext_frame_cycles);
            read_cache_ext_word(CACHE_STAT_TOTAL_CYCLES_WORD, ext_total_cycles);
            read_cache_ext_word(CACHE_STAT_SAMPLE_REQ_WORD, ext_sample_req);
            read_cache_ext_word(CACHE_STAT_SAMPLE_ACCEPT_WORD, ext_sample_accept);
            read_cache_ext_word(CACHE_STAT_SAMPLE_STALL_WORD, ext_sample_stall);
            read_cache_ext_word(CACHE_STAT_NORMAL_PREFETCH_FILLS_WORD, ext_normal_prefetch_fills);
            read_cache_ext_word(CACHE_STAT_PREFETCH_EVICT_UNUSED_WORD, ext_prefetch_evicted_unused);
            read_cache_ext_word(CACHE_STAT_FIFO_MAX_WORD, ext_fifo_max);
            read_cache_ext_word(CACHE_STAT_READ_BUSY_CYCLES_WORD, ext_read_busy_cycles);
            read_cache_ext_word(CACHE_STAT_READ_BYTES_LOW_WORD, ext_read_bytes_low);
            read_cache_ext_word(CACHE_STAT_READ_BYTES_HIGH_WORD, ext_read_bytes_high);
            read_cache_ext_word(CACHE_STAT_USEFUL_SOURCE_SECTORS_WORD, ext_useful_source_sectors);
            read_cache_ext_word(CACHE_STAT_REPLACEMENT_FAIL_WORD, ext_replacement_fail);
            read_cache_ext_word(CACHE_STAT_MISS_LATENCY_MIN_WORD, ext_miss_latency_min);
            read_cache_ext_word(CACHE_STAT_MISS_LATENCY_MAX_WORD, ext_miss_latency_max);
            read_cache_ext_word(CACHE_STAT_MISS_LATENCY_SUM_LOW_WORD, ext_miss_latency_sum_low);
            read_cache_ext_word(CACHE_STAT_MISS_LATENCY_SUM_HIGH_WORD, ext_miss_latency_sum_high);
            read_cache_ext_word(CACHE_STAT_MISS_LATENCY_COUNT_WORD, ext_miss_latency_count);
            read_cache_ext_word(CACHE_STAT_SCHED_POLICY_WORD, ext_sched_policy);
            read_cache_ext_word(CACHE_STAT_SCHED_LEAD_WORD, ext_sched_lead);
            read_cache_ext_word(CACHE_STAT_SCHED_MERGE_WORD, ext_sched_merge);
            read_cache_ext_word(CACHE_STAT_SCHED_FIFO_WORD, ext_sched_fifo);
            read_cache_ext_word(CACHE_STAT_SCHED_THROTTLE_WORD, ext_sched_throttle);
            read_cache_ext_word(CACHE_STAT_FIFO_HEAD_RUN_WORD, ext_fifo_head_run);
            read_cache_ext_word(CACHE_STAT_FIFO_SAME_ROW_ADJ_WORD, ext_fifo_same_row_adj);
            read_cache_ext_word(CACHE_STAT_FIFO_REVERSE_X_ADJ_WORD, ext_fifo_reverse_x_adj);
            read_cache_ext_word(CACHE_STAT_MERGE_OPPORTUNITY_MISSED_WORD, ext_merge_opp_missed);
            for (h = 0; h < 17; h = h + 1) begin
                read_cache_ext_word(CACHE_STAT_MERGE_HIST_BASE_WORD + h, ext_merge_hist[h]);
            end
            ext_read_bytes = {ext_read_bytes_high, ext_read_bytes_low};
            ext_miss_latency_sum = {ext_miss_latency_sum_high, ext_miss_latency_sum_low};
            $display("PERF_SINGLE case=%s prefetch=%0d src=%0dx%0d dst=%0dx%0d sin=0x%08h cos=0x%08h cycles=%0d reads=%0d misses=%0d prefetches=%0d hits=%0d analytic=%0d/%0d/%0d/%0d evict_unused=%0d",
                case_name, prefetch_en, src_w, src_h, dst_w, dst_h, sin_q16, cos_q16,
                cycles, reads, misses, prefetches, prefetch_hits,
                dut.u_src_tile_cache.stat_analytic_candidates_reg,
                dut.u_src_tile_cache.stat_analytic_duplicates_reg,
                dut.u_src_tile_cache.stat_analytic_blocked_reg,
                dut.u_src_tile_cache.stat_analytic_fills_reg,
                dut.u_src_tile_cache.stat_prefetch_evicted_unused_reg);
            $display("PERF_SINGLE_STATS_EXT version=0x%08h snapshot=%0d frame_cycles=%0d cache_cycles=%0d sample_req=%0d sample_accept=%0d sample_stall=%0d normal_prefetch=%0d evict_unused=%0d fifo_max=%0d read_busy=%0d read_bytes=%0d useful_sectors=%0d replacement_fail=%0d miss_lat_min=%0d miss_lat_max=%0d miss_lat_sum=%0d miss_lat_count=%0d sched_policy=%0d sched_lead=%0d sched_merge=0x%08h sched_fifo=0x%08h sched_throttle=%0d fifo_head_run=%0d fifo_same_row_adj=%0d fifo_reverse_x_adj=%0d merge_opp_missed=%0d merge_hist=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d",
                ext_version, ext_snapshot_id, ext_frame_cycles, ext_total_cycles,
                ext_sample_req, ext_sample_accept, ext_sample_stall,
                ext_normal_prefetch_fills, ext_prefetch_evicted_unused, ext_fifo_max,
                ext_read_busy_cycles, ext_read_bytes, ext_useful_source_sectors,
                ext_replacement_fail, ext_miss_latency_min, ext_miss_latency_max,
                ext_miss_latency_sum, ext_miss_latency_count,
                ext_sched_policy, ext_sched_lead, ext_sched_merge, ext_sched_fifo,
                ext_sched_throttle, ext_fifo_head_run, ext_fifo_same_row_adj,
                ext_fifo_reverse_x_adj, ext_merge_opp_missed,
                ext_merge_hist[0], ext_merge_hist[1], ext_merge_hist[2], ext_merge_hist[3],
                ext_merge_hist[4], ext_merge_hist[5], ext_merge_hist[6], ext_merge_hist[7],
                ext_merge_hist[8], ext_merge_hist[9], ext_merge_hist[10], ext_merge_hist[11],
                ext_merge_hist[12], ext_merge_hist[13], ext_merge_hist[14], ext_merge_hist[15],
                ext_merge_hist[16]);
`ifndef IMAGE_GEO_PERF_SINGLE_LIGHTWEIGHT
            $display("PERF_SINGLE_PROFILE_DETAIL corewait=%0d/%0d/%0d/%0d/%0d/%0d/%0d waitpipe=%0d/%0d/%0d fillcyc=%0d/%0d/%0d/%0d domq=%0d/%0d/%0d req=%0d wait=%0d out=%0d accepts=%0d rsp=%0d pix=%0d",
                prof_req_stall_miss_count,
                prof_req_stall_decode_count,
                prof_req_stall_issue_count,
                prof_req_stall_prefetch_fill_count,
                prof_req_stall_demand_fill_count,
                prof_req_stall_read_busy_count,
                prof_req_stall_allhit_busy_count,
                prof_wait_no_rsp_count,
                prof_wait_decode_count,
                prof_wait_issue_count,
                prof_fill_prefetch_cycles,
                prof_fill_demand_cycles,
                prof_fill_read_busy_cycles,
                prof_fill_row_inflight_cycles,
                prof_dom_nonempty_cycles,
                prof_dom_fill_count,
                prof_dom_blocked_by_pending_count,
                prof_req_cycles,
                prof_wait_cycles,
                prof_out_cycles,
                prof_req_accepts,
                prof_rsp_count,
                prof_pix_fire_count);
`endif
        end
    endtask

    initial begin
        run_case(CASE_NAME, SRC_W_CFG, SRC_H_CFG, DST_W_CFG, DST_H_CFG,
            SIN_Q16_CFG, COS_Q16_CFG, PREFETCH_EN, SRC_STRIDE_CFG, DST_STRIDE_CFG);
        $display("tb_image_geo_top_perf_single_case completed");
        $finish;
    end

endmodule

module tb_image_geo_top_perf_single_small_rotate45_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("small_rotate45"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(64), .SRC_H_CFG(64), .DST_W_CFG(24), .DST_H_CFG(24),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(64), .DST_STRIDE_CFG(64)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_small_rotate45_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("small_rotate45"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(64), .SRC_H_CFG(64), .DST_W_CFG(24), .DST_H_CFG(24),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(64), .DST_STRIDE_CFG(64)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_downscale_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("large_downscale"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_downscale_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("large_downscale"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_1000_600_downscale_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("1000_600_downscale"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1000), .SRC_H_CFG(1000), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(1000), .DST_STRIDE_CFG(600),
        .TIMEOUT_CYCLES_CFG(40000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_1000_600_rotate15_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("1000_600_rotate15"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1000), .SRC_H_CFG(1000), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(1000), .DST_STRIDE_CFG(600),
        .TIMEOUT_CYCLES_CFG(40000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("large_rotate45"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_off_quickdiag;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("large_rotate45"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600),
        .TIMEOUT_CYCLES_CFG(10000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("large_rotate45"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_on_quickdiag;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("large_rotate45"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600),
        .TIMEOUT_CYCLES_CFG(10000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_on_trace2uniq;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("large_rotate45"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600),
        .TIMEOUT_CYCLES_CFG(10000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate15_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate15"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate15_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate15"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate30_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate30"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_8000), .COS_Q16_CFG(32'sh0000_DDB4),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate30_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate30"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_8000), .COS_Q16_CFG(32'sh0000_DDB4),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate45_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate45"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate45_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate45"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate60_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate60"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_DDB4), .COS_Q16_CFG(32'sh0000_8000),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate60_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate60"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_DDB4), .COS_Q16_CFG(32'sh0000_8000),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate75_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate75"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate75_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("mid_rotate75"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate15_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("proxy_rotate15"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate15_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("proxy_rotate15"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate45_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("proxy_rotate45"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate45_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("proxy_rotate45"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate75_off;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("proxy_rotate75"),
        .PREFETCH_EN(1'b0),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate75_on;
    tb_image_geo_top_perf_single_case_base #(
        .CASE_NAME("proxy_rotate75"),
        .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256),
        .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule
