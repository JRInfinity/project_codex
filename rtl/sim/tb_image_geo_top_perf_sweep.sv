`timescale 1ns/1ps
// Keep tb_image_geo_top_perf_sweep.md in sync
module tb_image_geo_top_perf_sweep;

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
            init_memory();
            repeat (6) @(posedge axi_clk);
            axi_rstn  = 1'b1;
            core_rstn = 1'b1;
            repeat (2) @(posedge axi_clk);
        end
    endtask

    task automatic clear_dst_region;
        int idx;
        begin
            for (idx = 0; idx < 4096; idx = idx + 1) begin
                dst_mem[DST_BASE + idx] = 8'hA5;
            end
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
        end else begin
            m_axi_rd_arready <= 1'b1;

            if (!rd_active_reg && m_axi_rd_arvalid && m_axi_rd_arready) begin
                rd_active_reg       <= 1'b1;
                rd_active_addr_reg  <= m_axi_rd_araddr;
                rd_active_beats_reg <= m_axi_rd_arlen + 1;
                rd_active_idx_reg   <= 0;
                m_axi_rd_rvalid     <= 1'b1;
                m_axi_rd_rdata      <= {
                    src_mem[m_axi_rd_araddr + 3],
                    src_mem[m_axi_rd_araddr + 2],
                    src_mem[m_axi_rd_araddr + 1],
                    src_mem[m_axi_rd_araddr + 0]
                };
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
        end
    end

    always_ff @(posedge axi_clk) begin
        int byte_idx;
        logic [AXI_ADDR_W-1:0] beat_addr;

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

                beat_addr = wr_active_addr_reg + wr_active_idx_reg*BYTE_W;
                for (byte_idx = 0; byte_idx < BYTE_W; byte_idx = byte_idx + 1) begin
                    if (m_axi_wr_wstrb[byte_idx]) begin
                        dst_mem[beat_addr + byte_idx] <= m_axi_wr_wdata[byte_idx*8 +: 8];
                    end
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

    function automatic byte bilinear_ref_generic(
        input int src_base,
        input int src_stride,
        input int src_w,
        input int src_h,
        input int dst_w,
        input int dst_h,
        input int xd,
        input int yd,
        input int signed sin_q16,
        input int signed cos_q16
    );
        longint signed frac_one;
        longint signed scale_x_q16;
        longint signed scale_y_q16;
        longint signed step_x_x;
        longint signed step_y_x;
        longint signed step_x_y;
        longint signed step_y_y;
        longint signed src_cx_q16;
        longint signed src_cy_q16;
        longint signed dst_cx_q16;
        longint signed dst_cy_q16;
        longint signed x_q16;
        longint signed y_q16;
        longint signed frac_x;
        longint signed frac_y;
        int x0;
        int y0;
        int x1;
        int y1;
        longint signed top_mix;
        longint signed bot_mix;
        longint signed out_mix;
        byte p00;
        byte p01;
        byte p10;
        byte p11;
        begin
            frac_one    = 1 <<< 16;
            scale_x_q16 = (frac_one * src_w) / dst_w;
            scale_y_q16 = (frac_one * src_h) / dst_h;
            step_x_x    = (cos_q16 * scale_x_q16) >>> 16;
            step_y_x    = -((sin_q16 * scale_x_q16) >>> 16);
            step_x_y    = (sin_q16 * scale_y_q16) >>> 16;
            step_y_y    = (cos_q16 * scale_y_q16) >>> 16;
            src_cx_q16  = (src_w - 1) <<< 15;
            src_cy_q16  = (src_h - 1) <<< 15;
            dst_cx_q16  = (dst_w - 1) <<< 15;
            dst_cy_q16  = (dst_h - 1) <<< 15;

            x_q16 = src_cx_q16
                  - ((dst_cx_q16 * step_x_x) >>> 16)
                  - ((dst_cy_q16 * step_x_y) >>> 16)
                  + (xd * step_x_x)
                  + (yd * step_x_y);
            y_q16 = src_cy_q16
                  - ((dst_cx_q16 * step_y_x) >>> 16)
                  - ((dst_cy_q16 * step_y_y) >>> 16)
                  + (xd * step_y_x)
                  + (yd * step_y_y);

            if (x_q16 < 0) x_q16 = 0;
            if (y_q16 < 0) y_q16 = 0;
            if (x_q16 > ((src_w - 1) <<< 16)) x_q16 = ((src_w - 1) <<< 16);
            if (y_q16 > ((src_h - 1) <<< 16)) y_q16 = ((src_h - 1) <<< 16);

            x0 = x_q16 >>> 16;
            y0 = y_q16 >>> 16;
            frac_x = x_q16 & 16'hFFFF;
            frac_y = y_q16 & 16'hFFFF;
            x1 = (x0 >= (src_w - 1)) ? (src_w - 1) : (x0 + 1);
            y1 = (y0 >= (src_h - 1)) ? (src_h - 1) : (y0 + 1);

            p00 = src_mem[src_base + y0*src_stride + x0];
            p01 = src_mem[src_base + y0*src_stride + x1];
            p10 = src_mem[src_base + y1*src_stride + x0];
            p11 = src_mem[src_base + y1*src_stride + x1];

            top_mix = (($unsigned(p00) * (frac_one - frac_x)) +
                       ($unsigned(p01) * frac_x) +
                       (1 <<< 15)) >>> 16;
            bot_mix = (($unsigned(p10) * (frac_one - frac_x)) +
                       ($unsigned(p11) * frac_x) +
                       (1 <<< 15)) >>> 16;
            out_mix = ((top_mix * (frac_one - frac_y)) +
                       (bot_mix * frac_y) +
                       (1 <<< 15)) >>> 16;

            bilinear_ref_generic = byte'(out_mix[7:0]);
        end
    endfunction

    task automatic wait_for_irq;
        begin
            while (!irq) begin
                @(posedge axi_clk);
                if (cycle_count > 800000) begin
                    $fatal(1, "Perf sweep top-level simulation timed out waiting for irq");
                end
            end
        end
    endtask

    task automatic check_status_done_ok;
        logic [31:0] status_data;
        begin
            axil_read(12'h01C, status_data);
            if (!status_data[1]) begin
                $fatal(1, "Perf sweep status did not report done: 0x%08h", status_data);
            end
            if (status_data[2]) begin
                $fatal(1, "Perf sweep status reported error: 0x%08h", status_data);
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
            axil_read(12'h028, reads);
            axil_read(12'h02C, misses);
            axil_read(12'h030, prefetches);
            axil_read(12'h034, prefetch_hits);
        end
    endtask

    task automatic program_case(
        input int src_w,
        input int src_h,
        input int dst_w,
        input int dst_h,
        input int signed sin_q16,
        input int signed cos_q16,
        input bit prefetch_en
    );
        begin
            clear_dst_region();
            axil_write(12'h004, SRC_BASE);
            axil_write(12'h008, DST_BASE);
            axil_write(12'h00C, 32'd64);
            axil_write(12'h010, 32'd64);
            axil_write(12'h014, {src_h[15:0], src_w[15:0]});
            axil_write(12'h018, {dst_h[15:0], dst_w[15:0]});
            axil_write(12'h020, sin_q16);
            axil_write(12'h024, cos_q16);
            axil_write(12'h038, {31'd0, prefetch_en});
            axil_write(12'h000, 32'h0000_0003);
        end
    endtask

    task automatic check_transform_ref_generic(
        input int src_base,
        input int dst_base,
        input int src_stride,
        input int src_w,
        input int src_h,
        input int dst_w,
        input int dst_h,
        input int signed sin_q16,
        input int signed cos_q16
    );
        int x;
        int y;
        int dst_addr;
        byte expected;
        begin
            for (y = 0; y < dst_h; y = y + 1) begin
                for (x = 0; x < dst_w; x = x + 1) begin
                    dst_addr = dst_base + y*64 + x;
                    expected = bilinear_ref_generic(src_base, src_stride, src_w, src_h, dst_w, dst_h, x, y, sin_q16, cos_q16);
                    if (dst_mem[dst_addr] !== expected) begin
                        $fatal(1, "Perf sweep mismatch at dst(%0d,%0d): got=%0d exp=%0d",
                            x, y, dst_mem[dst_addr], expected);
                    end
                end
            end
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
        output logic [31:0] reads,
        output logic [31:0] misses,
        output logic [31:0] prefetches,
        output logic [31:0] prefetch_hits
    );
        begin
            reset_dut();
            program_case(src_w, src_h, dst_w, dst_h, sin_q16, cos_q16, prefetch_en);
            wait_for_irq();
            check_status_done_ok();
            check_transform_ref_generic(SRC_BASE, DST_BASE, 64, src_w, src_h, dst_w, dst_h, sin_q16, cos_q16);
            read_cache_stats(reads, misses, prefetches, prefetch_hits);
            $display("PERF case=%s prefetch=%0d src=%0dx%0d dst=%0dx%0d sin=0x%08h cos=0x%08h reads=%0d misses=%0d prefetches=%0d hits=%0d",
                case_name, prefetch_en, src_w, src_h, dst_w, dst_h, sin_q16, cos_q16,
                reads, misses, prefetches, prefetch_hits);
        end
    endtask

    initial begin
        logic [31:0] reads_off;
        logic [31:0] misses_off;
        logic [31:0] pref_off;
        logic [31:0] hits_off;
        logic [31:0] reads_on;
        logic [31:0] misses_on;
        logic [31:0] pref_on;
        logic [31:0] hits_on;

        run_case("identity_64x16", 64, 16, 64, 16, 32'sh0000_0000, 32'sh0001_0000, 1'b0,
            reads_off, misses_off, pref_off, hits_off);
        run_case("identity_64x16", 64, 16, 64, 16, 32'sh0000_0000, 32'sh0001_0000, 1'b1,
            reads_on, misses_on, pref_on, hits_on);
        if (pref_off != 0 || hits_off != 0) begin
            $fatal(1, "identity_64x16 prefetch-off counters should be zero");
        end

        run_case("downscale_64_to_32", 64, 64, 32, 32, 32'sh0000_0000, 32'sh0001_0000, 1'b0,
            reads_off, misses_off, pref_off, hits_off);
        run_case("downscale_64_to_32", 64, 64, 32, 32, 32'sh0000_0000, 32'sh0001_0000, 1'b1,
            reads_on, misses_on, pref_on, hits_on);
        if (pref_off != 0 || hits_off != 0) begin
            $fatal(1, "downscale_64_to_32 prefetch-off counters should be zero");
        end

        run_case("rotate45_48_to_32", 48, 48, 32, 32, 32'sh0000_B505, 32'sh0000_B505, 1'b0,
            reads_off, misses_off, pref_off, hits_off);
        run_case("rotate45_48_to_32", 48, 48, 32, 32, 32'sh0000_B505, 32'sh0000_B505, 1'b1,
            reads_on, misses_on, pref_on, hits_on);
        if (pref_off != 0 || hits_off != 0) begin
            $fatal(1, "rotate45_48_to_32 prefetch-off counters should be zero");
        end

        run_case("rotate90_32x48", 32, 48, 32, 48, 32'sh0001_0000, 32'sh0000_0000, 1'b0,
            reads_off, misses_off, pref_off, hits_off);
        run_case("rotate90_32x48", 32, 48, 32, 48, 32'sh0001_0000, 32'sh0000_0000, 1'b1,
            reads_on, misses_on, pref_on, hits_on);
        if (pref_off != 0 || hits_off != 0) begin
            $fatal(1, "rotate90_32x48 prefetch-off counters should be zero");
        end

        run_case("rotate45_downscale_64_to_24", 64, 64, 24, 24, 32'sh0000_B505, 32'sh0000_B505, 1'b0,
            reads_off, misses_off, pref_off, hits_off);
        run_case("rotate45_downscale_64_to_24", 64, 64, 24, 24, 32'sh0000_B505, 32'sh0000_B505, 1'b1,
            reads_on, misses_on, pref_on, hits_on);
        if (pref_off != 0 || hits_off != 0) begin
            $fatal(1, "rotate45_downscale_64_to_24 prefetch-off counters should be zero");
        end

        $display("tb_image_geo_top_perf_sweep completed");
        $finish;
    end

endmodule
