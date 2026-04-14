`timescale 1ns/1ps

// 模块职责：
// 1. 作为 DDR 写回路径的顶层封装。
// 2. 负责把像素流打包并交给 AXI 写突发模块。
// 3. 对外提供稳定的任务启动、忙闲和结果接口。
import ddr_axi_pkg::*;
module ddr_write_engine #(
    parameter int DATA_W        = 32,
    parameter int ADDR_W        = 32,
    parameter int PIXEL_W       = 8,
    parameter int BURST_MAX_LEN = 256,
    parameter int AXI_ID_W      = 8,
    parameter int FIFO_DEPTH_PIXELS = 256
) (
    input  logic               axi_clk,
    input  logic               core_clk,
    input  logic               sys_rst,
    input  logic               task_start,
    input  logic [ADDR_W-1:0]  task_addr,
    input  logic [31:0]        task_byte_count,
    output logic               task_busy,
    output logic               task_done,
    output logic               task_error,
    input  logic [PIXEL_W-1:0] in_data,
    input  logic               in_valid,
    output logic               in_ready,
    taxi_axi_if.wr_mst         m_axi_wr
);

    logic                  task_ready_core;
    logic                  task_start_accept;
    logic                  task_active_reg;
    logic                  task_valid_axi;
    logic [ADDR_W-1:0]     task_addr_axi;
    logic [31:0]           task_byte_count_axi;
    logic                  task_ready_axi;
    logic                  start_accept_axi;
    logic [DATA_W-1:0]     packed_word_data;
    logic [(DATA_W/8)-1:0] packed_word_strb;
    logic                  packed_word_valid;
    logic                  packed_word_ready;
    logic                  pixel_ready_axi;
    logic                  task_busy_axi;
    logic                  pixel_fifo_rd_en;
    logic [PIXEL_W-1:0]    pixel_fifo_rd_data;
    logic                  pixel_fifo_empty;
    logic                  pixel_fifo_full;
    logic                  pixel_fifo_underflow;
    logic                  result_valid_axi;
    logic                  result_done_axi;
    logic                  result_error_axi;
    logic                  result_ready_axi;
    logic                  result_valid_core;
    logic                  result_done_evt_core;
    logic                  result_error_evt_core;

    assign task_start_accept = task_start && !task_active_reg && task_ready_core && (task_byte_count != 0);
    assign task_busy         = task_active_reg;
    assign task_done         = result_done_evt_core;
    assign result_ready_axi  = 1'b1;
    assign start_accept_axi  = task_valid_axi && task_ready_axi;
    assign task_ready_axi    = !task_busy_axi;
    assign pixel_fifo_rd_en  = pixel_ready_axi && !pixel_fifo_empty;
    assign task_error        = result_error_evt_core;

    always_ff @(posedge core_clk) begin
        if (sys_rst) begin
            task_active_reg <= 1'b0;
        end else begin
            if (task_start_accept) begin
                task_active_reg <= 1'b1;
            end else if (result_done_evt_core || result_error_evt_core) begin
                task_active_reg <= 1'b0;
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
        .result_ready_src(),
        .dst_clk(core_clk),
        .result_valid_dst(result_valid_core),
        .result_done_dst(result_done_evt_core),
        .result_error_dst(result_error_evt_core)
    );

    async_word_fifo #(
        .DATA_W(PIXEL_W),
        .DEPTH(FIFO_DEPTH_PIXELS),
        .ALMOST_FULL_MARGIN(8)
    ) u_async_pixel_fifo (
        .wr_clk(core_clk),
        .sys_rst(sys_rst),
        .wr_en(in_valid && in_ready),
        .wr_data(in_data),
        .full(pixel_fifo_full),
        .almost_full(),
        .wr_count(),
        .overflow(),
        .rd_clk(axi_clk),
        .rd_en(pixel_fifo_rd_en),
        .rd_data(pixel_fifo_rd_data),
        .empty(pixel_fifo_empty),
        .rd_count(),
        .underflow(pixel_fifo_underflow)
    );

    assign in_ready = !pixel_fifo_full;

    pixel_packer #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PIXEL_W(PIXEL_W)
    ) u_pixel_packer (
        .clk(axi_clk),
        .sys_rst(sys_rst),
        .task_start(start_accept_axi),
        .task_addr(task_addr_axi),
        .task_byte_count(task_byte_count_axi),
        .pixel_data(pixel_fifo_rd_data),
        .pixel_valid(!pixel_fifo_empty),
        .pixel_ready(pixel_ready_axi),
        .word_data(packed_word_data),
        .word_strb(packed_word_strb),
        .word_valid(packed_word_valid),
        .word_ready(packed_word_ready)
    );

    axi_burst_writer #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .BURST_MAX_LEN(BURST_MAX_LEN),
        .AXI_ID_W(AXI_ID_W)
    ) u_axi_burst_writer (
        .clk(axi_clk),
        .sys_rst(sys_rst),
        .task_valid(start_accept_axi),
        .task_ready(),
        .task_busy(task_busy_axi),
        .task_addr(task_addr_axi),
        .task_byte_count(task_byte_count_axi),
        .word_data(packed_word_data),
        .word_strb(packed_word_strb),
        .word_valid(packed_word_valid),
        .word_ready(packed_word_ready),
        .result_valid(result_valid_axi),
        .result_ready(result_ready_axi),
        .result_done(result_done_axi),
        .result_error(result_error_axi),
        .m_axi_wr(m_axi_wr)
    );

endmodule
