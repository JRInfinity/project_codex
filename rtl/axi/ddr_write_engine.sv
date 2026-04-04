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
    parameter int AXI_ID_W      = 8
) (
    input  logic               clk,
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

    logic                  start_accept;
    logic [DATA_W-1:0]     packed_word_data;
    logic [(DATA_W/8)-1:0] packed_word_strb;
    logic                  packed_word_valid;
    logic                  packed_word_ready;
    logic                  result_valid;
    logic                  result_done;
    logic                  result_error;
    logic                  result_ready;

    assign start_accept = task_start && !task_busy && (task_byte_count != 0);
    assign result_ready = 1'b1;
    assign task_done    = result_valid && result_done;
    assign task_error   = result_valid && result_error;

    pixel_packer #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PIXEL_W(PIXEL_W)
    ) u_pixel_packer (
        .clk(clk),
        .sys_rst(sys_rst),
        .task_start(start_accept),
        .task_addr(task_addr),
        .task_byte_count(task_byte_count),
        .pixel_data(in_data),
        .pixel_valid(in_valid),
        .pixel_ready(in_ready),
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
        .clk(clk),
        .sys_rst(sys_rst),
        .task_valid(start_accept),
        .task_ready(),
        .task_busy(task_busy),
        .task_addr(task_addr),
        .task_byte_count(task_byte_count),
        .word_data(packed_word_data),
        .word_strb(packed_word_strb),
        .word_valid(packed_word_valid),
        .word_ready(packed_word_ready),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_done(result_done),
        .result_error(result_error),
        .m_axi_wr(m_axi_wr)
    );

endmodule
