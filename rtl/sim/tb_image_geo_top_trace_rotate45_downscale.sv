`timescale 1ns/1ps
// Keep tb_image_geo_top_trace_rotate45_downscale.md in sync
module tb_image_geo_top_trace_rotate45_downscale;

    localparam int AXIL_ADDR_W = 12;
    localparam int AXIL_DATA_W = 32;
    localparam int AXI_ADDR_W  = 32;
    localparam int AXI_DATA_W  = 32;
    localparam int AXI_ID_W    = 4;
    localparam int PIXEL_W     = 8;
    localparam int MEM_BYTES   = 65536;
    localparam int BYTE_W      = AXI_DATA_W / 8;
    localparam int SRC_BASE    = 32'h0000_0100;
    localparam int DST_BASE    = 32'h0000_4000;
    localparam int TRACE_START = 120;
    localparam int TRACE_LIMIT = 96;

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

    byte src_mem [0:MEM_BYTES-1];
    byte dst_mem [0:MEM_BYTES-1];

    logic [AXI_ADDR_W-1:0] rd_active_addr_reg;
    int unsigned           rd_active_beats_reg;
    int unsigned           rd_active_idx_reg;
    bit                    rd_active_reg;

    logic [AXI_ADDR_W-1:0] wr_active_addr_reg;
    int unsigned           wr_active_beats_reg;
    int unsigned           wr_active_idx_reg;
    bit                    wr_active_reg;

    int cycle_count;
    int trace_accept_count;
    int trace_fill_count;
    bit trace_done_reg;

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
        .MAX_SRC_W(64),
        .MAX_SRC_H(64),
        .MAX_DST_W(64),
        .MAX_DST_H(64),
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

    task automatic init_memory;
        int x;
        int y;
        begin
            for (x = 0; x < MEM_BYTES; x = x + 1) begin
                src_mem[x] = 8'h00;
                dst_mem[x] = 8'hA5;
            end
            for (y = 0; y < 64; y = y + 1) begin
                for (x = 0; x < 64; x = x + 1) begin
                    src_mem[SRC_BASE + y*64 + x] = byte'(((y * 29) + (x * 17) + (x * y * 3) + 7) & 8'hFF);
                end
            end
        end
    endtask

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
            wr_active_reg      = 1'b0;
            cycle_count        = 0;
            trace_accept_count = 0;
            trace_fill_count   = 0;
            trace_done_reg     = 1'b0;
            init_memory();
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
            while (!(s_axi_ctrl_awready && s_axi_ctrl_wready)) @(posedge axi_clk);
            @(posedge axi_clk);
            s_axi_ctrl_awvalid <= 1'b0;
            s_axi_ctrl_wvalid  <= 1'b0;
            while (!s_axi_ctrl_bvalid) @(posedge axi_clk);
            if (s_axi_ctrl_bresp != 2'b00) $fatal(1, "AXI-Lite write response error at addr %h", addr);
            @(posedge axi_clk);
            s_axi_ctrl_bready <= 1'b0;
        end
    endtask

    task automatic program_case(input bit prefetch_en);
        begin
            axil_write(12'h004, SRC_BASE);
            axil_write(12'h008, DST_BASE);
            axil_write(12'h00C, 32'd64);
            axil_write(12'h010, 32'd64);
            axil_write(12'h014, {16'd64, 16'd64});
            axil_write(12'h018, {16'd24, 16'd24});
            axil_write(12'h020, 32'sh0000_B505);
            axil_write(12'h024, 32'sh0000_B505);
            axil_write(12'h038, {31'd0, prefetch_en});
            axil_write(12'h000, 32'h0000_0003);
        end
    endtask

    always_ff @(posedge axi_clk) begin
        int byte_idx;
        logic [AXI_ADDR_W-1:0] beat_addr;
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
            m_axi_wr_awready    <= 1'b0;
            m_axi_wr_wready     <= 1'b0;
            m_axi_wr_bvalid     <= 1'b0;
            m_axi_wr_bresp      <= 2'b00;
            wr_active_reg       <= 1'b0;
            wr_active_addr_reg  <= '0;
            wr_active_beats_reg <= 0;
            wr_active_idx_reg   <= 0;
        end else begin
            m_axi_rd_arready <= 1'b1;
            if (!rd_active_reg && m_axi_rd_arvalid && m_axi_rd_arready) begin
                rd_active_reg       <= 1'b1;
                rd_active_addr_reg  <= m_axi_rd_araddr;
                rd_active_beats_reg <= m_axi_rd_arlen + 1;
                rd_active_idx_reg   <= 0;
                m_axi_rd_rvalid     <= 1'b1;
                m_axi_rd_rdata      <= {src_mem[m_axi_rd_araddr + 3], src_mem[m_axi_rd_araddr + 2], src_mem[m_axi_rd_araddr + 1], src_mem[m_axi_rd_araddr + 0]};
                m_axi_rd_rresp      <= 2'b00;
                m_axi_rd_rlast      <= (m_axi_rd_arlen == 0);
            end else if (rd_active_reg && m_axi_rd_rvalid && m_axi_rd_rready) begin
                if (rd_active_idx_reg == (rd_active_beats_reg - 1)) begin
                    rd_active_reg   <= 1'b0;
                    m_axi_rd_rvalid <= 1'b0;
                    m_axi_rd_rlast  <= 1'b0;
                end else begin
                    rd_active_idx_reg <= rd_active_idx_reg + 1;
                    m_axi_rd_rvalid   <= 1'b1;
                    m_axi_rd_rdata    <= {
                        src_mem[rd_active_addr_reg + (rd_active_idx_reg + 1)*BYTE_W + 3],
                        src_mem[rd_active_addr_reg + (rd_active_idx_reg + 1)*BYTE_W + 2],
                        src_mem[rd_active_addr_reg + (rd_active_idx_reg + 1)*BYTE_W + 1],
                        src_mem[rd_active_addr_reg + (rd_active_idx_reg + 1)*BYTE_W + 0]
                    };
                    m_axi_rd_rresp <= 2'b00;
                    m_axi_rd_rlast <= ((rd_active_idx_reg + 1) == (rd_active_beats_reg - 1));
                end
            end else if (!rd_active_reg) begin
                m_axi_rd_rvalid <= 1'b0;
                m_axi_rd_rlast  <= 1'b0;
            end

            m_axi_wr_awready <= 1'b1;
            m_axi_wr_wready  <= 1'b1;
            if (!wr_active_reg && m_axi_wr_awvalid && m_axi_wr_awready) begin
                wr_active_reg       <= 1'b1;
                wr_active_addr_reg  <= m_axi_wr_awaddr;
                wr_active_beats_reg <= m_axi_wr_awlen + 1;
                wr_active_idx_reg   <= 0;
                m_axi_wr_bvalid     <= 1'b0;
            end
            if (wr_active_reg && m_axi_wr_wvalid && m_axi_wr_wready) begin
                beat_addr = wr_active_addr_reg + wr_active_idx_reg*BYTE_W;
                for (byte_idx = 0; byte_idx < BYTE_W; byte_idx = byte_idx + 1) begin
                    if (m_axi_wr_wstrb[byte_idx]) dst_mem[beat_addr + byte_idx] <= m_axi_wr_wdata[8*byte_idx +: 8];
                end
                if (m_axi_wr_wlast || (wr_active_idx_reg == (wr_active_beats_reg - 1))) begin
                    wr_active_reg   <= 1'b0;
                    m_axi_wr_bvalid <= 1'b1;
                    m_axi_wr_bresp  <= 2'b00;
                end else begin
                    wr_active_idx_reg <= wr_active_idx_reg + 1;
                end
            end
            if (m_axi_wr_bvalid && m_axi_wr_bready) m_axi_wr_bvalid <= 1'b0;
        end
    end

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn) cycle_count <= 0;
        else cycle_count <= cycle_count + 1;
    end

    always_ff @(posedge core_clk) begin
        int tile_x0;
        int tile_y0;
        int tile_x1;
        int tile_y1;
        if (!core_rstn) begin
            trace_accept_count <= 0;
            trace_fill_count   <= 0;
            trace_done_reg     <= 1'b0;
        end else begin
            if (!trace_done_reg && dut.sample_req_valid && dut.sample_req_ready) begin
                tile_x0 = dut.sample_x0 / 16;
                tile_y0 = dut.sample_y0 / 16;
                tile_x1 = dut.sample_x1 / 16;
                tile_y1 = dut.sample_y1 / 16;
                if (trace_accept_count >= TRACE_START) begin
                    $display("TRACE_REQ idx=%0d dst=(%0d,%0d) src=(%0d,%0d)-(%0d,%0d) tiles=(%0d,%0d)-(%0d,%0d) scan=(%0d,%0d) cache_reads=%0d misses=%0d pref=%0d hits=%0d",
                        trace_accept_count,
                        dut.u_rotate_core_bilinear.dst_x_reg,
                        dut.u_rotate_core_bilinear.dst_y_reg,
                        dut.sample_x0, dut.sample_y0, dut.sample_x1, dut.sample_y1,
                        tile_x0, tile_y0, tile_x1, tile_y1,
                        dut.sample_scan_dir_x, dut.sample_scan_dir_y,
                        dut.src_cache_stat_read_starts,
                        dut.src_cache_stat_misses,
                        dut.src_cache_stat_prefetch_starts,
                        dut.src_cache_stat_prefetch_hits);
                end
                trace_accept_count <= trace_accept_count + 1;
                if (trace_accept_count + 1 >= (TRACE_START + TRACE_LIMIT)) trace_done_reg <= 1'b1;
            end
            if (dut.u_src_tile_cache.fill_plan_seed_valid_reg && (trace_fill_count < (TRACE_START + TRACE_LIMIT))) begin
                if (trace_accept_count >= TRACE_START) begin
                    $display("TRACE_FILL idx=%0d kind=%s tile=(%0d,%0d) slot=%0d misses=%0d pref=%0d",
                        trace_fill_count,
                        dut.u_src_tile_cache.fill_request_is_prefetch ? "prefetch" : "demand",
                        dut.u_src_tile_cache.fill_request_tile_x,
                        dut.u_src_tile_cache.fill_request_tile_y,
                        dut.u_src_tile_cache.fill_request_slot_sel,
                        dut.src_cache_stat_misses,
                        dut.src_cache_stat_prefetch_starts);
                end
                trace_fill_count <= trace_fill_count + 1;
            end
        end
    end

    initial begin
        reset_dut();
        program_case(1'b1);
        while (!trace_done_reg) begin
            @(posedge core_clk);
            if (cycle_count > 200000) $fatal(1, "Trace run timed out before collecting %0d accepted requests", TRACE_LIMIT);
        end
        repeat (20) @(posedge core_clk);
        $display("TRACE_SUMMARY accepted=%0d fills=%0d reads=%0d misses=%0d pref=%0d hits=%0d",
            trace_accept_count, trace_fill_count,
            dut.src_cache_stat_read_starts,
            dut.src_cache_stat_misses,
            dut.src_cache_stat_prefetch_starts,
            dut.src_cache_stat_prefetch_hits);
        $finish;
    end

endmodule
