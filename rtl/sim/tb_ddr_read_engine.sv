`timescale 1ns/1ps
// 说明：修改测试场景或检查项时，同步更新 tb_ddr_read_engine.md。

module tb_ddr_read_engine;

    // 测试目标：
    // 1. 覆盖跨拍突发读取与像素拆包路径
    // 2. 检查任务完成、错误和输出像素序列是否正确

    localparam int DATA_W                 = 32;
    localparam int ADDR_W                 = 32;
    localparam int PIXEL_W                = 8;
    localparam int BURST_MAX_LEN          = 8;
    localparam int AXI_ID_W               = 4;
    localparam int FIFO_DEPTH_WORDS       = 32;
    localparam int MAX_OUTSTANDING_BURSTS = 3;
    localparam int MAX_OUTSTANDING_BEATS  = 12;
    localparam int MEM_BYTES              = 8192;
    localparam int BYTE_W                 = DATA_W / 8;
    localparam logic [2:0] AXI_SIZE       = $clog2(BYTE_W);

    logic axi_clk;
    logic core_clk;
    logic sys_rst;

    logic               task_start;
    logic [ADDR_W-1:0]  task_addr;
    logic [31:0]        task_byte_count;
    logic               task_busy;
    logic               task_done;
    logic               task_error;
    logic [PIXEL_W-1:0] out_data;
    logic               out_valid;
    logic               out_ready;

    taxi_axi_if #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .ID_W(AXI_ID_W)
    ) m_axi_rd ();

    ddr_read_engine #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PIXEL_W(PIXEL_W),
        .BURST_MAX_LEN(BURST_MAX_LEN),
        .AXI_ID_W(AXI_ID_W),
        .FIFO_DEPTH_WORDS(FIFO_DEPTH_WORDS),
        .MAX_OUTSTANDING_BURSTS(MAX_OUTSTANDING_BURSTS),
        .MAX_OUTSTANDING_BEATS(MAX_OUTSTANDING_BEATS)
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
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .m_axi_rd(m_axi_rd)
    );

    byte mem [0:MEM_BYTES-1];
    byte observed [0:MEM_BYTES-1];

    logic [ADDR_W-1:0] ar_addr_queue [0:63];
    int unsigned       ar_beats_queue [0:63];
    int                ar_head_reg;
    int                ar_tail_reg;
    int                ar_count_reg;

    logic [ADDR_W-1:0] active_addr_reg;
    int unsigned       active_beats_reg;
    bit      active_cmd_valid_reg;
    int      active_beat_idx_reg;
    int      global_rbeat_idx_reg;

    int      observed_count;
    int      core_cycle_count;

    bit      enable_backpressure;
    bit      inject_rresp_error;
    bit      inject_rlast_error;
    int      inject_rresp_on_beat;

    bit      saw_first_rlast;
    bit      saw_second_ar_before_first_rlast;
    bit      saw_axi_accept_while_out_stalled;

    initial axi_clk = 1'b0;
    always #2.5 axi_clk = ~axi_clk;

    initial core_clk = 1'b0;
    always #5 core_clk = ~core_clk;

    task automatic fill_memory;
        int idx;
        begin
            for (idx = 0; idx < MEM_BYTES; idx = idx + 1) begin
                mem[idx] = byte'((idx * 13) ^ (idx >> 2));
            end
        end
    endtask

    task automatic drive_r_outputs(
        input logic [ADDR_W-1:0] addr,
        input int unsigned beats,
        input int beat_idx
    );
        logic [ADDR_W-1:0] beat_addr;
        begin
            beat_addr        = addr + beat_idx * BYTE_W;
            m_axi_rd.rvalid <= 1'b1;
            m_axi_rd.rid    <= '0;
            m_axi_rd.rdata  <= {mem[beat_addr + 3], mem[beat_addr + 2], mem[beat_addr + 1], mem[beat_addr + 0]};
            m_axi_rd.rresp  <= (inject_rresp_error && (global_rbeat_idx_reg == inject_rresp_on_beat)) ? 2'b10 : 2'b00;
            m_axi_rd.rlast  <= (beat_idx == (beats - 1));
            if (inject_rlast_error && (beats > 1) && (beat_idx == 0)) begin
                m_axi_rd.rlast <= 1'b1;
            end
        end
    endtask

    always_ff @(posedge axi_clk) begin
        if (sys_rst) begin
            m_axi_rd.arready <= 1'b0;
            m_axi_rd.rid     <= '0;
            m_axi_rd.rdata   <= '0;
            m_axi_rd.rresp   <= 2'b00;
            m_axi_rd.rlast   <= 1'b0;
            m_axi_rd.ruser   <= '0;
            m_axi_rd.rvalid  <= 1'b0;
            ar_head_reg                      <= 0;
            ar_tail_reg                      <= 0;
            ar_count_reg                     <= 0;
            active_addr_reg                  <= '0;
            active_beats_reg                 <= 0;
            active_cmd_valid_reg             <= 1'b0;
            active_beat_idx_reg              <= 0;
            global_rbeat_idx_reg             <= 0;
            saw_first_rlast                  <= 1'b0;
            saw_second_ar_before_first_rlast <= 1'b0;
            saw_axi_accept_while_out_stalled <= 1'b0;
        end else begin
            m_axi_rd.arready <= 1'b1;

            if (m_axi_rd.arvalid && m_axi_rd.arready) begin
                if (m_axi_rd.arburst != 2'b01) $fatal(1, "ARBURST must be INCR.");
                if (m_axi_rd.arsize != AXI_SIZE) $fatal(1, "ARSIZE mismatch.");
                if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");
                if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");

                ar_addr_queue[ar_tail_reg]  <= m_axi_rd.araddr;
                ar_beats_queue[ar_tail_reg] <= m_axi_rd.arlen + 1;
                ar_tail_reg                 <= (ar_tail_reg + 1) % 64;
                ar_count_reg                <= ar_count_reg + 1;
                if (!saw_first_rlast && ((ar_count_reg != 0) || active_cmd_valid_reg)) begin
                    saw_second_ar_before_first_rlast <= 1'b1;
                end
            end

            if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin
                active_addr_reg      <= ar_addr_queue[ar_head_reg];
                active_beats_reg     <= ar_beats_queue[ar_head_reg];
                active_cmd_valid_reg <= 1'b1;
                active_beat_idx_reg  <= 0;
                ar_head_reg          <= (ar_head_reg + 1) % 64;
                ar_count_reg         <= ar_count_reg - 1;
                drive_r_outputs(ar_addr_queue[ar_head_reg], ar_beats_queue[ar_head_reg], 0);
            end else if (m_axi_rd.rvalid && m_axi_rd.rready) begin
                if (m_axi_rd.rlast) begin
                    saw_first_rlast <= 1'b1;
                end

                if (!out_ready) begin
                    saw_axi_accept_while_out_stalled <= 1'b1;
                end

                global_rbeat_idx_reg <= global_rbeat_idx_reg + 1;

                if ((active_beat_idx_reg + 1) < active_beats_reg) begin
                    active_beat_idx_reg <= active_beat_idx_reg + 1;
                    drive_r_outputs(active_addr_reg, active_beats_reg, active_beat_idx_reg + 1);
                end else if (ar_count_reg != 0) begin
                    active_addr_reg       <= ar_addr_queue[ar_head_reg];
                    active_beats_reg      <= ar_beats_queue[ar_head_reg];
                    active_cmd_valid_reg <= 1'b1;
                    active_beat_idx_reg   <= 0;
                    ar_head_reg           <= (ar_head_reg + 1) % 64;
                    ar_count_reg          <= ar_count_reg - 1;
                    drive_r_outputs(ar_addr_queue[ar_head_reg], ar_beats_queue[ar_head_reg], 0);
                end else begin
                    active_cmd_valid_reg <= 1'b0;
                    active_beat_idx_reg  <= 0;
                    m_axi_rd.rvalid      <= 1'b0;
                    m_axi_rd.rresp       <= 2'b00;
                    m_axi_rd.rlast       <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge core_clk) begin
        if (sys_rst) begin
            out_ready       <= 1'b0;
            observed_count  <= 0;
            core_cycle_count <= 0;
        end else begin
            core_cycle_count <= core_cycle_count + 1;
            if (!enable_backpressure) begin
                out_ready <= 1'b1;
            end else begin
                out_ready <= ((core_cycle_count % 5) != 2);
            end

            if (out_valid && out_ready) begin
                observed[observed_count] <= out_data;
                observed_count           <= observed_count + 1;
            end
        end
    end

    task automatic reset_dut;
        begin
            sys_rst                  = 1'b1;
            task_start               = 1'b0;
            task_addr                = '0;
            task_byte_count          = '0;
            enable_backpressure      = 1'b0;
            inject_rresp_error       = 1'b0;
            inject_rlast_error       = 1'b0;
            inject_rresp_on_beat     = 2;
            observed_count           = 0;
            core_cycle_count         = 0;
            repeat (6) @(posedge axi_clk);
            repeat (4) @(posedge core_clk);
            sys_rst                  = 1'b0;
            repeat (4) @(posedge axi_clk);
        end
    endtask

    task automatic start_read(input logic [ADDR_W-1:0] addr, input logic [31:0] byte_count);
        begin
            @(posedge core_clk);
            task_addr       <= addr;
            task_byte_count <= byte_count;
            task_start      <= 1'b1;
            @(posedge core_clk);
            task_start      <= 1'b0;
        end
    endtask

    task automatic expect_success(
        input string case_name,
        input logic [ADDR_W-1:0] addr,
        input logic [31:0] byte_count,
        input bit backpressure
    );
        int idx;
        begin
            $display("Running %s", case_name);
            fill_memory();
            reset_dut();
            enable_backpressure = backpressure;

            start_read(addr, byte_count);

            while (!task_done && !task_error) begin
                @(posedge core_clk);
                if (core_cycle_count > 6000) $fatal(1, "Timeout in %s", case_name);
            end

            if (task_error) $fatal(1, "%s unexpectedly asserted task_error", case_name);
            if (observed_count != byte_count) $fatal(1, "%s byte count mismatch got=%0d exp=%0d", case_name, observed_count, byte_count);

            for (idx = 0; idx < byte_count; idx = idx + 1) begin
                if (observed[idx] !== mem[addr + idx]) begin
                    $fatal(1, "%s mismatch at idx=%0d got=%0d exp=%0d", case_name, idx, observed[idx], mem[addr + idx]);
                end
            end

            if ((byte_count > (BURST_MAX_LEN * BYTE_W)) && !saw_second_ar_before_first_rlast) begin
                $fatal(1, "%s did not issue a second AR before the first burst completed", case_name);
            end

            if (backpressure && !saw_axi_accept_while_out_stalled) begin
                $fatal(1, "%s did not keep accepting AXI data while out_ready was low", case_name);
            end
        end
    endtask

    task automatic expect_error(
        input string case_name,
        input logic [ADDR_W-1:0] addr,
        input logic [31:0] byte_count,
        input bit resp_err,
        input bit rlast_err
    );
        begin
            $display("Running %s", case_name);
            fill_memory();
            reset_dut();
            inject_rresp_error = resp_err;
            inject_rlast_error = rlast_err;

            start_read(addr, byte_count);

            while (!task_error) begin
                @(posedge core_clk);
                if (core_cycle_count > 6000) $fatal(1, "Timeout waiting for error in %s", case_name);
            end

            while (task_busy) begin
                @(posedge core_clk);
                if (core_cycle_count > 7000) $fatal(1, "Timeout waiting for busy to clear in %s", case_name);
            end

            if (task_done) $fatal(1, "%s should not assert task_done after an injected error", case_name);
        end
    endtask

    initial begin
        expect_success("aligned_whole_word",  32'h0000_0040, 32'd32, 1'b0);
        expect_success("unaligned_partial",   32'h0000_0043, 32'd19, 1'b0);
        expect_success("multi_burst",         32'h0000_0080, 32'd96, 1'b0);
        expect_success("split_4kb_boundary",  32'h0000_0FFB, 32'd24, 1'b0);
        expect_success("backpressure",        32'h0000_0123, 32'd73, 1'b1);
        expect_error("rresp_error",           32'h0000_0200, 32'd40, 1'b1, 1'b0);
        expect_error("rlast_error",           32'h0000_0300, 32'd40, 1'b0, 1'b1);
        $display("tb_ddr_read_engine completed");
        $finish;
    end

endmodule
