`timescale 1ns/1ps

module src_row_cache #(
    parameter int PIXEL_W   = 8,
    parameter int ADDR_W    = 32,
    parameter int MAX_SRC_W = 7200,
    parameter int MAX_SRC_H = 7200,
    parameter int LINE_NUM  = 2
) (
    input  logic clk,
    input  logic sys_rst,

    input  logic                           start,
    input  logic [ADDR_W-1:0]              src_base_addr,
    input  logic [ADDR_W-1:0]              src_stride,
    input  logic [$clog2(MAX_SRC_W+1)-1:0] src_w,
    input  logic [$clog2(MAX_SRC_H+1)-1:0] src_h,
    output logic                           busy,
    output logic                           prefill_done,
    output logic                           error,

    output logic              read_start,
    output logic [ADDR_W-1:0] read_addr,
    output logic [31:0]       read_byte_count,
    input  logic              read_busy,
    input  logic              read_done,
    input  logic              read_error,

    input  logic [PIXEL_W-1:0] in_data,
    input  logic               in_valid,
    output logic               in_ready,

    input  logic                                                line_req_valid,
    input  logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0]  line_req_y,
    output logic                                                line_req_ready,
    output logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0]    line_req_sel0,
    output logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0]    line_req_sel1,

    input  logic                                               rd0_req_valid,
    input  logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0]   rd0_line_sel,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] rd0_x,
    output logic [PIXEL_W-1:0]                                 rd0_data,
    output logic                                               rd0_data_valid,

    input  logic                                               rd1_req_valid,
    input  logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0]   rd1_line_sel,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] rd1_x,
    output logic [PIXEL_W-1:0]                                 rd1_data,
    output logic                                               rd1_data_valid
);

    localparam int LINE_SEL_W = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;
    localparam int SRC_Y_W    = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;
    localparam int SRC_X_W    = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int COUNT_W    = $clog2(MAX_SRC_W+1);

    logic [PIXEL_W-1:0] mem_reg [0:LINE_NUM-1][0:MAX_SRC_W-1];

    logic                           active_reg;
    logic [ADDR_W-1:0]              src_base_addr_reg;
    logic [ADDR_W-1:0]              src_stride_reg;
    logic [$clog2(MAX_SRC_W+1)-1:0] src_w_reg;
    logic [$clog2(MAX_SRC_H+1)-1:0] src_h_reg;
    logic [SRC_Y_W-1:0]             next_prefetch_y_reg;
    logic                           prefill_done_reg;
    logic [SRC_Y_W-1:0]             prefill_target_reg;
    logic [LINE_NUM-1:0]            slot_occupied_reg;
    logic [LINE_NUM-1:0]            slot_ready_reg;
    logic [SRC_Y_W-1:0]             slot_y_reg [0:LINE_NUM-1];

    logic                           fill_active_reg;
    logic [LINE_SEL_W-1:0]          fill_sel_reg;
    logic [SRC_Y_W-1:0]             fill_y_reg;
    logic [COUNT_W-1:0]             fill_pixel_count_reg;
    logic [COUNT_W-1:0]             wr_ptr_reg;
    logic                           fill_fire;
    logic                           fill_done_fire;

    logic                           have_free_slot;
    logic [LINE_SEL_W-1:0]          free_slot_sel;
    logic                           launch_read;
    logic [SRC_Y_W-1:0]             line_req_y1;
    logic                           line_hit0;
    logic                           line_hit1;
    logic [LINE_SEL_W-1:0]          line_hit_sel0;
    logic [LINE_SEL_W-1:0]          line_hit_sel1;
    logic [PIXEL_W-1:0]             rd0_data_reg;
    logic [PIXEL_W-1:0]             rd1_data_reg;
    logic                           rd0_data_valid_reg;
    logic                           rd1_data_valid_reg;

    initial begin
        if (LINE_NUM < 2) $error("src_row_cache currently expects LINE_NUM >= 2.");
    end

    always_comb begin
        have_free_slot = 1'b0;
        free_slot_sel  = '0;
        line_hit0      = 1'b0;
        line_hit1      = 1'b0;
        line_hit_sel0  = '0;
        line_hit_sel1  = '0;

        for (int slot_idx_comb = 0; slot_idx_comb < LINE_NUM; slot_idx_comb++) begin
            if (!have_free_slot && !slot_occupied_reg[slot_idx_comb]) begin
                have_free_slot = 1'b1;
                free_slot_sel  = LINE_SEL_W'(slot_idx_comb);
            end

            if (!line_hit0 && slot_ready_reg[slot_idx_comb] && (slot_y_reg[slot_idx_comb] == line_req_y)) begin
                line_hit0     = 1'b1;
                line_hit_sel0 = LINE_SEL_W'(slot_idx_comb);
            end

            if (!line_hit1 && slot_ready_reg[slot_idx_comb] && (slot_y_reg[slot_idx_comb] == line_req_y1)) begin
                line_hit1     = 1'b1;
                line_hit_sel1 = LINE_SEL_W'(slot_idx_comb);
            end
        end
    end

    assign line_req_y1 = (line_req_y + 1'b1 >= src_h_reg) ? (src_h_reg - 1'b1) : (line_req_y + 1'b1);
    assign launch_read = active_reg &&
        !error &&
        !fill_active_reg &&
        !read_busy &&
        have_free_slot &&
        (next_prefetch_y_reg < src_h_reg);

    assign busy            = active_reg && ((next_prefetch_y_reg < src_h_reg) || fill_active_reg || read_busy);
    assign prefill_done    = prefill_done_reg;
    assign read_start      = launch_read;
    assign read_addr       = src_base_addr_reg + next_prefetch_y_reg * src_stride_reg;
    assign read_byte_count = src_w_reg;
    assign in_ready        = fill_active_reg && (wr_ptr_reg < fill_pixel_count_reg) && !error;
    assign fill_fire       = in_valid && in_ready;
    assign fill_done_fire  = fill_fire && (wr_ptr_reg == fill_pixel_count_reg - 1'b1);
    assign line_req_ready  = active_reg && prefill_done_reg && line_hit0 && line_hit1;
    assign line_req_sel0   = line_hit_sel0;
    assign line_req_sel1   = line_hit_sel1;
    assign rd0_data        = rd0_data_reg;
    assign rd0_data_valid  = rd0_data_valid_reg;
    assign rd1_data        = rd1_data_reg;
    assign rd1_data_valid  = rd1_data_valid_reg;

    always_ff @(posedge clk) begin
        if (sys_rst) begin
            active_reg           <= 1'b0;
            src_base_addr_reg    <= '0;
            src_stride_reg       <= '0;
            src_w_reg            <= '0;
            src_h_reg            <= '0;
            next_prefetch_y_reg  <= '0;
            prefill_done_reg     <= 1'b0;
            prefill_target_reg   <= '0;
            slot_occupied_reg    <= '0;
            slot_ready_reg       <= '0;
            fill_active_reg      <= 1'b0;
            fill_sel_reg         <= '0;
            fill_y_reg           <= '0;
            fill_pixel_count_reg <= '0;
            wr_ptr_reg           <= '0;
            error                <= 1'b0;
            rd0_data_reg         <= '0;
            rd1_data_reg         <= '0;
            rd0_data_valid_reg   <= 1'b0;
            rd1_data_valid_reg   <= 1'b0;

            for (int slot_idx_ff = 0; slot_idx_ff < LINE_NUM; slot_idx_ff++) begin
                slot_y_reg[slot_idx_ff] <= '0;
            end
        end else begin
            rd0_data_valid_reg <= 1'b0;
            rd1_data_valid_reg <= 1'b0;

            if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin
                rd0_data_reg       <= mem_reg[rd0_line_sel][rd0_x];
                rd0_data_valid_reg <= 1'b1;
            end

            if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin
                rd1_data_reg       <= mem_reg[rd1_line_sel][rd1_x];
                rd1_data_valid_reg <= 1'b1;
            end

            if (start) begin
                active_reg          <= 1'b1;
                src_base_addr_reg   <= src_base_addr;
                src_stride_reg      <= src_stride;
                src_w_reg           <= src_w;
                src_h_reg           <= src_h;
                next_prefetch_y_reg <= '0;
                prefill_done_reg    <= 1'b0;
                prefill_target_reg  <= (src_h < LINE_NUM) ? src_h[SRC_Y_W-1:0] : SRC_Y_W'(LINE_NUM);
                slot_occupied_reg   <= '0;
                slot_ready_reg      <= '0;
                fill_active_reg     <= 1'b0;
                fill_sel_reg        <= '0;
                fill_y_reg          <= '0;
                fill_pixel_count_reg <= '0;
                wr_ptr_reg          <= '0;
                error               <= 1'b0;

                for (int slot_idx_start = 0; slot_idx_start < LINE_NUM; slot_idx_start++) begin
                    slot_y_reg[slot_idx_start] <= '0;
                end
            end else if (active_reg) begin
                if ((src_w_reg == 0) || (src_h_reg == 0)) begin
                    error      <= 1'b1;
                    active_reg <= 1'b0;
                end

                if (read_error) begin
                    error                         <= 1'b1;
                    active_reg                    <= 1'b0;
                    fill_active_reg               <= 1'b0;
                    slot_occupied_reg[fill_sel_reg] <= 1'b0;
                    slot_ready_reg[fill_sel_reg]  <= 1'b0;
                end

                if (line_req_valid) begin
                    for (int slot_idx_rel = 0; slot_idx_rel < LINE_NUM; slot_idx_rel++) begin
                        if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin
                            slot_ready_reg[slot_idx_rel]    <= 1'b0;
                            slot_occupied_reg[slot_idx_rel] <= 1'b0;
                        end
                    end
                end

                if (launch_read) begin
                    fill_active_reg                    <= 1'b1;
                    fill_sel_reg                       <= free_slot_sel;
                    fill_y_reg                         <= next_prefetch_y_reg;
                    fill_pixel_count_reg               <= src_w_reg;
                    wr_ptr_reg                         <= '0;
                    slot_occupied_reg[free_slot_sel]   <= 1'b1;
                    slot_ready_reg[free_slot_sel]      <= 1'b0;
                    slot_y_reg[free_slot_sel]          <= next_prefetch_y_reg;
                    next_prefetch_y_reg                <= next_prefetch_y_reg + 1'b1;
                end

                if (fill_active_reg && fill_fire) begin
                    mem_reg[fill_sel_reg][wr_ptr_reg[SRC_X_W-1:0]] <= in_data;
                    wr_ptr_reg <= wr_ptr_reg + 1'b1;

                    if (fill_done_fire) begin
                        fill_active_reg              <= 1'b0;
                        slot_ready_reg[fill_sel_reg] <= 1'b1;

                        if ((fill_y_reg + 1'b1) >= prefill_target_reg) begin
                            prefill_done_reg <= 1'b1;
                        end
                    end
                end

                if (read_done && fill_active_reg && (wr_ptr_reg != fill_pixel_count_reg)) begin
                    error      <= 1'b1;
                    active_reg <= 1'b0;
                end
            end
        end
    end

endmodule
