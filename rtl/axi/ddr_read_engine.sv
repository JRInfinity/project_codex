`timescale 1ns/1ps

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
    input  logic               axi_rst,
    input  logic               core_rst,

    input  logic               task_start,
    input  logic [ADDR_W-1:0]  task_addr,
    input  logic [31:0]        task_row_stride,
    input  logic [31:0]        task_byte_count,
    input  logic [15:0]        task_row_count,
    output logic               task_start_ready,

    output logic               task_busy,
    output logic               task_done,
    output logic               task_error,
    output logic [PIXEL_W-1:0] out_data,
    output logic               out_valid,
    output logic               out_row_last,
    input  logic               out_ready,

    taxi_axi_if.rd_mst         m_axi_rd
);

    localparam int TOTAL_COUNT_W = 48;

    logic               task_ready_core;
    logic               task_valid_axi;
    logic [ADDR_W-1:0]  task_addr_axi;
    logic [31:0]        task_row_stride_axi;
    logic [31:0]        task_row_byte_count_axi;
    logic [15:0]        task_row_count_axi;
    logic               task_ready_axi;

    logic               reader_task_valid_reg;
    logic [ADDR_W-1:0]  reader_task_addr_reg;
    logic [31:0]        reader_task_byte_count_reg;
    logic               reader_task_ready;
    logic               reader_result_valid;
    logic               reader_result_done;
    logic               reader_result_error;
    logic               reader_result_ready;

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
    logic               unpacker_done_level;
    logic               unpacker_error_level;
    logic               unpacker_error_flag;
    logic               task_active_reg;
    logic               task_start_accept;
    logic [TOTAL_COUNT_W-1:0] total_byte_count_calc;

    typedef enum logic [2:0] {
        R_IDLE,
        R_ISSUE,
        R_WAIT,
        R_DONE,
        R_ERROR
    } row_state_t;

    row_state_t        row_state_reg;
    logic [ADDR_W-1:0] row_base_addr_reg;
    logic [31:0]       row_stride_reg;
    logic [31:0]       row_byte_count_reg;
    logic [15:0]       row_count_reg;
    logic [15:0]       row_index_reg;
    logic [15:0]       row_rows_remaining_reg;
    logic              row_more_after_current_reg;
    logic              result_pending_reg;
    logic              result_done_reg;
    logic              result_error_reg;

    initial begin
        if (DATA_W % 8 != 0) $error("ddr_read_engine requires DATA_W to be byte aligned.");
        if (PIXEL_W != 8) $error("Current pixel_unpacker implementation expects PIXEL_W == 8.");
        if (FIFO_DEPTH_WORDS < 4) $error("FIFO_DEPTH_WORDS must be at least 4 words.");
    end

    assign total_byte_count_calc = TOTAL_COUNT_W'(task_byte_count) * TOTAL_COUNT_W'(task_row_count);
    assign task_start_accept = task_start && !task_active_reg && task_ready_core &&
                               (task_byte_count != 32'd0) && (task_row_count != 16'd0);
    assign task_start_ready  = !task_active_reg && task_ready_core;
    assign task_busy         = task_active_reg && !unpacker_done_level && !unpacker_error_level;
    assign task_done         = unpacker_done_pulse || unpacker_done_level;
    assign read_word_ready   = !fifo_full;

    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            task_active_reg <= 1'b0;
            task_error      <= 1'b0;
        end else begin
            if (task_start_accept) begin
                task_active_reg <= 1'b1;
                task_error      <= 1'b0;
            end else if (unpacker_done_pulse || unpacker_error_pulse ||
                         unpacker_done_level || unpacker_error_level) begin
                task_active_reg <= 1'b0;
            end

            if (result_error_evt_core || unpacker_error_flag) begin
                task_error <= 1'b1;
            end
        end
    end

    task_cdc_2d #(
        .ADDR_W(ADDR_W)
    ) u_task_cdc (
        .src_clk(core_clk),
        .src_rst(core_rst),
        .task_valid_src(task_start_accept),
        .task_base_addr_src(task_addr),
        .task_row_stride_src(task_row_stride),
        .task_row_byte_count_src(task_byte_count),
        .task_row_count_src(task_row_count),
        .task_ready_src(task_ready_core),
        .dst_clk(axi_clk),
        .dst_rst(axi_rst),
        .task_valid_dst(task_valid_axi),
        .task_base_addr_dst(task_addr_axi),
        .task_row_stride_dst(task_row_stride_axi),
        .task_row_byte_count_dst(task_row_byte_count_axi),
        .task_row_count_dst(task_row_count_axi),
        .task_ready_dst(task_ready_axi)
    );

    always_ff @(posedge axi_clk) begin
        if (axi_rst) begin
            row_state_reg              <= R_IDLE;
            row_base_addr_reg          <= '0;
            row_stride_reg             <= '0;
            row_byte_count_reg         <= '0;
            row_count_reg              <= '0;
            row_index_reg              <= '0;
            row_rows_remaining_reg     <= '0;
            row_more_after_current_reg <= 1'b0;
            reader_task_valid_reg      <= 1'b0;
            reader_task_addr_reg       <= '0;
            reader_task_byte_count_reg <= '0;
            result_pending_reg         <= 1'b0;
            result_done_reg            <= 1'b0;
            result_error_reg           <= 1'b0;
        end else begin
            if (result_pending_reg && result_ready_axi) begin
                result_pending_reg <= 1'b0;
                result_done_reg    <= 1'b0;
                result_error_reg   <= 1'b0;
                if ((row_state_reg == R_DONE) || (row_state_reg == R_ERROR)) begin
                    row_state_reg <= R_IDLE;
                end
            end

            if (reader_task_valid_reg && reader_task_ready) begin
                reader_task_valid_reg <= 1'b0;
                row_state_reg         <= R_WAIT;
            end

            if (reader_result_valid) begin
                if (!reader_result_error && reader_result_done) begin
                    reader_task_addr_reg       <= row_base_addr_reg + ((row_index_reg + 1'b1) * row_stride_reg);
                    reader_task_byte_count_reg <= row_byte_count_reg;
                    row_index_reg              <= row_index_reg + 1'b1;
                    row_rows_remaining_reg     <= row_rows_remaining_reg - 1'b1;
                end
                if (reader_result_error || !reader_result_done) begin
                    row_state_reg      <= R_ERROR;
                    result_pending_reg <= 1'b1;
                    result_done_reg    <= 1'b0;
                    result_error_reg   <= 1'b1;
                end else if (!row_more_after_current_reg) begin
                    row_state_reg      <= R_DONE;
                    result_pending_reg <= 1'b1;
                    result_done_reg    <= 1'b1;
                    result_error_reg   <= 1'b0;
                end else begin
                    reader_task_valid_reg      <= 1'b1;
                    row_more_after_current_reg <= (row_rows_remaining_reg > 16'd2);
                    row_state_reg              <= R_ISSUE;
                end
            end

            if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin
                row_base_addr_reg          <= task_addr_axi;
                row_stride_reg             <= task_row_stride_axi;
                row_byte_count_reg         <= task_row_byte_count_axi;
                row_count_reg              <= task_row_count_axi;
                row_index_reg              <= '0;
                row_rows_remaining_reg     <= task_row_count_axi;
                row_more_after_current_reg <= (task_row_count_axi > 16'd1);
                reader_task_addr_reg       <= task_addr_axi;
                reader_task_byte_count_reg <= task_row_byte_count_axi;
                reader_task_valid_reg      <= 1'b1;
                row_state_reg              <= R_ISSUE;
            end
        end
    end

    assign task_ready_axi      = (row_state_reg == R_IDLE) && !result_pending_reg;
    assign reader_result_ready = 1'b1;
    assign result_valid_axi    = result_pending_reg;
    assign result_done_axi     = result_done_reg;
    assign result_error_axi    = result_error_reg;

    result_cdc u_result_cdc (
        .src_clk(axi_clk),
        .src_rst(axi_rst),
        .result_valid_src(result_valid_axi),
        .result_done_src(result_done_axi),
        .result_error_src(result_error_axi),
        .result_ready_src(result_ready_axi),
        .dst_clk(core_clk),
        .dst_rst(core_rst),
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
        .wr_rst(axi_rst),
        .wr_en(read_word_valid),
        .wr_data(read_word_data),
        .full(fifo_full),
        .almost_full(fifo_almost_full),
        .wr_count(fifo_wr_count),
        .overflow(),
        .rd_clk(core_clk),
        .rd_rst(core_rst),
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
        .sys_rst(axi_rst),
        .task_valid(reader_task_valid_reg),
        .task_addr(reader_task_addr_reg),
        .task_byte_count(reader_task_byte_count_reg),
        .task_ready(reader_task_ready),
        .word_valid(read_word_valid),
        .word_data(read_word_data),
        .word_ready(read_word_ready),
        .word_almost_full(fifo_almost_full),
        .word_count(fifo_wr_count),
        .result_valid(reader_result_valid),
        .result_done(reader_result_done),
        .result_error(reader_result_error),
        .result_ready(reader_result_ready),
        .m_axi_rd(m_axi_rd)
    );

    pixel_unpacker #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PIXEL_W(PIXEL_W)
    ) u_pixel_unpacker (
        .core_clk(core_clk),
        .sys_rst(core_rst),
        .task_start(task_start_accept),
        .task_addr(task_addr),
        .task_byte_count(total_byte_count_calc[31:0]),
        .task_row_byte_count(task_byte_count),
        .reader_status_valid(result_valid_core),
        .reader_done_evt(result_done_evt_core),
        .reader_error_evt(result_error_evt_core),
        .fifo_rd_en(fifo_rd_en),
        .fifo_rd_data(fifo_rd_data),
        .fifo_empty(fifo_empty),
        .fifo_underflow(fifo_underflow),
        .pixel_data(out_data),
        .pixel_valid(out_valid),
        .pixel_row_last(out_row_last),
        .pixel_ready(out_ready),
        .task_done_level(unpacker_done_level),
        .task_error_level(unpacker_error_level),
        .task_done_pulse(unpacker_done_pulse),
        .task_error_pulse(unpacker_error_pulse),
        .task_error_flag(unpacker_error_flag)
    );

endmodule
