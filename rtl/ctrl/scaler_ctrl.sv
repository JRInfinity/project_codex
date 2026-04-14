`timescale 1ns/1ps

module scaler_ctrl #(
    parameter int ADDR_W    = 32,
    parameter int PIXEL_W   = 8,
    parameter int MAX_SRC_W = 7200,
    parameter int MAX_SRC_H = 7200,
    parameter int MAX_DST_W = 600,
    parameter int MAX_DST_H = 600,
    parameter int LINE_NUM  = 2
) (
    input  logic clk,
    input  logic sys_rst,

    input  logic              start,
    input  logic [ADDR_W-1:0] src_base_addr,
    input  logic [ADDR_W-1:0] dst_base_addr,
    input  logic [ADDR_W-1:0] src_stride,
    input  logic [ADDR_W-1:0] dst_stride,
    input  logic [$clog2(MAX_SRC_W+1)-1:0] src_w,
    input  logic [$clog2(MAX_SRC_H+1)-1:0] src_h,
    input  logic [$clog2(MAX_DST_W+1)-1:0] dst_w,
    input  logic [$clog2(MAX_DST_H+1)-1:0] dst_h,

    output logic busy,
    output logic done,
    output logic error,
    output logic                                             core_start,
    input  logic                                             core_busy,
    input  logic                                             core_done,
    input  logic                                             core_error,
    input  logic                                             row_done,

    output logic                           wb_start,
    output logic [$clog2(MAX_DST_W+1)-1:0] wb_pixel_count,
    input  logic                           wb_busy,
    input  logic                           wb_done_buf,
    input  logic                           wb_error,
    output logic                           wb_out_start,
    input  logic                           wb_out_done,

    output logic              write_start,
    output logic [ADDR_W-1:0] write_addr,
    output logic [31:0]       write_byte_count,
    input  logic              write_busy,
    input  logic              write_done,
    input  logic              write_error
);

    localparam int DST_Y_W    = $clog2(MAX_DST_H+1);

    typedef enum logic [1:0] {
        S_IDLE,
        S_RUN,
        S_DONE,
        S_ERROR
    } state_t;

    state_t state_reg;
    state_t state_next;

    logic [ADDR_W-1:0] dst_base_addr_reg;
    logic [ADDR_W-1:0] dst_stride_reg;
    logic [$clog2(MAX_DST_W+1)-1:0] dst_w_reg;
    logic [$clog2(MAX_DST_H+1)-1:0] dst_h_reg;

    logic [DST_Y_W-1:0] row_started_count_reg;
    logic [DST_Y_W-1:0] row_written_count_reg;
    logic [DST_Y_W-1:0] pending_row_write_count_reg;
    logic               pending_row_start_reg;
    logic               core_done_seen_reg;

    logic launch_first_row;
    logic launch_next_row;
    logic launch_write_row;
    logic launch_core;
    logic final_write_done;
    logic invalid_start;

    assign invalid_start = (src_w == 0) || (src_h == 0) || (dst_w == 0) || (dst_h == 0);

    always_comb begin
        state_next = state_reg;

        case (state_reg)
            S_IDLE: begin
                if (start) begin
                    if (invalid_start) begin
                        state_next = S_ERROR;
                    end else begin
                        state_next = S_RUN;
                    end
                end
            end

            S_RUN: begin
                if (core_error || wb_error || write_error) begin
                    state_next = S_ERROR;
                end else if (final_write_done) begin
                    state_next = S_DONE;
                end
            end

            S_DONE: begin
                state_next = S_IDLE;
            end

            S_ERROR: begin
                state_next = S_IDLE;
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    assign launch_first_row = (state_reg == S_RUN) &&
        (row_started_count_reg == 0) &&
        !wb_busy;

    assign launch_next_row = (state_reg == S_RUN) &&
        pending_row_start_reg &&
        (row_started_count_reg < dst_h_reg) &&
        !wb_busy;

    assign launch_write_row = (state_reg == S_RUN) &&
        (pending_row_write_count_reg != 0) &&
        !write_busy;

    assign launch_core = (state_reg == S_RUN) &&
        (row_started_count_reg == 0) &&
        !core_busy &&
        !core_done_seen_reg;

    assign final_write_done = (state_reg == S_RUN) &&
        write_done &&
        core_done_seen_reg &&
        (row_written_count_reg == dst_h_reg - 1'b1);

    assign busy  = (state_reg == S_RUN);
    assign done  = (state_reg == S_DONE);
    assign error = (state_reg == S_ERROR);

    assign core_start      = launch_core;
    assign wb_start        = launch_first_row || launch_next_row;
    assign wb_pixel_count  = dst_w_reg;
    assign wb_out_start    = launch_write_row;
    assign write_start      = launch_write_row;
    assign write_addr       = dst_base_addr_reg + row_written_count_reg * dst_stride_reg;
    assign write_byte_count = dst_w_reg;

    always_ff @(posedge clk) begin
        if (sys_rst) begin
            state_reg                    <= S_IDLE;
            dst_base_addr_reg            <= '0;
            dst_stride_reg               <= '0;
            dst_w_reg                    <= '0;
            dst_h_reg                    <= '0;
            row_started_count_reg        <= '0;
            row_written_count_reg        <= '0;
            pending_row_write_count_reg  <= '0;
            pending_row_start_reg        <= 1'b0;
            core_done_seen_reg           <= 1'b0;
        end else begin
            state_reg <= state_next;

            case (state_reg)
                S_IDLE: begin
                    row_started_count_reg       <= '0;
                    row_written_count_reg       <= '0;
                    pending_row_write_count_reg <= '0;
                    pending_row_start_reg       <= 1'b0;
                    core_done_seen_reg          <= 1'b0;

                    if (start) begin
                        dst_base_addr_reg <= dst_base_addr;
                        dst_stride_reg    <= dst_stride;
                        dst_w_reg         <= dst_w;
                        dst_h_reg         <= dst_h;
                    end
                end

                S_RUN: begin
                    if (launch_first_row) begin
                        row_started_count_reg <= row_started_count_reg + 1'b1;
                    end

                    if (launch_next_row) begin
                        row_started_count_reg <= row_started_count_reg + 1'b1;
                        pending_row_start_reg <= 1'b0;
                    end

                    if (row_done && (row_started_count_reg < dst_h_reg)) begin
                        pending_row_start_reg <= 1'b1;
                    end

                    case ({wb_done_buf, launch_write_row})
                        2'b10: pending_row_write_count_reg <= pending_row_write_count_reg + 1'b1;
                        2'b01: pending_row_write_count_reg <= pending_row_write_count_reg - 1'b1;
                        default: pending_row_write_count_reg <= pending_row_write_count_reg;
                    endcase

                    if (write_done) begin
                        row_written_count_reg <= row_written_count_reg + 1'b1;
                    end

                    if (core_done) begin
                        core_done_seen_reg <= 1'b1;
                    end
                end

                S_DONE: begin
                    // single-cycle pulse
                end

                S_ERROR: begin
                    // single-cycle pulse
                end

                default: begin
                    state_reg <= S_IDLE;
                end
            endcase
        end
    end

    logic unused_inputs;

    assign unused_inputs = &{1'b0, wb_out_done, src_base_addr[0], src_stride[0]};

endmodule
