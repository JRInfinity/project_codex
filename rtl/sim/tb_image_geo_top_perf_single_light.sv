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

module tb_image_geo_top_perf_single_light_base #(
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
);

    localparam int AXIL_ADDR_W = 12;
    localparam int AXIL_DATA_W = 32;
    localparam int AXI_ADDR_W  = 32;
    localparam int AXI_DATA_W  = 32;
    localparam int AXI_ID_W    = 4;
    localparam int PIXEL_W     = 8;
    localparam int BYTE_W      = AXI_DATA_W / 8;
    localparam int SRC_BASE    = 32'h0000_0100;
    localparam int DST_BASE    = 32'h0800_0000;
    localparam int TIMEOUT_CYCLES = TIMEOUT_CYCLES_CFG;
    localparam int RD_QUEUE_DEPTH = 128;

    localparam logic [AXIL_ADDR_W-1:0] REG_CTRL_ADDR = 12'h000;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_BASE_ADDR = 12'h004;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_BASE_ADDR = 12'h008;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_STRIDE_ADDR = 12'h00C;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_STRIDE_ADDR = 12'h010;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_SIZE_ADDR = 12'h014;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_SIZE_ADDR = 12'h018;
    localparam logic [AXIL_ADDR_W-1:0] REG_STATUS_ADDR = 12'h01C;
    localparam logic [AXIL_ADDR_W-1:0] REG_SIN_ADDR = 12'h020;
    localparam logic [AXIL_ADDR_W-1:0] REG_COS_ADDR = 12'h024;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_READS_ADDR = 12'h028;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_MISSES_ADDR = 12'h02C;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_PREFETCH_ADDR = 12'h030;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_PREFETCH_HIT_ADDR = 12'h034;
    localparam logic [AXIL_ADDR_W-1:0] REG_PREFETCH_CTRL_ADDR = 12'h038;
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

    logic [AXI_ADDR_W-1:0] rd_addr_queue [0:RD_QUEUE_DEPTH-1];
    int unsigned           rd_beats_queue [0:RD_QUEUE_DEPTH-1];
    int unsigned           rd_head_reg;
    int unsigned           rd_tail_reg;
    int unsigned           rd_count_reg;
    logic [AXI_ADDR_W-1:0] rd_active_addr_reg;
    int unsigned           rd_active_beats_reg;
    int unsigned           rd_active_idx_reg;
    logic                  rd_active_reg;

    int unsigned           wr_active_beats_reg;
    int unsigned           wr_active_idx_reg;
    logic                  wr_active_reg;

    int cycle_count;
    int runtime_lead_pixels_cfg;
    int runtime_merge_max_x_eff_cfg;
    int runtime_merge_min_x_cfg;
    int runtime_fifo_depth_eff_cfg;
    int runtime_fifo_age_limit_cfg;
    int runtime_throttle_cycles_cfg;
    int runtime_scheduler_policy_cfg;

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

    function automatic logic [7:0] src_byte_at_addr(input logic [AXI_ADDR_W-1:0] addr);
        int unsigned offset;
        int unsigned x;
        int unsigned y;
        begin
            if (addr < SRC_BASE) begin
                src_byte_at_addr = 8'h00;
            end else begin
                offset = addr - SRC_BASE;
                y = offset / SRC_STRIDE_CFG;
                x = offset % SRC_STRIDE_CFG;
                if ((x >= SRC_W_CFG) || (y >= SRC_H_CFG)) begin
                    src_byte_at_addr = 8'h00;
                end else begin
                    src_byte_at_addr = ((y * 29) + (x * 17) + ((x ^ y) * 3) + 7) & 8'hFF;
                end
            end
        end
    endfunction

    function automatic logic [AXI_DATA_W-1:0] src_word_at_addr(input logic [AXI_ADDR_W-1:0] addr);
        int b;
        begin
            src_word_at_addr = '0;
            for (b = 0; b < BYTE_W; b = b + 1) begin
                src_word_at_addr[b*8 +: 8] = src_byte_at_addr(addr + b);
            end
        end
    endfunction

    task automatic reset_dut;
        begin
            axi_rstn = 1'b0;
            core_rstn = 1'b0;
            s_axi_ctrl_awaddr = '0;
            s_axi_ctrl_awprot = '0;
            s_axi_ctrl_awvalid = 1'b0;
            s_axi_ctrl_wdata = '0;
            s_axi_ctrl_wstrb = '0;
            s_axi_ctrl_wvalid = 1'b0;
            s_axi_ctrl_bready = 1'b0;
            s_axi_ctrl_araddr = '0;
            s_axi_ctrl_arprot = '0;
            s_axi_ctrl_arvalid = 1'b0;
            s_axi_ctrl_rready = 1'b0;
            m_axi_rd_arready = 1'b0;
            m_axi_rd_rid = '0;
            m_axi_rd_rdata = '0;
            m_axi_rd_rresp = 2'b00;
            m_axi_rd_rlast = 1'b0;
            m_axi_rd_rvalid = 1'b0;
            m_axi_wr_awready = 1'b0;
            m_axi_wr_wready = 1'b0;
            m_axi_wr_bid = '0;
            m_axi_wr_bresp = 2'b00;
            m_axi_wr_bvalid = 1'b0;
            rd_head_reg = 0;
            rd_tail_reg = 0;
            rd_count_reg = 0;
            rd_active_reg = 1'b0;
            rd_active_addr_reg = '0;
            rd_active_beats_reg = 0;
            rd_active_idx_reg = 0;
            wr_active_reg = 1'b0;
            wr_active_beats_reg = 0;
            wr_active_idx_reg = 0;
            cycle_count = 0;
            repeat (6) @(posedge axi_clk);
            axi_rstn = 1'b1;
            core_rstn = 1'b1;
            repeat (4) @(posedge axi_clk);
        end
    endtask

    task automatic axil_write(input logic [AXIL_ADDR_W-1:0] addr, input logic [31:0] data);
        begin
            @(posedge axi_clk);
            s_axi_ctrl_awaddr <= addr;
            s_axi_ctrl_awvalid <= 1'b1;
            s_axi_ctrl_wdata <= data;
            s_axi_ctrl_wstrb <= 4'hF;
            s_axi_ctrl_wvalid <= 1'b1;
            s_axi_ctrl_bready <= 1'b1;
            while (!(s_axi_ctrl_awready && s_axi_ctrl_wready)) begin
                @(posedge axi_clk);
            end
            @(posedge axi_clk);
            s_axi_ctrl_awvalid <= 1'b0;
            s_axi_ctrl_wvalid <= 1'b0;
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
            s_axi_ctrl_araddr <= addr;
            s_axi_ctrl_arvalid <= 1'b1;
            s_axi_ctrl_rready <= 1'b1;
            while (!s_axi_ctrl_arready) begin
                @(posedge axi_clk);
            end
            @(posedge axi_clk);
            s_axi_ctrl_arvalid <= 1'b0;
            while (!s_axi_ctrl_rvalid) begin
                @(posedge axi_clk);
            end
            data = s_axi_ctrl_rdata;
            if (s_axi_ctrl_rresp != 2'b00) begin
                $fatal(1, "AXI-Lite read response error at addr %h", addr);
            end
            @(posedge axi_clk);
            s_axi_ctrl_rready <= 1'b0;
        end
    endtask

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn) begin
            m_axi_rd_arready <= 1'b0;
            m_axi_rd_rvalid <= 1'b0;
            m_axi_rd_rlast <= 1'b0;
            m_axi_rd_rresp <= 2'b00;
            m_axi_rd_rid <= '0;
        end else begin
            m_axi_rd_arready <= (rd_count_reg < (RD_QUEUE_DEPTH - 2));
            if (m_axi_rd_arvalid && m_axi_rd_arready) begin
                rd_addr_queue[rd_tail_reg] <= m_axi_rd_araddr;
                rd_beats_queue[rd_tail_reg] <= m_axi_rd_arlen + 1;
                rd_tail_reg <= (rd_tail_reg == (RD_QUEUE_DEPTH - 1)) ? 0 : (rd_tail_reg + 1);
                rd_count_reg <= rd_count_reg + 1;
            end

            if (!rd_active_reg && (rd_count_reg != 0) && !m_axi_rd_rvalid) begin
                rd_active_reg <= 1'b1;
                rd_active_addr_reg <= rd_addr_queue[rd_head_reg];
                rd_active_beats_reg <= rd_beats_queue[rd_head_reg];
                rd_active_idx_reg <= 0;
                rd_head_reg <= (rd_head_reg == (RD_QUEUE_DEPTH - 1)) ? 0 : (rd_head_reg + 1);
                rd_count_reg <= rd_count_reg - 1;
            end else if (rd_active_reg && !m_axi_rd_rvalid) begin
                m_axi_rd_rvalid <= 1'b1;
                m_axi_rd_rid <= '0;
                m_axi_rd_rresp <= 2'b00;
                m_axi_rd_rdata <= src_word_at_addr(rd_active_addr_reg + (rd_active_idx_reg * BYTE_W));
                m_axi_rd_rlast <= (rd_active_idx_reg == (rd_active_beats_reg - 1));
            end else if (m_axi_rd_rvalid && m_axi_rd_rready) begin
                if (m_axi_rd_rlast) begin
                    m_axi_rd_rvalid <= 1'b0;
                    m_axi_rd_rlast <= 1'b0;
                    rd_active_reg <= 1'b0;
                end else begin
                    rd_active_idx_reg <= rd_active_idx_reg + 1;
                    m_axi_rd_rdata <= src_word_at_addr(rd_active_addr_reg + ((rd_active_idx_reg + 1) * BYTE_W));
                    m_axi_rd_rlast <= ((rd_active_idx_reg + 1) == (rd_active_beats_reg - 1));
                end
            end
        end
    end

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn) begin
            m_axi_wr_awready <= 1'b0;
            m_axi_wr_wready <= 1'b0;
            m_axi_wr_bvalid <= 1'b0;
            m_axi_wr_bresp <= 2'b00;
            m_axi_wr_bid <= '0;
            wr_active_reg <= 1'b0;
            wr_active_beats_reg <= 0;
            wr_active_idx_reg <= 0;
        end else begin
            m_axi_wr_awready <= 1'b1;
            m_axi_wr_wready <= 1'b1;
            if (m_axi_wr_awvalid && m_axi_wr_awready) begin
                wr_active_reg <= 1'b1;
                wr_active_beats_reg <= m_axi_wr_awlen + 1;
                wr_active_idx_reg <= 0;
            end
            if (m_axi_wr_wvalid && m_axi_wr_wready) begin
                if (!wr_active_reg) begin
                    $fatal(1, "Write data arrived before write address");
                end
                if (m_axi_wr_wlast != (wr_active_idx_reg == (wr_active_beats_reg - 1))) begin
                    $fatal(1, "WLAST mismatch");
                end
                if (m_axi_wr_wlast) begin
                    wr_active_reg <= 1'b0;
                    m_axi_wr_bvalid <= 1'b1;
                    m_axi_wr_bresp <= 2'b00;
                end else begin
                    wr_active_idx_reg <= wr_active_idx_reg + 1;
                end
            end
            if (m_axi_wr_bvalid && m_axi_wr_bready) begin
                m_axi_wr_bvalid <= 1'b0;
            end
        end
    end

    task automatic program_case;
        begin
            runtime_lead_pixels_cfg = `IMAGE_GEO_RUNTIME_LEAD_PIXELS;
            runtime_merge_max_x_eff_cfg = `IMAGE_GEO_RUNTIME_MERGE_MAX_X;
            runtime_merge_min_x_cfg = `IMAGE_GEO_RUNTIME_MERGE_MIN_X;
            runtime_fifo_depth_eff_cfg = `IMAGE_GEO_RUNTIME_FIFO_DEPTH;
            runtime_fifo_age_limit_cfg = `IMAGE_GEO_RUNTIME_FIFO_AGE_LIMIT;
            runtime_throttle_cycles_cfg = `IMAGE_GEO_RUNTIME_PREFETCH_THROTTLE_CYCLES;
            runtime_scheduler_policy_cfg = `IMAGE_GEO_RUNTIME_SCHEDULER_POLICY;
            axil_write(REG_SRC_BASE_ADDR, SRC_BASE);
            axil_write(REG_DST_BASE_ADDR, DST_BASE);
            axil_write(REG_SRC_STRIDE_ADDR, SRC_STRIDE_CFG);
            axil_write(REG_DST_STRIDE_ADDR, DST_STRIDE_CFG);
            axil_write(REG_SRC_SIZE_ADDR, {SRC_H_CFG[15:0], SRC_W_CFG[15:0]});
            axil_write(REG_DST_SIZE_ADDR, {DST_H_CFG[15:0], DST_W_CFG[15:0]});
            axil_write(REG_SIN_ADDR, SIN_Q16_CFG);
            axil_write(REG_COS_ADDR, COS_Q16_CFG);
            axil_write(REG_PREFETCH_CTRL_ADDR, {31'd0, PREFETCH_EN});
            axil_write(REG_SCHED_CTRL_ADDR, {22'd0, runtime_scheduler_policy_cfg[1:0], 7'd0, PREFETCH_EN});
            axil_write(REG_SCHED_LEAD_ADDR, {16'd0, runtime_lead_pixels_cfg[15:0]});
            axil_write(REG_SCHED_MERGE_ADDR, {16'd0, runtime_merge_min_x_cfg[7:0], runtime_merge_max_x_eff_cfg[7:0]});
            axil_write(REG_SCHED_FIFO_ADDR, {runtime_fifo_age_limit_cfg[15:0], runtime_fifo_depth_eff_cfg[15:0]});
            axil_write(REG_SCHED_THROTTLE_ADDR, {16'd0, runtime_throttle_cycles_cfg[15:0]});
            axil_write(REG_CTRL_ADDR, 32'h0000_0003);
        end
    endtask

    task automatic wait_for_irq;
        logic [31:0] status_data;
        begin
            while (!irq) begin
                @(posedge axi_clk);
                if (cycle_count > TIMEOUT_CYCLES) begin
                    axil_read(REG_STATUS_ADDR, status_data);
                    $display("PERF_SINGLE_TIMEOUT case=%s prefetch=%0d cycles=%0d status=0x%08h",
                        CASE_NAME, PREFETCH_EN, cycle_count, status_data);
                    $fatal(1, "Perf light single-case timed out waiting for irq");
                end
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

    task automatic run_case;
        logic [31:0] status_data;
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
        logic [31:0] ext_analytic_candidates;
        logic [31:0] ext_analytic_duplicates;
        logic [31:0] ext_analytic_blocked;
        logic [31:0] ext_analytic_fills;
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
            program_case();
            wait_for_irq();
            cycles = cycle_count - start_cycles;
            axil_read(REG_STATUS_ADDR, status_data);
            if (!status_data[1] || status_data[2]) begin
                $fatal(1, "Perf light status not done-ok: 0x%08h", status_data);
            end
            wait_for_cache_stats_snapshot();
            read_cache_stats(reads, misses, prefetches, prefetch_hits);
            read_cache_ext_word(CACHE_STAT_VERSION_WORD, ext_version);
            read_cache_ext_word(CACHE_STAT_SNAPSHOT_ID_WORD, ext_snapshot_id);
            read_cache_ext_word(CACHE_STAT_FRAME_CYCLES_WORD, ext_frame_cycles);
            read_cache_ext_word(CACHE_STAT_TOTAL_CYCLES_WORD, ext_total_cycles);
            read_cache_ext_word(CACHE_STAT_SAMPLE_REQ_WORD, ext_sample_req);
            read_cache_ext_word(CACHE_STAT_SAMPLE_ACCEPT_WORD, ext_sample_accept);
            read_cache_ext_word(CACHE_STAT_SAMPLE_STALL_WORD, ext_sample_stall);
            read_cache_ext_word(CACHE_STAT_ANALYTIC_CANDIDATES_WORD, ext_analytic_candidates);
            read_cache_ext_word(CACHE_STAT_ANALYTIC_DUPLICATES_WORD, ext_analytic_duplicates);
            read_cache_ext_word(CACHE_STAT_ANALYTIC_BLOCKED_WORD, ext_analytic_blocked);
            read_cache_ext_word(CACHE_STAT_ANALYTIC_FILLS_WORD, ext_analytic_fills);
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
                CASE_NAME, PREFETCH_EN, SRC_W_CFG, SRC_H_CFG, DST_W_CFG, DST_H_CFG,
                SIN_Q16_CFG, COS_Q16_CFG, cycles, reads, misses, prefetches, prefetch_hits,
                ext_analytic_candidates, ext_analytic_duplicates, ext_analytic_blocked,
                ext_analytic_fills, ext_prefetch_evicted_unused);
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
        end
    endtask

    initial begin
        run_case();
        $display("tb_image_geo_top_perf_single_light completed");
        $finish;
    end
endmodule

module tb_image_geo_top_perf_single_small_rotate45_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("small_rotate45"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(64), .SRC_H_CFG(64), .DST_W_CFG(24), .DST_H_CFG(24),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(64), .DST_STRIDE_CFG(64)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_small_rotate45_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("small_rotate45"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(64), .SRC_H_CFG(64), .DST_W_CFG(24), .DST_H_CFG(24),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(64), .DST_STRIDE_CFG(64)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate0_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate0"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate0_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate0"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate15_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate15"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate15_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate15"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate45_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate45"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate45_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate45"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate75_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate75"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate75_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate75"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate90_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate90"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0001_0000), .COS_Q16_CFG(32'sh0000_0000),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal128_rotate90_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal128_rotate90"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(128), .SRC_H_CFG(128), .DST_W_CFG(48), .DST_H_CFG(48),
        .SIN_Q16_CFG(32'sh0001_0000), .COS_Q16_CFG(32'sh0000_0000),
        .SRC_STRIDE_CFG(128), .DST_STRIDE_CFG(64), .TIMEOUT_CYCLES_CFG(4000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal256_rotate0_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal256_rotate0"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(256), .SRC_H_CFG(256), .DST_W_CFG(96), .DST_H_CFG(96),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(256), .DST_STRIDE_CFG(128), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal256_rotate15_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal256_rotate15"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(256), .SRC_H_CFG(256), .DST_W_CFG(96), .DST_H_CFG(96),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(256), .DST_STRIDE_CFG(128), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal256_rotate45_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal256_rotate45"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(256), .SRC_H_CFG(256), .DST_W_CFG(96), .DST_H_CFG(96),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(256), .DST_STRIDE_CFG(128), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal256_rotate75_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal256_rotate75"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(256), .SRC_H_CFG(256), .DST_W_CFG(96), .DST_H_CFG(96),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(256), .DST_STRIDE_CFG(128), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_cal256_rotate90_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("cal256_rotate90"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(256), .SRC_H_CFG(256), .DST_W_CFG(96), .DST_H_CFG(96),
        .SIN_Q16_CFG(32'sh0001_0000), .COS_Q16_CFG(32'sh0000_0000),
        .SRC_STRIDE_CFG(256), .DST_STRIDE_CFG(128), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy512_rotate0_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy512_rotate0"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(512), .SRC_H_CFG(512), .DST_W_CFG(192), .DST_H_CFG(192),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(512), .DST_STRIDE_CFG(192), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy512_rotate15_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy512_rotate15"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(512), .SRC_H_CFG(512), .DST_W_CFG(192), .DST_H_CFG(192),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(512), .DST_STRIDE_CFG(192), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy512_rotate45_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy512_rotate45"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(512), .SRC_H_CFG(512), .DST_W_CFG(192), .DST_H_CFG(192),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(512), .DST_STRIDE_CFG(192), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy512_rotate75_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy512_rotate75"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(512), .SRC_H_CFG(512), .DST_W_CFG(192), .DST_H_CFG(192),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(512), .DST_STRIDE_CFG(192), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy512_rotate90_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy512_rotate90"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(512), .SRC_H_CFG(512), .DST_W_CFG(192), .DST_H_CFG(192),
        .SIN_Q16_CFG(32'sh0001_0000), .COS_Q16_CFG(32'sh0000_0000),
        .SRC_STRIDE_CFG(512), .DST_STRIDE_CFG(192), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate0_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy_rotate0"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate90_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy_rotate90"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0001_0000), .COS_Q16_CFG(32'sh0000_0000),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_downscale_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("large_downscale"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_downscale_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("large_downscale"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_1000_600_downscale_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("1000_600_downscale"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1000), .SRC_H_CFG(1000), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_0000), .COS_Q16_CFG(32'sh0001_0000),
        .SRC_STRIDE_CFG(1000), .DST_STRIDE_CFG(600), .TIMEOUT_CYCLES_CFG(40000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_1000_600_rotate15_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("1000_600_rotate15"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1000), .SRC_H_CFG(1000), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(1000), .DST_STRIDE_CFG(600), .TIMEOUT_CYCLES_CFG(40000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("large_rotate45"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_off_quickdiag;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("large_rotate45"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600), .TIMEOUT_CYCLES_CFG(10000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("large_rotate45"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_on_quickdiag;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("large_rotate45"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(7200), .SRC_H_CFG(7200), .DST_W_CFG(600), .DST_H_CFG(600),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(7200), .DST_STRIDE_CFG(600), .TIMEOUT_CYCLES_CFG(10000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_large_rotate45_on_trace2uniq;
    tb_image_geo_top_perf_single_large_rotate45_on_quickdiag tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate15_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate15"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate15_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate15"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate30_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate30"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_8000), .COS_Q16_CFG(32'sh0000_DDB4),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate30_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate30"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_8000), .COS_Q16_CFG(32'sh0000_DDB4),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate45_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate45"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate45_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate45"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate60_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate60"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_DDB4), .COS_Q16_CFG(32'sh0000_8000),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate60_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate60"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_DDB4), .COS_Q16_CFG(32'sh0000_8000),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate75_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate75"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_mid_rotate75_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("mid_rotate75"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(2048), .SRC_H_CFG(2048), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(2048), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(20000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate15_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy_rotate15"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate15_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy_rotate15"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_4242), .COS_Q16_CFG(32'sh0000_F747),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate45_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy_rotate45"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate45_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy_rotate45"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_B505), .COS_Q16_CFG(32'sh0000_B505),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate75_off;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy_rotate75"), .PREFETCH_EN(1'b0),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule

module tb_image_geo_top_perf_single_proxy_rotate75_on;
    tb_image_geo_top_perf_single_light_base #(
        .CASE_NAME("proxy_rotate75"), .PREFETCH_EN(1'b1),
        .SRC_W_CFG(1024), .SRC_H_CFG(1024), .DST_W_CFG(256), .DST_H_CFG(256),
        .SIN_Q16_CFG(32'sh0000_F747), .COS_Q16_CFG(32'sh0000_4242),
        .SRC_STRIDE_CFG(1024), .DST_STRIDE_CFG(256), .TIMEOUT_CYCLES_CFG(12000000)
    ) tb ();
endmodule
