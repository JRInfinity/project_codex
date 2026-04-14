`timescale 1ns/1ps
// 说明：修改测试场景或检查项时，同步更新 tb_ddr_write_engine.md。

// Keep tb_ddr_write_engine.md in sync
module tb_ddr_write_engine;

    // 测试目标：
    // 1. 覆盖像素打包与 AXI 写突发路径
    // 2. 检查写回内存内容、任务完成和错误行为

    localparam int DATA_W        = 32;
    localparam int ADDR_W        = 32;
    localparam int PIXEL_W       = 8;
    localparam int BURST_MAX_LEN = 8;
    localparam int AXI_ID_W      = 4;
    localparam int MEM_BYTES     = 8192;
    localparam int BYTE_W        = DATA_W / 8;
    localparam logic [2:0] AXI_SIZE = $clog2(BYTE_W);

    logic axi_clk;
    logic core_clk;
    logic sys_rst;

    logic               task_start;
    logic [ADDR_W-1:0]  task_addr;
    logic [31:0]        task_byte_count;
    logic               task_busy;
    logic               task_done;
    logic               task_error;
    logic [PIXEL_W-1:0] in_data;
    logic               in_valid;
    logic               in_ready;

    taxi_axi_if #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(AXI_ID_W)
    ) m_axi_wr ();

    ddr_write_engine #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PIXEL_W(PIXEL_W),
        .BURST_MAX_LEN(BURST_MAX_LEN),
        .AXI_ID_W(AXI_ID_W)
    ) dut (
        .axi_clk(axi_clk),
        .core_clk(core_clk),
        .sys_rst(sys_rst),
        .task_start(task_start),
        .task_addr(task_addr),
        .task_byte_count(task_byte_count),
        .task_busy(task_busy),
        .task_done(task_done),
        .task_error(task_error),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .m_axi_wr(m_axi_wr)
    );

    byte expected [0:MEM_BYTES-1];
    byte written  [0:MEM_BYTES-1];

    logic [ADDR_W-1:0] active_awaddr_reg;
    int unsigned       active_awbeats_reg;
    int unsigned       active_wbeat_idx_reg;
    bit                active_write_reg;
    bit                inject_bresp_error;
    bit                enable_in_backpressure;
    int                input_idx_reg;
    int                cycle_count;
    int                expected_start_idx;
    int                expected_byte_count_reg;

    initial axi_clk = 1'b0;
    always #2.5 axi_clk = ~axi_clk;

    initial core_clk = 1'b0;
    always #5 core_clk = ~core_clk;

    assign in_valid = !sys_rst && task_busy && (!enable_in_backpressure || ((cycle_count % 4) != 1));
    assign in_data  = expected[expected_start_idx + input_idx_reg];

    task automatic fill_expected;
        int idx;
        begin
            for (idx = 0; idx < MEM_BYTES; idx = idx + 1) begin
                expected[idx] = byte'((idx * 7) ^ (idx >> 1));
                written[idx]  = 8'hA5;
            end
        end
    endtask

    task automatic reset_dut;
        begin
            sys_rst               = 1'b1;
            task_start            = 1'b0;
            task_addr             = '0;
            task_byte_count       = '0;
            inject_bresp_error    = 1'b0;
            enable_in_backpressure = 1'b0;
            input_idx_reg         = 0;
            cycle_count           = 0;
            expected_start_idx    = 0;
            expected_byte_count_reg = 0;
            repeat (6) @(posedge core_clk);
            sys_rst = 1'b0;
            repeat (2) @(posedge core_clk);
        end
    endtask

    task automatic start_write(
        input logic [ADDR_W-1:0] addr,
        input logic [31:0]       byte_count
    );
        begin
            @(posedge core_clk);
            task_addr       <= addr;
            task_byte_count <= byte_count;
            task_start      <= 1'b1;
            @(posedge core_clk);
            task_start      <= 1'b0;
        end
    endtask

    always_ff @(posedge axi_clk) begin
        if (sys_rst) begin
            m_axi_wr.awready       <= 1'b0;
            m_axi_wr.wready        <= 1'b0;
            m_axi_wr.bid           <= '0;
            m_axi_wr.bresp         <= 2'b00;
            m_axi_wr.buser         <= '0;
            m_axi_wr.bvalid        <= 1'b0;
            active_awaddr_reg      <= '0;
            active_awbeats_reg     <= 0;
            active_wbeat_idx_reg   <= 0;
            active_write_reg       <= 1'b0;
        end else begin
            m_axi_wr.awready <= 1'b1;
            m_axi_wr.wready  <= 1'b1;

            if (m_axi_wr.awvalid && m_axi_wr.awready) begin
                if (m_axi_wr.awburst != 2'b01) $fatal(1, "AWBURST must be INCR.");
                if (m_axi_wr.awsize != AXI_SIZE) $fatal(1, "AWSIZE mismatch.");
                if ((m_axi_wr.awlen + 1) > BURST_MAX_LEN) $fatal(1, "AWLEN exceeds BURST_MAX_LEN.");
                if (((m_axi_wr.awaddr[11:0]) + ((m_axi_wr.awlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");

                active_awaddr_reg    <= m_axi_wr.awaddr;
                active_awbeats_reg   <= m_axi_wr.awlen + 1;
                active_wbeat_idx_reg <= 0;
                active_write_reg     <= 1'b1;
            end

            if (m_axi_wr.wvalid && m_axi_wr.wready) begin
                logic [ADDR_W-1:0] beat_addr;
                int byte_idx;

                if (!active_write_reg) $fatal(1, "W channel fired before AW.");
                beat_addr = active_awaddr_reg + active_wbeat_idx_reg * BYTE_W;

                for (byte_idx = 0; byte_idx < BYTE_W; byte_idx = byte_idx + 1) begin
                    if (m_axi_wr.wstrb[byte_idx]) begin
                        written[beat_addr + byte_idx] <= m_axi_wr.wdata[byte_idx*8 +: 8];
                    end
                end

                if (m_axi_wr.wlast != (active_wbeat_idx_reg == (active_awbeats_reg - 1))) begin
                    $fatal(1, "WLAST mismatch at beat %0d", active_wbeat_idx_reg);
                end

                if (active_wbeat_idx_reg == (active_awbeats_reg - 1)) begin
                    active_write_reg <= 1'b0;
                    m_axi_wr.bvalid  <= 1'b1;
                    m_axi_wr.bresp   <= inject_bresp_error ? 2'b10 : 2'b00;
                end else begin
                    active_wbeat_idx_reg <= active_wbeat_idx_reg + 1;
                end
            end

            if (m_axi_wr.bvalid && m_axi_wr.bready) begin
                m_axi_wr.bvalid <= 1'b0;
                m_axi_wr.bresp  <= 2'b00;
            end
        end
    end

    always_ff @(posedge core_clk) begin
        if (sys_rst) begin
        end else begin
            cycle_count <= cycle_count + 1;

            if (in_valid && in_ready) begin
                input_idx_reg <= input_idx_reg + 1;
            end
        end
    end

    task automatic expect_success(
        input string case_name,
        input logic [ADDR_W-1:0] addr,
        input logic [31:0]       byte_count,
        input bit                use_backpressure
    );
        int idx;
        begin
            $display("Running %s", case_name);
            fill_expected();
            reset_dut();
            enable_in_backpressure  = use_backpressure;
            expected_start_idx      = addr;
            expected_byte_count_reg = byte_count;

            start_write(addr, byte_count);

            while (!task_done && !task_error) begin
                @(posedge core_clk);
                if (cycle_count > 6000) begin
                    $fatal(
                        1,
                        "Timeout in %s busy=%0b in_idx=%0d awvalid=%0b wvalid=%0b bready=%0b bvalid=%0b state=%0d bytes_left=%0d burst_words=%0d sent=%0d burst_left=%0d bytes_in_word=%0d pack_valid=%0b",
                        case_name,
                        task_busy,
                        input_idx_reg,
                        m_axi_wr.awvalid,
                        m_axi_wr.wvalid,
                        m_axi_wr.bready,
                        m_axi_wr.bvalid,
                        dut.u_axi_burst_writer.state_reg,
                        dut.u_pixel_packer.bytes_remaining_reg,
                        dut.u_axi_burst_writer.burst_words_reg,
                        dut.u_axi_burst_writer.burst_sent_words_reg,
                        dut.u_axi_burst_writer.words_total_reg - dut.u_axi_burst_writer.words_sent_total_reg,
                        dut.u_pixel_packer.bytes_in_word_reg,
                        dut.u_pixel_packer.word_valid_reg
                    );
                end
            end

            if (task_error) $fatal(1, "%s unexpectedly asserted task_error", case_name);

            for (idx = 0; idx < byte_count; idx = idx + 1) begin
                if (written[addr + idx] !== expected[addr + idx]) begin
                    $fatal(1, "%s mismatch at idx=%0d got=%0d exp=%0d", case_name, idx, written[addr + idx], expected[addr + idx]);
                end
            end
        end
    endtask

    task automatic expect_error(
        input string case_name,
        input logic [ADDR_W-1:0] addr,
        input logic [31:0]       byte_count
    );
        begin
            $display("Running %s", case_name);
            fill_expected();
            reset_dut();
            inject_bresp_error      = 1'b1;
            expected_start_idx      = addr;
            expected_byte_count_reg = byte_count;

            start_write(addr, byte_count);

            while (!task_done && !task_error) begin
                @(posedge core_clk);
                if (cycle_count > 6000) begin
                    $fatal(
                        1,
                        "Timeout in %s busy=%0b in_idx=%0d awvalid=%0b wvalid=%0b bready=%0b bvalid=%0b state=%0d bytes_left=%0d burst_words=%0d sent=%0d burst_left=%0d bytes_in_word=%0d pack_valid=%0b",
                        case_name,
                        task_busy,
                        input_idx_reg,
                        m_axi_wr.awvalid,
                        m_axi_wr.wvalid,
                        m_axi_wr.bready,
                        m_axi_wr.bvalid,
                        dut.u_axi_burst_writer.state_reg,
                        dut.u_pixel_packer.bytes_remaining_reg,
                        dut.u_axi_burst_writer.burst_words_reg,
                        dut.u_axi_burst_writer.burst_sent_words_reg,
                        dut.u_axi_burst_writer.words_total_reg - dut.u_axi_burst_writer.words_sent_total_reg,
                        dut.u_pixel_packer.bytes_in_word_reg,
                        dut.u_pixel_packer.word_valid_reg
                    );
                end
            end

            if (!task_error) $fatal(1, "%s expected task_error", case_name);
            if (task_done) $fatal(1, "%s should not assert task_done after BRESP error", case_name);
        end
    endtask

    initial begin
        expect_success("aligned_whole_word", 32'h0000_0040, 32'd32, 1'b0);
        expect_success("unaligned_partial",  32'h0000_0043, 32'd19, 1'b0);
        expect_success("multi_burst",        32'h0000_0080, 32'd96, 1'b0);
        expect_success("split_4kb_boundary", 32'h0000_0FFB, 32'd24, 1'b0);
        expect_success("input_backpressure", 32'h0000_0123, 32'd73, 1'b1);
        expect_error("bresp_error",          32'h0000_0200, 32'd40);
        $display("tb_ddr_write_engine completed");
        $finish;
    end

endmodule
