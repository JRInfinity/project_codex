`timescale 1ns/1ps

module src_tile_cache #(
    parameter int PIXEL_W   = 8,
    parameter int ADDR_W    = 32,
    parameter int MAX_SRC_W = 7200,
    parameter int MAX_SRC_H = 7200,
    parameter int TILE_W    = 16,
    parameter int TILE_H    = 16,
    parameter int TILE_NUM  = 4
) (
    input  logic clk,
    input  logic sys_rst,

    input  logic                           start,
    input  logic [ADDR_W-1:0]              src_base_addr,
    input  logic [ADDR_W-1:0]              src_stride,
    input  logic [$clog2(MAX_SRC_W+1)-1:0] src_w,
    input  logic [$clog2(MAX_SRC_H+1)-1:0] src_h,
    input  logic                           prefetch_enable,
    input  logic signed [1:0]             scan_dir_x,
    input  logic signed [1:0]             scan_dir_y,
    input  logic                           scan_dir_valid,
    output logic                           busy,
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

    input  logic                                              sample_req_valid,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x0,
    input  logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y0,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x1,
    input  logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y1,
    output logic                                              sample_req_ready,
    output logic [PIXEL_W-1:0]                                sample_p00,
    output logic [PIXEL_W-1:0]                                sample_p01,
    output logic [PIXEL_W-1:0]                                sample_p10,
    output logic [PIXEL_W-1:0]                                sample_p11,
    output logic                                              sample_rsp_valid,
    output logic [31:0]                                       stat_read_starts,
    output logic [31:0]                                       stat_misses,
    output logic [31:0]                                       stat_prefetch_starts,
    output logic [31:0]                                       stat_prefetch_hits
);

    localparam int SRC_X_W   = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int SRC_Y_W   = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;
    localparam int TILE_X_W  = ((MAX_SRC_W + TILE_W - 1) / TILE_W > 1) ? $clog2((MAX_SRC_W + TILE_W - 1) / TILE_W) : 1;
    localparam int TILE_Y_W  = ((MAX_SRC_H + TILE_H - 1) / TILE_H > 1) ? $clog2((MAX_SRC_H + TILE_H - 1) / TILE_H) : 1;
    localparam int SLOT_W    = (TILE_NUM > 1) ? $clog2(TILE_NUM) : 1;
    localparam int TILE_ROW_W = (TILE_W > 1) ? $clog2(TILE_W) : 1;
    localparam int TILE_COL_W = (TILE_H > 1) ? $clog2(TILE_H) : 1;

    logic [PIXEL_W-1:0] mem_reg [0:TILE_NUM-1][0:TILE_H-1][0:TILE_W-1];

    logic [TILE_NUM-1:0]            slot_valid_reg;
    logic [TILE_NUM-1:0]            slot_prefetched_reg;
    logic [TILE_X_W-1:0]            slot_tile_x_reg [0:TILE_NUM-1];
    logic [TILE_Y_W-1:0]            slot_tile_y_reg [0:TILE_NUM-1];
    logic [SLOT_W-1:0]              replace_ptr_reg;
    logic [ADDR_W-1:0]              cfg_src_base_addr_reg;
    logic [ADDR_W-1:0]              cfg_src_stride_reg;
    logic [$clog2(MAX_SRC_W+1)-1:0] cfg_src_w_reg;
    logic [$clog2(MAX_SRC_H+1)-1:0] cfg_src_h_reg;
    logic                           cfg_prefetch_enable_reg;
    logic                           cfg_geom_init_pending_reg;
    logic [TILE_X_W-1:0]            cfg_tile_count_x_reg;
    logic [TILE_Y_W-1:0]            cfg_tile_count_y_reg;
    logic [$clog2(TILE_W+1)-1:0]    cfg_last_tile_width_reg;
    logic [$clog2(TILE_H+1)-1:0]    cfg_last_tile_height_reg;

    logic                           fill_active_reg;
    logic [SLOT_W-1:0]              fill_slot_reg;
    logic [TILE_X_W-1:0]            fill_tile_x_reg;
    logic [TILE_Y_W-1:0]            fill_tile_y_reg;
    logic [TILE_COL_W-1:0]          fill_row_idx_reg;
    logic [TILE_ROW_W-1:0]          fill_col_idx_reg;
    logic [$clog2(TILE_W+1)-1:0]    fill_row_width_reg;
    logic [$clog2(TILE_H+1)-1:0]    fill_tile_height_reg;
    logic                           fill_is_prefetch_reg;
    logic                           fill_plan_valid_reg;
    logic [SLOT_W-1:0]              fill_plan_slot_reg;
    logic [TILE_X_W-1:0]            fill_plan_tile_x_reg;
    logic [TILE_Y_W-1:0]            fill_plan_tile_y_reg;
    logic [$clog2(TILE_W+1)-1:0]    fill_plan_row_width_reg;
    logic [$clog2(TILE_H+1)-1:0]    fill_plan_tile_height_reg;
    logic                           fill_plan_is_prefetch_reg;
    logic                           row_inflight_reg;
    logic                           read_start_reg;
    logic [ADDR_W-1:0]              read_addr_reg;
    logic [31:0]                    read_byte_count_reg;
    logic                           last_req_valid_reg;
    logic [TILE_X_W-1:0]            last_req_tile_x_reg;
    logic [TILE_Y_W-1:0]            last_req_tile_y_reg;
    logic                           prefetch_pending_reg;
    logic [TILE_X_W-1:0]            prefetch_pending_tile_x_reg;
    logic [TILE_Y_W-1:0]            prefetch_pending_tile_y_reg;

    logic [TILE_X_W-1:0] req_tile_x00;
    logic [TILE_X_W-1:0] req_tile_x01;
    logic [TILE_Y_W-1:0] req_tile_y00;
    logic [TILE_Y_W-1:0] req_tile_y10;
    logic [TILE_X_W-1:0] hold_req_tile_x00;
    logic [TILE_X_W-1:0] hold_req_tile_x01;
    logic [TILE_Y_W-1:0] hold_req_tile_y00;
    logic [TILE_Y_W-1:0] hold_req_tile_y10;
    logic [SLOT_W-1:0] hit_slot00;
    logic [SLOT_W-1:0] hit_slot01;
    logic [SLOT_W-1:0] hit_slot10;
    logic [SLOT_W-1:0] hit_slot11;
    logic [SLOT_W-1:0] hold_hit_slot00;
    logic [SLOT_W-1:0] hold_hit_slot01;
    logic [SLOT_W-1:0] hold_hit_slot10;
    logic [SLOT_W-1:0] hold_hit_slot11;
    logic hit00;
    logic hit01;
    logic hit10;
    logic hit11;
    logic hold_hit00;
    logic hold_hit01;
    logic hold_hit10;
    logic hold_hit11;
    logic have_invalid_slot;
    logic [SLOT_W-1:0] invalid_slot_sel;
    logic miss_present;
    logic [TILE_X_W-1:0] miss_tile_x;
    logic [TILE_Y_W-1:0] miss_tile_y;
    logic [SLOT_W-1:0]   alloc_slot_sel;
    logic                have_reusable_slot;
    logic [SLOT_W-1:0]   reusable_slot_sel;
    logic                prefetch_present;
    logic [TILE_X_W-1:0] prefetch_tile_x;
    logic [TILE_Y_W-1:0] prefetch_tile_y;
    logic [SLOT_W-1:0]   prefetch_hit_slot_unused;
    logic                fill_request_present;
    logic                fill_request_is_prefetch;
    logic [TILE_X_W-1:0] fill_request_tile_x;
    logic [TILE_Y_W-1:0] fill_request_tile_y;
    logic [SLOT_W-1:0]   fill_request_slot_sel;
    logic [31:0]         stat_read_starts_reg;
    logic [31:0]         stat_misses_reg;
    logic [31:0]         stat_prefetch_starts_reg;
    logic [31:0]         stat_prefetch_hits_reg;
    logic                prefetched_hit_now;
    logic                sample_issue_valid_reg;
    logic [SLOT_W-1:0]   sample_hit_slot00_reg;
    logic [SLOT_W-1:0]   sample_hit_slot01_reg;
    logic [SLOT_W-1:0]   sample_hit_slot10_reg;
    logic [SLOT_W-1:0]   sample_hit_slot11_reg;
    logic [TILE_ROW_W-1:0] sample_col0_reg;
    logic [TILE_ROW_W-1:0] sample_col1_reg;
    logic [TILE_COL_W-1:0] sample_row0_reg;
    logic [TILE_COL_W-1:0] sample_row1_reg;
    logic                  sample_prefetched_hit_reg;
    logic                  sample_decode_valid_reg;
    logic [SRC_X_W-1:0]    sample_hold_x0_reg;
    logic [SRC_X_W-1:0]    sample_hold_x1_reg;
    logic [SRC_Y_W-1:0]    sample_hold_y0_reg;
    logic [SRC_Y_W-1:0]    sample_hold_y1_reg;
    logic                  hold_prefetched_hit_now;

    function automatic logic hit_tile(
        input logic [TILE_X_W-1:0] tile_x,
        input logic [TILE_Y_W-1:0] tile_y,
        output logic [SLOT_W-1:0] slot_sel
    );
        logic found;
        begin
            found    = 1'b0;
            slot_sel = '0;
            for (int slot_idx = 0; slot_idx < TILE_NUM; slot_idx++) begin
                if (!found && slot_valid_reg[slot_idx] &&
                    (slot_tile_x_reg[slot_idx] == tile_x) &&
                    (slot_tile_y_reg[slot_idx] == tile_y)) begin
                    found    = 1'b1;
                    slot_sel = SLOT_W'(slot_idx);
                end
            end
            hit_tile = found;
        end
    endfunction

    always_comb begin
        req_tile_x00 = sample_x0 / TILE_W;
        req_tile_x01 = sample_x1 / TILE_W;
        req_tile_y00 = sample_y0 / TILE_H;
        req_tile_y10 = sample_y1 / TILE_H;

        hit00 = hit_tile(req_tile_x00, req_tile_y00, hit_slot00);
        hit01 = hit_tile(req_tile_x01, req_tile_y00, hit_slot01);
        hit10 = hit_tile(req_tile_x00, req_tile_y10, hit_slot10);
        hit11 = hit_tile(req_tile_x01, req_tile_y10, hit_slot11);
        hold_req_tile_x00 = sample_hold_x0_reg / TILE_W;
        hold_req_tile_x01 = sample_hold_x1_reg / TILE_W;
        hold_req_tile_y00 = sample_hold_y0_reg / TILE_H;
        hold_req_tile_y10 = sample_hold_y1_reg / TILE_H;
        hold_hit00 = hit_tile(hold_req_tile_x00, hold_req_tile_y00, hold_hit_slot00);
        hold_hit01 = hit_tile(hold_req_tile_x01, hold_req_tile_y00, hold_hit_slot01);
        hold_hit10 = hit_tile(hold_req_tile_x00, hold_req_tile_y10, hold_hit_slot10);
        hold_hit11 = hit_tile(hold_req_tile_x01, hold_req_tile_y10, hold_hit_slot11);

        have_invalid_slot = 1'b0;
        invalid_slot_sel  = '0;
        for (int slot_idx_comb = 0; slot_idx_comb < TILE_NUM; slot_idx_comb++) begin
            if (!have_invalid_slot && !slot_valid_reg[slot_idx_comb] &&
                !(fill_active_reg && (fill_slot_reg == SLOT_W'(slot_idx_comb)))) begin
                have_invalid_slot = 1'b1;
                invalid_slot_sel  = SLOT_W'(slot_idx_comb);
            end
        end

        miss_present = 1'b0;
        miss_tile_x  = '0;
        miss_tile_y  = '0;

        if (sample_req_valid) begin
            if (!hit00) begin
                miss_present = 1'b1;
                miss_tile_x  = req_tile_x00;
                miss_tile_y  = req_tile_y00;
            end else if (!hit01) begin
                miss_present = 1'b1;
                miss_tile_x  = req_tile_x01;
                miss_tile_y  = req_tile_y00;
            end else if (!hit10) begin
                miss_present = 1'b1;
                miss_tile_x  = req_tile_x00;
                miss_tile_y  = req_tile_y10;
            end else if (!hit11) begin
                miss_present = 1'b1;
                miss_tile_x  = req_tile_x01;
                miss_tile_y  = req_tile_y10;
            end
        end

        have_reusable_slot = 1'b0;
        reusable_slot_sel  = replace_ptr_reg;
        for (int slot_search = 0; slot_search < TILE_NUM; slot_search++) begin
            int candidate_idx;
            logic protected_slot;
            candidate_idx = (replace_ptr_reg + slot_search) % TILE_NUM;
            protected_slot = (hit00 && (hit_slot00 == SLOT_W'(candidate_idx))) ||
                             (hit01 && (hit_slot01 == SLOT_W'(candidate_idx))) ||
                             (hit10 && (hit_slot10 == SLOT_W'(candidate_idx))) ||
                             (hit11 && (hit_slot11 == SLOT_W'(candidate_idx)));
            if (!have_reusable_slot && !protected_slot) begin
                have_reusable_slot = 1'b1;
                reusable_slot_sel  = SLOT_W'(candidate_idx);
            end
        end

        alloc_slot_sel   = have_invalid_slot ? invalid_slot_sel :
                           (have_reusable_slot ? reusable_slot_sel : replace_ptr_reg);

        prefetch_present = prefetch_pending_reg;
        prefetch_tile_x  = prefetch_pending_tile_x_reg;
        prefetch_tile_y  = prefetch_pending_tile_y_reg;

        if (prefetch_present && hit_tile(prefetch_tile_x, prefetch_tile_y, prefetch_hit_slot_unused)) begin
            prefetch_present = 1'b0;
        end

        fill_request_present     = 1'b0;
        fill_request_is_prefetch = 1'b0;
        fill_request_tile_x      = '0;
        fill_request_tile_y      = '0;
        fill_request_slot_sel    = alloc_slot_sel;
        prefetched_hit_now       = 1'b0;

        if (miss_present) begin
            fill_request_present  = 1'b1;
            fill_request_tile_x   = miss_tile_x;
            fill_request_tile_y   = miss_tile_y;
            fill_request_slot_sel = alloc_slot_sel;
        end else if (prefetch_present && (have_invalid_slot || have_reusable_slot)) begin
            fill_request_present     = 1'b1;
            fill_request_is_prefetch = 1'b1;
            fill_request_tile_x      = prefetch_tile_x;
            fill_request_tile_y      = prefetch_tile_y;
            fill_request_slot_sel    = have_invalid_slot ? invalid_slot_sel : reusable_slot_sel;
        end

        sample_req_ready = sample_req_valid && !sample_decode_valid_reg && !sample_issue_valid_reg &&
                           hit00 && hit01 && hit10 && hit11;
        if (sample_req_ready) begin
            prefetched_hit_now = slot_prefetched_reg[hit_slot00] ||
                                 slot_prefetched_reg[hit_slot01] ||
                                 slot_prefetched_reg[hit_slot10] ||
                                 slot_prefetched_reg[hit_slot11];
        end

        hold_prefetched_hit_now = slot_prefetched_reg[hold_hit_slot00] ||
                                  slot_prefetched_reg[hold_hit_slot01] ||
                                  slot_prefetched_reg[hold_hit_slot10] ||
                                  slot_prefetched_reg[hold_hit_slot11];
    end

    assign busy            = cfg_geom_init_pending_reg || fill_active_reg || row_inflight_reg || read_busy;
    assign read_start      = read_start_reg;
    assign read_addr       = read_addr_reg;
    assign read_byte_count = read_byte_count_reg;
    assign in_ready        = fill_active_reg && row_inflight_reg && (fill_col_idx_reg < fill_row_width_reg) && !error;
    assign stat_read_starts = stat_read_starts_reg;
    assign stat_misses = stat_misses_reg;
    assign stat_prefetch_starts = stat_prefetch_starts_reg;
    assign stat_prefetch_hits = stat_prefetch_hits_reg;

    always_ff @(posedge clk) begin
        if (sys_rst) begin
            slot_valid_reg     <= '0;
            slot_prefetched_reg <= '0;
            replace_ptr_reg    <= '0;
            cfg_src_base_addr_reg <= '0;
            cfg_src_stride_reg <= '0;
            cfg_src_w_reg <= '0;
            cfg_src_h_reg <= '0;
            cfg_prefetch_enable_reg <= 1'b0;
            cfg_geom_init_pending_reg <= 1'b0;
            cfg_tile_count_x_reg <= '0;
            cfg_tile_count_y_reg <= '0;
            cfg_last_tile_width_reg <= '0;
            cfg_last_tile_height_reg <= '0;
            fill_active_reg    <= 1'b0;
            fill_slot_reg      <= '0;
            fill_tile_x_reg    <= '0;
            fill_tile_y_reg    <= '0;
            fill_row_idx_reg   <= '0;
            fill_col_idx_reg   <= '0;
            fill_row_width_reg <= '0;
            fill_tile_height_reg <= '0;
            fill_is_prefetch_reg <= 1'b0;
            fill_plan_valid_reg <= 1'b0;
            fill_plan_slot_reg <= '0;
            fill_plan_tile_x_reg <= '0;
            fill_plan_tile_y_reg <= '0;
            fill_plan_row_width_reg <= '0;
            fill_plan_tile_height_reg <= '0;
            fill_plan_is_prefetch_reg <= 1'b0;
            row_inflight_reg   <= 1'b0;
            read_start_reg     <= 1'b0;
            read_addr_reg      <= '0;
            read_byte_count_reg <= '0;
            last_req_valid_reg <= 1'b0;
            last_req_tile_x_reg <= '0;
            last_req_tile_y_reg <= '0;
            prefetch_pending_reg <= 1'b0;
            prefetch_pending_tile_x_reg <= '0;
            prefetch_pending_tile_y_reg <= '0;
            stat_read_starts_reg <= '0;
            stat_misses_reg <= '0;
            stat_prefetch_starts_reg <= '0;
            stat_prefetch_hits_reg <= '0;
            sample_issue_valid_reg <= 1'b0;
            sample_decode_valid_reg <= 1'b0;
            sample_hit_slot00_reg <= '0;
            sample_hit_slot01_reg <= '0;
            sample_hit_slot10_reg <= '0;
            sample_hit_slot11_reg <= '0;
            sample_col0_reg <= '0;
            sample_col1_reg <= '0;
            sample_row0_reg <= '0;
            sample_row1_reg <= '0;
            sample_hold_x0_reg <= '0;
            sample_hold_x1_reg <= '0;
            sample_hold_y0_reg <= '0;
            sample_hold_y1_reg <= '0;
            sample_prefetched_hit_reg <= 1'b0;
            error              <= 1'b0;
            sample_p00         <= '0;
            sample_p01         <= '0;
            sample_p10         <= '0;
            sample_p11         <= '0;
            sample_rsp_valid   <= 1'b0;
            for (int slot_idx_ff = 0; slot_idx_ff < TILE_NUM; slot_idx_ff++) begin
                slot_tile_x_reg[slot_idx_ff] <= '0;
                slot_tile_y_reg[slot_idx_ff] <= '0;
            end
        end else begin
            read_start_reg   <= 1'b0;
            sample_rsp_valid <= 1'b0;

            if (start) begin
                slot_valid_reg   <= '0;
                slot_prefetched_reg <= '0;
                replace_ptr_reg  <= '0;
                cfg_src_base_addr_reg <= src_base_addr;
                cfg_src_stride_reg <= src_stride;
                cfg_src_w_reg <= src_w;
                cfg_src_h_reg <= src_h;
                cfg_prefetch_enable_reg <= prefetch_enable;
                cfg_geom_init_pending_reg <= 1'b1;
                fill_active_reg  <= 1'b0;
                fill_is_prefetch_reg <= 1'b0;
                fill_plan_valid_reg <= 1'b0;
                row_inflight_reg <= 1'b0;
                last_req_valid_reg <= 1'b0;
                prefetch_pending_reg <= 1'b0;
                stat_read_starts_reg <= '0;
                stat_misses_reg <= '0;
                stat_prefetch_starts_reg <= '0;
                stat_prefetch_hits_reg <= '0;
                sample_issue_valid_reg <= 1'b0;
                sample_decode_valid_reg <= 1'b0;
                error            <= 1'b0;
            end

            if (cfg_geom_init_pending_reg) begin
                cfg_tile_count_x_reg <= (cfg_src_w_reg + TILE_W - 1) / TILE_W;
                cfg_tile_count_y_reg <= (cfg_src_h_reg + TILE_H - 1) / TILE_H;
                cfg_last_tile_width_reg <= ((cfg_src_w_reg % TILE_W) == 0) ? TILE_W : (cfg_src_w_reg % TILE_W);
                cfg_last_tile_height_reg <= ((cfg_src_h_reg % TILE_H) == 0) ? TILE_H : (cfg_src_h_reg % TILE_H);
                cfg_geom_init_pending_reg <= 1'b0;
            end

            if (!cfg_geom_init_pending_reg && sample_req_valid && sample_req_ready) begin
                sample_decode_valid_reg <= 1'b1;
                sample_hold_x0_reg      <= sample_x0;
                sample_hold_x1_reg      <= sample_x1;
                sample_hold_y0_reg      <= sample_y0;
                sample_hold_y1_reg      <= sample_y1;

                if (cfg_prefetch_enable_reg && scan_dir_valid) begin
                    if (scan_dir_x > 0) begin
                        if ((req_tile_x01 + 1'b1) < cfg_tile_count_x_reg) begin
                            prefetch_pending_reg        <= 1'b1;
                            prefetch_pending_tile_x_reg <= req_tile_x01 + 1'b1;
                            prefetch_pending_tile_y_reg <= req_tile_y00;
                        end else begin
                            prefetch_pending_reg <= 1'b0;
                        end
                    end else if (scan_dir_x < 0) begin
                        if (req_tile_x00 != 0) begin
                            prefetch_pending_reg        <= 1'b1;
                            prefetch_pending_tile_x_reg <= req_tile_x00 - 1'b1;
                            prefetch_pending_tile_y_reg <= req_tile_y00;
                        end else begin
                            prefetch_pending_reg <= 1'b0;
                        end
                    end else if (scan_dir_y > 0) begin
                        if ((req_tile_y10 + 1'b1) < cfg_tile_count_y_reg) begin
                            prefetch_pending_reg        <= 1'b1;
                            prefetch_pending_tile_x_reg <= req_tile_x00;
                            prefetch_pending_tile_y_reg <= req_tile_y10 + 1'b1;
                        end else begin
                            prefetch_pending_reg <= 1'b0;
                        end
                    end else if (scan_dir_y < 0) begin
                        if (req_tile_y00 != 0) begin
                            prefetch_pending_reg        <= 1'b1;
                            prefetch_pending_tile_x_reg <= req_tile_x00;
                            prefetch_pending_tile_y_reg <= req_tile_y00 - 1'b1;
                        end else begin
                            prefetch_pending_reg <= 1'b0;
                        end
                    end else begin
                        prefetch_pending_reg <= 1'b0;
                    end
                end else begin
                    prefetch_pending_reg <= 1'b0;
                end

                slot_prefetched_reg[hit_slot00] <= 1'b0;
                slot_prefetched_reg[hit_slot01] <= 1'b0;
                slot_prefetched_reg[hit_slot10] <= 1'b0;
                slot_prefetched_reg[hit_slot11] <= 1'b0;

                last_req_valid_reg  <= 1'b1;
                last_req_tile_x_reg <= req_tile_x00;
                last_req_tile_y_reg <= req_tile_y00;
            end

            if (sample_decode_valid_reg) begin
                sample_issue_valid_reg <= 1'b1;
                sample_hit_slot00_reg  <= hold_hit_slot00;
                sample_hit_slot01_reg  <= hold_hit_slot01;
                sample_hit_slot10_reg  <= hold_hit_slot10;
                sample_hit_slot11_reg  <= hold_hit_slot11;
                sample_col0_reg        <= sample_hold_x0_reg % TILE_W;
                sample_col1_reg        <= sample_hold_x1_reg % TILE_W;
                sample_row0_reg        <= sample_hold_y0_reg % TILE_H;
                sample_row1_reg        <= sample_hold_y1_reg % TILE_H;
                sample_prefetched_hit_reg <= hold_prefetched_hit_now;
                sample_decode_valid_reg <= 1'b0;
            end

            if (sample_issue_valid_reg) begin
                sample_p00         <= mem_reg[sample_hit_slot00_reg][sample_row0_reg][sample_col0_reg];
                sample_p01         <= mem_reg[sample_hit_slot01_reg][sample_row0_reg][sample_col1_reg];
                sample_p10         <= mem_reg[sample_hit_slot10_reg][sample_row1_reg][sample_col0_reg];
                sample_p11         <= mem_reg[sample_hit_slot11_reg][sample_row1_reg][sample_col1_reg];
                sample_rsp_valid   <= 1'b1;
                if (sample_prefetched_hit_reg) begin
                    stat_prefetch_hits_reg <= stat_prefetch_hits_reg + 1'b1;
                end
                sample_issue_valid_reg <= 1'b0;
            end

            if (read_error) begin
                error            <= 1'b1;
                fill_active_reg  <= 1'b0;
                fill_plan_valid_reg <= 1'b0;
                row_inflight_reg <= 1'b0;
                slot_valid_reg[fill_slot_reg] <= 1'b0;
            end

            if (!cfg_geom_init_pending_reg && !sample_decode_valid_reg && !sample_issue_valid_reg &&
                !fill_active_reg && !fill_plan_valid_reg && fill_request_present && !error) begin
                fill_plan_valid_reg <= 1'b1;
                fill_plan_slot_reg <= fill_request_slot_sel;
                fill_plan_tile_x_reg <= fill_request_tile_x;
                fill_plan_tile_y_reg <= fill_request_tile_y;
                fill_plan_row_width_reg <=
                    (fill_request_tile_x == (cfg_tile_count_x_reg - 1'b1)) ? cfg_last_tile_width_reg : TILE_W;
                fill_plan_tile_height_reg <=
                    (fill_request_tile_y == (cfg_tile_count_y_reg - 1'b1)) ? cfg_last_tile_height_reg : TILE_H;
                fill_plan_is_prefetch_reg <= fill_request_is_prefetch;
                if (miss_present) begin
                    stat_misses_reg <= stat_misses_reg + 1'b1;
                end
                if (fill_request_is_prefetch) begin
                    stat_prefetch_starts_reg <= stat_prefetch_starts_reg + 1'b1;
                    prefetch_pending_reg <= 1'b0;
                end
            end

            if (!fill_active_reg && fill_plan_valid_reg && !error) begin
                fill_active_reg    <= 1'b1;
                fill_slot_reg      <= fill_plan_slot_reg;
                fill_tile_x_reg    <= fill_plan_tile_x_reg;
                fill_tile_y_reg    <= fill_plan_tile_y_reg;
                fill_row_idx_reg   <= '0;
                fill_col_idx_reg   <= '0;
                fill_row_width_reg <= fill_plan_row_width_reg;
                fill_tile_height_reg <= fill_plan_tile_height_reg;
                fill_is_prefetch_reg <= fill_plan_is_prefetch_reg;
                fill_plan_valid_reg <= 1'b0;
                slot_valid_reg[fill_plan_slot_reg]  <= 1'b0;
                slot_prefetched_reg[fill_plan_slot_reg] <= 1'b0;
                slot_tile_x_reg[fill_plan_slot_reg] <= fill_plan_tile_x_reg;
                slot_tile_y_reg[fill_plan_slot_reg] <= fill_plan_tile_y_reg;
                replace_ptr_reg <= fill_plan_slot_reg + 1'b1;
            end

            if (fill_active_reg && !row_inflight_reg && !read_busy && !error) begin
                read_addr_reg       <= cfg_src_base_addr_reg +
                    ((fill_tile_y_reg * TILE_H + fill_row_idx_reg) * cfg_src_stride_reg) +
                    (fill_tile_x_reg * TILE_W);
                read_byte_count_reg <= fill_row_width_reg;
                read_start_reg      <= 1'b1;
                row_inflight_reg    <= 1'b1;
                fill_col_idx_reg    <= '0;
                stat_read_starts_reg <= stat_read_starts_reg + 1'b1;
            end

            if (fill_active_reg && in_valid && in_ready) begin
                mem_reg[fill_slot_reg][fill_row_idx_reg][fill_col_idx_reg] <= in_data;
                fill_col_idx_reg <= fill_col_idx_reg + 1'b1;
            end

            if (fill_active_reg && row_inflight_reg && read_done) begin
                row_inflight_reg <= 1'b0;
                if ((fill_row_idx_reg + 1) >= fill_tile_height_reg) begin
                    fill_active_reg               <= 1'b0;
                    slot_valid_reg[fill_slot_reg] <= 1'b1;
                    slot_prefetched_reg[fill_slot_reg] <= fill_is_prefetch_reg;
                end else begin
                    fill_row_idx_reg <= fill_row_idx_reg + 1'b1;
                end
            end
        end
    end

endmodule
