`timescale 1ns/1ps

module result_cdc (
    input  logic src_clk,
    input  logic src_rst,
    input  logic result_valid_src,
    input  logic result_done_src,
    input  logic result_error_src,
    output logic result_ready_src,
    input  logic dst_clk,
    input  logic dst_rst,
    output logic result_valid_dst,
    output logic result_done_dst,
    output logic result_error_dst
);

    logic [1:0] fifo_wr_data;
    logic [1:0] fifo_rd_data;
    logic       fifo_full;
    logic       fifo_empty;
    logic       fifo_overflow;
    logic       fifo_underflow;
    logic       fifo_almost_full;
    logic [3:0] fifo_wr_count;
    logic [3:0] fifo_rd_count;

    assign fifo_wr_data = {result_error_src, result_done_src};
    assign result_ready_src = !fifo_full;

    async_word_fifo #(
        .DATA_W(2),
        .DEPTH(16),
        .ALMOST_FULL_MARGIN(2)
    ) u_result_fifo (
        .wr_clk(src_clk),
        .wr_rst(src_rst),
        .wr_en(result_valid_src && result_ready_src),
        .wr_data(fifo_wr_data),
        .full(fifo_full),
        .almost_full(fifo_almost_full),
        .wr_count(fifo_wr_count),
        .overflow(fifo_overflow),

        .rd_clk(dst_clk),
        .rd_rst(dst_rst),
        .rd_en(!fifo_empty),
        .rd_data(fifo_rd_data),
        .empty(fifo_empty),
        .rd_count(fifo_rd_count),
        .underflow(fifo_underflow)
    );

    always_ff @(posedge dst_clk) begin
        if (dst_rst) begin
            result_valid_dst <= 1'b0;
            result_done_dst <= 1'b0;
            result_error_dst <= 1'b0;
        end else begin
            result_valid_dst <= !fifo_empty;
            result_done_dst <= !fifo_empty && fifo_rd_data[0];
            result_error_dst <= !fifo_empty && fifo_rd_data[1];
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge src_clk) begin
        if (!src_rst && result_valid_src && !result_ready_src) begin
            $error("result_cdc overflow: result_valid_src asserted while FIFO full");
        end
    end
`endif

endmodule
