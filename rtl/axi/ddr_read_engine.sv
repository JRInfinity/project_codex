`timescale 1ns/1ps

// 模块职责：
// 1. 在 core_clk 域接收一次读任务。
// 2. 通过 CDC 把任务送入 axi_clk 域，并驱动 AXI 读突发。
// 3. 把完整 DATA_W 数据字写入异步 FIFO。
// 4. 回到 core_clk 域后拆出像素流，并上报任务完成或错误。
module ddr_read_engine #(
    parameter int DATA_W                  = 32,
    parameter int ADDR_W                  = 32,
    parameter int PIXEL_W                 = 8,
    parameter int BURST_MAX_LEN           = 256,
    parameter int AXI_ID_W                = 8,
    parameter int FIFO_DEPTH_WORDS        = 64,
    parameter int MAX_OUTSTANDING_BURSTS  = 4,
    parameter int MAX_OUTSTANDING_BEATS   = 32
) (
    input  logic               axi_clk,
    input  logic               core_clk,
    input  logic               sys_rst,
    input  logic               task_start, // ctrl发出的读任务启动信号，pulse
    input  logic [ADDR_W-1:0]  task_addr, // ctrl发来的读任务起始地址
    input  logic [31:0]        task_byte_count, // ctrl发来的读任务字节数
    output logic               task_busy,
    output logic               task_done,
    output logic               task_error,
    output logic [PIXEL_W-1:0] out_data,
    output logic               out_valid,
    input  logic               out_ready,
    taxi_axi_if.rd_mst         m_axi_rd
);

    logic               task_ready_core;
    logic               task_valid_axi;
    logic [ADDR_W-1:0]  task_addr_axi;
    logic [31:0]        task_byte_count_axi;
    logic               task_ready_axi;
    logic               result_valid_axi;
    logic               result_done_axi;
    logic               result_error_axi;
    logic               result_ready_axi;

    logic               result_valid_core;
    logic               result_done_evt_core;
    logic               result_error_evt_core;
    logic               read_word_valid;
    logic [DATA_W-1:0]  read_word_data;
    logic               read_word_ready;
    logic               fifo_full;
    logic               fifo_almost_full;
    logic [$clog2(FIFO_DEPTH_WORDS+1)-1:0] fifo_wr_count;
    logic               fifo_rd_en;
    logic [DATA_W-1:0]  fifo_rd_data;
    logic               fifo_empty;
    logic               fifo_underflow;

    logic               unpacker_done_pulse;
    logic               unpacker_error_pulse;
    logic               unpacker_error_flag;
    logic               task_active_reg;
    logic               task_start_accept;

    initial begin
        if (DATA_W % 8 != 0) $error("ddr_read_engine requires DATA_W to be byte aligned.");
        if (PIXEL_W != 8) $error("Current pixel_unpacker implementation expects PIXEL_W == 8.");
        if (FIFO_DEPTH_WORDS < 4) $error("FIFO_DEPTH_WORDS must be at least 4 words.");
    end

    assign task_start_accept = task_start && !task_active_reg && task_ready_core && (task_byte_count != 32'd0);
    assign task_busy         = task_active_reg;
    assign task_done         = unpacker_done_pulse;
    assign read_word_ready   = !fifo_full;

    // core_clk 域中只维护任务生命周期和错误粘连。
    always_ff @(posedge core_clk) begin
        if (sys_rst) begin
            task_active_reg <= 1'b0;
            task_error      <= 1'b0;
        end else begin
            if (task_start_accept) begin
                task_active_reg <= 1'b1;
                task_error      <= 1'b0;
            end else if (unpacker_done_pulse || unpacker_error_pulse) begin
                task_active_reg <= 1'b0;
            end

            if (result_error_evt_core || unpacker_error_flag) begin
                task_error <= 1'b1;
            end
        end
    end

    task_cdc #(
        .ADDR_W(ADDR_W)
    ) u_task_cdc (
        .src_clk(core_clk),
        .sys_rst(sys_rst),
        .task_valid_src(task_start_accept),
        .task_addr_src(task_addr),
        .task_byte_count_src(task_byte_count),
        .task_ready_src(task_ready_core),
        .dst_clk(axi_clk),
        .task_valid_dst(task_valid_axi),
        .task_addr_dst(task_addr_axi),
        .task_byte_count_dst(task_byte_count_axi),
        .task_ready_dst(task_ready_axi)
    );

    result_cdc u_result_cdc (
        .src_clk(axi_clk),
        .sys_rst(sys_rst),
        .result_valid_src(result_valid_axi),
        .result_done_src(result_done_axi),
        .result_error_src(result_error_axi),
        .result_ready_src(result_ready_axi),
        .dst_clk(core_clk),
        .result_valid_dst(result_valid_core),
        .result_done_dst(result_done_evt_core),
        .result_error_dst(result_error_evt_core)
    );

    async_word_fifo #(
        .DATA_W(DATA_W),
        .DEPTH(FIFO_DEPTH_WORDS),
        .ALMOST_FULL_MARGIN(MAX_OUTSTANDING_BEATS)
    ) u_async_word_fifo (
        .wr_clk(axi_clk),
        .sys_rst(sys_rst),
        .wr_en(read_word_valid),
        .wr_data(read_word_data),
        .full(fifo_full),
        .almost_full(fifo_almost_full),
        .wr_count(fifo_wr_count),
        .overflow(),
        .rd_clk(core_clk),
        .rd_en(fifo_rd_en),
        .rd_data(fifo_rd_data),
        .empty(fifo_empty),
        .rd_count(),
        .underflow(fifo_underflow)
    );

    axi_burst_reader #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .BURST_MAX_LEN(BURST_MAX_LEN),
        .AXI_ID_W(AXI_ID_W),
        .FIFO_DEPTH_WORDS(FIFO_DEPTH_WORDS),
        .MAX_OUTSTANDING_BURSTS(MAX_OUTSTANDING_BURSTS),
        .MAX_OUTSTANDING_BEATS(MAX_OUTSTANDING_BEATS)
    ) u_axi_burst_reader (
        .axi_clk(axi_clk),
        .sys_rst(sys_rst),
        .task_valid(task_valid_axi),
        .task_ready(task_ready_axi),
        .task_addr(task_addr_axi),
        .task_byte_count(task_byte_count_axi),
        .word_valid(read_word_valid),
        .word_data(read_word_data),
        .word_ready(read_word_ready),
        .word_almost_full(fifo_almost_full),
        .word_count(fifo_wr_count),
        .result_valid(result_valid_axi),
        .result_done(result_done_axi),
        .result_error(result_error_axi),
        .result_ready(result_ready_axi),
        .m_axi_rd(m_axi_rd)
    );

    pixel_unpacker #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PIXEL_W(PIXEL_W)
    ) u_pixel_unpacker (
        .core_clk(core_clk),
        .sys_rst(sys_rst),
        .task_start(task_start_accept),
        .task_addr(task_addr),
        .task_byte_count(task_byte_count),
        .reader_status_valid(result_valid_core),
        .reader_done_evt(result_done_evt_core),
        .reader_error_evt(result_error_evt_core),
        .fifo_rd_en(fifo_rd_en),
        .fifo_rd_data(fifo_rd_data),
        .fifo_empty(fifo_empty),
        .fifo_underflow(fifo_underflow),
        .pixel_data(out_data),
        .pixel_valid(out_valid),
        .pixel_ready(out_ready),
        .task_done_pulse(unpacker_done_pulse),
        .task_error_pulse(unpacker_error_pulse),
        .task_error_flag(unpacker_error_flag)
    );

endmodule
