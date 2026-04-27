`timescale 1ns/1ps

module async_word_fifo #(
    parameter int DATA_W             = 32,
    parameter int DEPTH              = 64,
    parameter int ALMOST_FULL_MARGIN = 4
) (
    input  logic wr_clk,
    input  logic wr_rst,
    input  logic wr_en,
    input  logic [DATA_W-1:0] wr_data,
    output logic full,
    output logic almost_full,
    output logic [$clog2(DEPTH+1)-1:0] wr_count,
    output logic overflow,

    input  logic rd_clk,
    input  logic rd_rst,
    input  logic rd_en,
    output logic [DATA_W-1:0] rd_data,
    output logic empty,
    output logic [$clog2(DEPTH+1)-1:0] rd_count,
    output logic underflow
);

    localparam int XPM_PROG_FULL_THRESH_MIN = 7;
    localparam int XPM_PROG_FULL_THRESH_MAX = DEPTH - 5;
    localparam int XPM_PROG_FULL_THRESH_REQ = DEPTH - ALMOST_FULL_MARGIN;
    localparam int XPM_PROG_FULL_THRESH =
        (XPM_PROG_FULL_THRESH_REQ < XPM_PROG_FULL_THRESH_MIN) ? XPM_PROG_FULL_THRESH_MIN :
        (XPM_PROG_FULL_THRESH_REQ > XPM_PROG_FULL_THRESH_MAX) ? XPM_PROG_FULL_THRESH_MAX :
        XPM_PROG_FULL_THRESH_REQ;
    logic fifo_rst;

    assign fifo_rst = wr_rst || rd_rst;

    initial begin
        if (DEPTH < 16) begin
            $error("async_word_fifo DEPTH must be >= 16 for XPM async FIFO");
        end
    end

`ifdef SYNTHESIS
    logic wr_rst_busy_int;
    logic rd_rst_busy_int;

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(DEPTH),
        .FULL_RESET_VALUE(0),
        .PROG_FULL_THRESH(XPM_PROG_FULL_THRESH),
        .RD_DATA_COUNT_WIDTH($clog2(DEPTH+1)),
        .READ_DATA_WIDTH(DATA_W),
        .READ_MODE("fwft"),
        .RELATED_CLOCKS(0),
        .SIM_ASSERT_CHK(0),
        .USE_ADV_FEATURES("0507"),
        .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(DATA_W),
        .WR_DATA_COUNT_WIDTH($clog2(DEPTH+1))
    ) xpm_fifo_async_inst (
        .sleep(1'b0),
        .rst(fifo_rst),
        .wr_clk(wr_clk),
        .wr_en(wr_en),
        .din(wr_data),
        .full(full),
        .overflow(overflow),
        .prog_full(almost_full),
        .wr_data_count(wr_count),
        .rd_clk(rd_clk),
        .rd_en(rd_en),
        .dout(rd_data),
        .empty(empty),
        .underflow(underflow),
        .rd_data_count(rd_count),
        .almost_empty(),
        .almost_full(),
        .data_valid(),
        .dbiterr(),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .prog_empty(),
        .rd_rst_busy(rd_rst_busy_int),
        .sbiterr(),
        .wr_ack(),
        .wr_rst_busy(wr_rst_busy_int)
    );
`else
    logic [DATA_W-1:0] fifo_q[$];

    always_comb begin
        full        = (fifo_q.size() >= DEPTH);
        empty       = (fifo_q.size() == 0);
        almost_full = (fifo_q.size() >= (DEPTH - ALMOST_FULL_MARGIN));
        wr_count    = fifo_q.size();
        rd_count    = fifo_q.size();
        rd_data     = empty ? '0 : fifo_q[0];
    end

    always_ff @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            fifo_q.delete();
            overflow <= 1'b0;
        end else begin
            overflow <= wr_en && full;
            if (wr_en && !full) begin
                fifo_q.push_back(wr_data);
            end
        end
    end

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            fifo_q.delete();
            underflow <= 1'b0;
        end else begin
            underflow <= rd_en && empty;
            if (rd_en && !empty) begin
                void'(fifo_q.pop_front());
            end
        end
    end
`endif

endmodule
