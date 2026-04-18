`timescale 1ns/1ps

module rotate_core_bilinear #(
    parameter int PIXEL_W   = 8,
    parameter int MAX_SRC_W = 7200,
    parameter int MAX_SRC_H = 7200,
    parameter int MAX_DST_W = 600,
    parameter int MAX_DST_H = 600,
    parameter int FRAC_W    = 16,
    parameter int COORD_W   = 48
) (
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic [$clog2(MAX_SRC_W+1)-1:0] src_w,
    input  logic [$clog2(MAX_SRC_H+1)-1:0] src_h,
    input  logic [$clog2(MAX_DST_W+1)-1:0] dst_w,
    input  logic [$clog2(MAX_DST_H+1)-1:0] dst_h,
    input  logic signed [31:0] angle_cos_q16,
    input  logic signed [31:0] angle_sin_q16,
    output logic busy,
    output logic done,
    output logic error,

    output logic                                              sample_req_valid,
    output logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x0,
    output logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y0,
    output logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x1,
    output logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y1,
    input  logic                                              sample_req_ready,
    input  logic [PIXEL_W-1:0]                                sample_p00,
    input  logic [PIXEL_W-1:0]                                sample_p01,
    input  logic [PIXEL_W-1:0]                                sample_p10,
    input  logic [PIXEL_W-1:0]                                sample_p11,
    input  logic                                              sample_rsp_valid,

    output logic signed [1:0]                                scan_dir_x,
    output logic signed [1:0]                                scan_dir_y,
    output logic                                             scan_dir_valid,

    output logic [PIXEL_W-1:0] pix_data,
    output logic               pix_valid,
    input  logic               pix_ready,
    output logic               row_done
);

    localparam int SRC_X_W = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int SRC_Y_W = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;
    localparam int SRC_CFG_W = $clog2(MAX_SRC_W+1);
    localparam int SRC_CFG_H = $clog2(MAX_SRC_H+1);
    localparam int DST_X_W = $clog2(MAX_DST_W+1);
    localparam int DST_Y_W = $clog2(MAX_DST_H+1);
    localparam int MIX_W      = PIXEL_W + FRAC_W + 2;
    localparam int INIT_MUL_W = 64;
    typedef enum logic [5:0] {
        S_IDLE,
        S_DIV_X_INIT,
        S_DIV_X_RUN,
        S_DIV_Y_INIT,
        S_DIV_Y_RUN,
        S_CENTER,
        S_STEP_XX,
        S_STEP_YX_MUL,
        S_STEP_YX,
        S_STEP_XY,
        S_STEP_YY,
        S_ROW0_X_PREP,
        S_ROW0_X_MUL,
        S_ROW0_X_SUM,
        S_ROW0_X_COMMIT,
        S_ROW0_Y_MUL,
        S_ROW0_Y_SUM,
        S_ROW0_Y_COMMIT,
        S_PRECALC_INIT,
        S_PRECALC_RUN,
        S_PRECALC_WAIT,
        S_PRECALC_STORE,
        S_LOAD0,
        S_LOAD1,
        S_LOAD2,
        S_CLAMP,
        S_INDEX,
        S_REQ,
        S_WAIT,
        S_MIX0_MUL,
        S_MIX0_SUM,
        S_MIX1,
        S_OUT
    } state_t;

    state_t state_reg;

    logic [DST_X_W-1:0] dst_x_reg;
    logic [DST_Y_W-1:0] dst_y_reg;
    logic signed [COORD_W-1:0] row0_x_base_reg;
    logic signed [COORD_W-1:0] row0_y_base_reg;
    logic                      row_base_wr_en;
    logic [DST_Y_W-1:0]        row_base_wr_addr;
    logic [2*COORD_W-1:0]      row_base_wr_data;
    logic                      row_base_rd_en_reg;
    logic [DST_Y_W-1:0]        row_base_rd_addr_reg;
    logic [2*COORD_W-1:0]      row_base_rd_data;
    logic signed [COORD_W-1:0] cur_x_reg;
    logic signed [COORD_W-1:0] cur_y_reg;
    logic signed [COORD_W-1:0] step_x_x_reg;
    logic signed [COORD_W-1:0] step_y_x_reg;
    logic signed [COORD_W-1:0] step_x_y_reg;
    logic signed [COORD_W-1:0] step_y_y_reg;
    logic signed [31:0]        scale_x_q16_reg;
    logic signed [31:0]        scale_y_q16_reg;
    logic [DST_X_W-1:0]        cfg_dst_w_reg;
    logic [DST_Y_W-1:0]        cfg_dst_h_reg;
    logic [SRC_CFG_W-1:0]      cfg_src_w_reg;
    logic [SRC_CFG_H-1:0]      cfg_src_h_reg;
    logic signed [31:0]        cfg_angle_cos_q16_reg;
    logic signed [31:0]        cfg_angle_sin_q16_reg;
    logic signed [COORD_W-1:0] src_cx_q16_reg;
    logic signed [COORD_W-1:0] src_cy_q16_reg;
    logic signed [COORD_W-1:0] dst_cx_q16_reg;
    logic signed [COORD_W-1:0] dst_cy_q16_reg;
    logic signed [COORD_W-1:0] row0_src_cx_hold_reg;
    logic signed [COORD_W-1:0] row0_src_cy_hold_reg;
    logic signed [COORD_W-1:0] row0_dst_cx_hold_reg;
    logic signed [COORD_W-1:0] row0_dst_cy_hold_reg;
    logic signed [COORD_W-1:0] row0_step_x_x_hold_reg;
    logic signed [COORD_W-1:0] row0_step_y_x_hold_reg;
    logic signed [COORD_W-1:0] row0_step_x_y_hold_reg;
    logic signed [COORD_W-1:0] row0_step_y_y_hold_reg;
    logic signed [COORD_W-1:0] cfg_src_x_max_q16_reg;
    logic signed [COORD_W-1:0] cfg_src_y_max_q16_reg;
    logic [SRC_X_W-1:0]        cfg_src_x_last_reg;
    logic [SRC_Y_W-1:0]        cfg_src_y_last_reg;
    logic signed [COORD_W-1:0] clamp_x_reg;
    logic signed [COORD_W-1:0] clamp_y_reg;
    logic signed [COORD_W-1:0] row_x_next_reg;
    logic signed [COORD_W-1:0] row_y_next_reg;
    logic signed [COORD_W-1:0] precalc_base_x_reg;
    logic signed [COORD_W-1:0] precalc_base_y_reg;
    logic [DST_Y_W-1:0]        precalc_idx_reg;
    logic                      row_adv_done_reg;
    logic signed [COORD_W-1:0] row_adv_next_x;
    logic signed [COORD_W-1:0] row_adv_next_y;
    logic [SRC_X_W-1:0]        sample_x0_reg;
    logic [SRC_X_W-1:0]        sample_x1_reg;
    logic [SRC_Y_W-1:0]        sample_y0_reg;
    logic [SRC_Y_W-1:0]        sample_y1_reg;
    logic [FRAC_W-1:0]         frac_x_reg;
    logic [FRAC_W-1:0]         frac_y_reg;
    logic [PIXEL_W-1:0]        sample_p00_reg;
    logic [PIXEL_W-1:0]        sample_p01_reg;
    logic [PIXEL_W-1:0]        sample_p10_reg;
    logic [PIXEL_W-1:0]        sample_p11_reg;
    logic [PIXEL_W-1:0]        mix_p00_reg;
    logic [PIXEL_W-1:0]        mix_p01_reg;
    logic [PIXEL_W-1:0]        mix_p10_reg;
    logic [PIXEL_W-1:0]        mix_p11_reg;
    logic [FRAC_W-1:0]         mix_frac_x_reg;
    logic [FRAC_W-1:0]         mix_frac_y_reg;
    logic [MIX_W-1:0]          top_mul0_reg;
    logic [MIX_W-1:0]          top_mul1_reg;
    logic [MIX_W-1:0]          bot_mul0_reg;
    logic [MIX_W-1:0]          bot_mul1_reg;
    logic [MIX_W-1:0]          top_mix_reg;
    logic [MIX_W-1:0]          bot_mix_reg;
    logic [MIX_W-1:0]          out_mix_reg;
    logic [PIXEL_W-1:0] pix_data_reg;
    logic               pix_valid_reg;

    logic [31:0]               div_dividend_reg;
    logic [31:0]               div_divisor_reg;
    logic [31:0]               div_quotient_reg;
    logic [32:0]               div_remainder_reg;
    logic [5:0]                div_count_reg;
    logic [32:0]               div_remainder_shift_calc;
    logic [32:0]               div_remainder_next_calc;
    logic [31:0]               div_dividend_next_calc;
    logic [31:0]               div_quotient_next_calc;

    logic signed [COORD_W-1:0] next_x_calc;
    logic signed [COORD_W-1:0] next_y_calc;
    logic signed [COORD_W-1:0] clamped_x_q16_calc;
    logic signed [COORD_W-1:0] clamped_y_q16_calc;
    logic [SRC_X_W-1:0]        sample_x0_calc;
    logic [SRC_X_W-1:0]        sample_x1_calc;
    logic [SRC_Y_W-1:0]        sample_y0_calc;
    logic [SRC_Y_W-1:0]        sample_y1_calc;
    logic [FRAC_W-1:0]         frac_x_calc;
    logic [FRAC_W-1:0]         frac_y_calc;
    logic [MIX_W-1:0]          top_mul0_calc;
    logic [MIX_W-1:0]          top_mul1_calc;
    logic [MIX_W-1:0]          bot_mul0_calc;
    logic [MIX_W-1:0]          bot_mul1_calc;
    logic [MIX_W-1:0]          top_mix_calc;
    logic [MIX_W-1:0]          bot_mix_calc;
    logic [MIX_W-1:0]          out_mix_calc;
    logic signed [INIT_MUL_W-1:0] row0_x_mul0_reg;
    logic signed [INIT_MUL_W-1:0] row0_x_mul1_reg;
    logic signed [COORD_W-1:0] row0_x_dst_cx_mul_reg;
    logic signed [COORD_W-1:0] row0_x_dst_cy_mul_reg;
    logic signed [COORD_W-1:0] row0_x_step_x_x_mul_reg;
    logic signed [COORD_W-1:0] row0_x_step_x_y_mul_reg;
    logic signed [INIT_MUL_W-1:0] row0_y_mul0_reg;
    logic signed [INIT_MUL_W-1:0] row0_y_mul1_reg;
    logic signed [INIT_MUL_W-1:0] row0_x_base_wide_reg;
    logic signed [INIT_MUL_W-1:0] row0_y_base_wide_reg;
    logic signed [INIT_MUL_W-1:0] step_y_x_mul_reg;

    logic last_col;
    logic last_row;
    logic pix_fire;

    always_comb begin
        div_remainder_shift_calc = {div_remainder_reg[31:0], div_dividend_reg[31]};
        div_dividend_next_calc   = {div_dividend_reg[30:0], 1'b0};
        if (div_remainder_shift_calc >= {1'b0, div_divisor_reg}) begin
            div_remainder_next_calc = div_remainder_shift_calc - {1'b0, div_divisor_reg};
            div_quotient_next_calc  = {div_quotient_reg[30:0], 1'b1};
        end else begin
            div_remainder_next_calc = div_remainder_shift_calc;
            div_quotient_next_calc  = {div_quotient_reg[30:0], 1'b0};
        end
    end

    always_comb begin
        next_x_calc          = cur_x_reg + step_x_x_reg;
        next_y_calc          = cur_y_reg + step_y_x_reg;
    end

    always_comb begin
        clamped_x_q16_calc = cur_x_reg;
        clamped_y_q16_calc = cur_y_reg;

        if (cur_x_reg < 0) begin
            clamped_x_q16_calc = '0;
        end else if (cur_x_reg > cfg_src_x_max_q16_reg) begin
            clamped_x_q16_calc = cfg_src_x_max_q16_reg;
        end

        if (cur_y_reg < 0) begin
            clamped_y_q16_calc = '0;
        end else if (cur_y_reg > cfg_src_y_max_q16_reg) begin
            clamped_y_q16_calc = cfg_src_y_max_q16_reg;
        end
    end

    always_comb begin
        sample_x0_calc = clamp_x_reg[FRAC_W +: SRC_X_W];
        sample_y0_calc = clamp_y_reg[FRAC_W +: SRC_Y_W];
        frac_x_calc    = clamp_x_reg[FRAC_W-1:0];
        frac_y_calc    = clamp_y_reg[FRAC_W-1:0];

        if (sample_x0_calc >= cfg_src_x_last_reg) begin
            sample_x1_calc = cfg_src_x_last_reg;
        end else begin
            sample_x1_calc = sample_x0_calc + 1'b1;
        end

        if (sample_y0_calc >= cfg_src_y_last_reg) begin
            sample_y1_calc = cfg_src_y_last_reg;
        end else begin
            sample_y1_calc = sample_y0_calc + 1'b1;
        end
    end

    always_comb begin
        top_mul0_calc = MIX_W'(mix_p00_reg) * MIX_W'((1 << FRAC_W) - mix_frac_x_reg);
        top_mul1_calc = MIX_W'(mix_p01_reg) * MIX_W'(mix_frac_x_reg);
        bot_mul0_calc = MIX_W'(mix_p10_reg) * MIX_W'((1 << FRAC_W) - mix_frac_x_reg);
        bot_mul1_calc = MIX_W'(mix_p11_reg) * MIX_W'(mix_frac_x_reg);
    end

    always_comb begin
        top_mix_calc = ((top_mul0_reg + top_mul1_reg) +
                        MIX_W'(1 << (FRAC_W - 1))) >> FRAC_W;
        bot_mix_calc = ((bot_mul0_reg + bot_mul1_reg) +
                        MIX_W'(1 << (FRAC_W - 1))) >> FRAC_W;
    end

    always_comb begin
        out_mix_calc = ((top_mix_reg * MIX_W'((1 << FRAC_W) - mix_frac_y_reg)) +
                        (bot_mix_reg * MIX_W'(mix_frac_y_reg)) +
                        MIX_W'(1 << (FRAC_W - 1))) >> FRAC_W;
    end

    assign busy           = (state_reg != S_IDLE);
    assign pix_data       = pix_data_reg;
    assign pix_valid      = pix_valid_reg;
    assign sample_req_valid = (state_reg == S_REQ);
    assign sample_x0      = sample_x0_reg;
    assign sample_y0      = sample_y0_reg;
    assign sample_x1      = sample_x1_reg;
    assign sample_y1      = sample_y1_reg;
    assign last_col       = (dst_x_reg == cfg_dst_w_reg - 1'b1);
    assign last_row       = (dst_y_reg == cfg_dst_h_reg - 1'b1);
    assign pix_fire       = pix_valid_reg && pix_ready;
    assign scan_dir_x     = (step_x_x_reg > 0) ? 2'sd1 : ((step_x_x_reg < 0) ? -2'sd1 : 2'sd0);
    assign scan_dir_y     = (step_y_x_reg > 0) ? 2'sd1 : ((step_y_x_reg < 0) ? -2'sd1 : 2'sd0);
    assign scan_dir_valid = busy && (((step_x_x_reg == 0) && (step_y_x_reg != 0)) ||
                                     ((step_x_x_reg != 0) && (step_y_x_reg == 0)));

    always_comb begin
        row_base_wr_en   = 1'b0;
        row_base_wr_addr = '0;
        row_base_wr_data = '0;

        if (state_reg == S_PRECALC_INIT) begin
            row_base_wr_en   = 1'b1;
            row_base_wr_addr = '0;
            row_base_wr_data = {row0_y_base_reg, row0_x_base_reg};
        end else if (state_reg == S_PRECALC_STORE) begin
            row_base_wr_en   = 1'b1;
            row_base_wr_addr = precalc_idx_reg + 1'b1;
            row_base_wr_data = {row_y_next_reg, row_x_next_reg};
        end
    end

    row_advance_unit #(
        .COORD_W(COORD_W),
        .FRAC_W (FRAC_W)
    ) u_row_advance (
        .clk   (clk),
        .rst   (rst),
        .start (state_reg == S_PRECALC_RUN),
        .base_x(precalc_base_x_reg),
        .base_y(precalc_base_y_reg),
        .step_x(step_x_y_reg),
        .step_y(step_y_y_reg),
        .busy  (),
        .done  (row_adv_done_reg),
        .next_x(row_adv_next_x),
        .next_y(row_adv_next_y)
    );

    xpm_memory_sdpram #( // 这是Xilinx单端口RAM生成器IP核的SystemVerilog版本，参数配置为适合存储行基地址的预计算结果
        .ADDR_WIDTH_A        (DST_Y_W),
        .ADDR_WIDTH_B        (DST_Y_W),
        .AUTO_SLEEP_TIME     (0),
        .BYTE_WRITE_WIDTH_A  (2*COORD_W),
        .CASCADE_HEIGHT      (0),
        .CLOCKING_MODE       ("common_clock"),
        .ECC_MODE            ("no_ecc"),
        .MEMORY_INIT_FILE    ("none"),
        .MEMORY_INIT_PARAM   ("0"),
        .MEMORY_OPTIMIZATION ("true"),
        .MEMORY_PRIMITIVE    ("block"),
        .MEMORY_SIZE         ((1 << DST_Y_W) * 2 * COORD_W),
        .MESSAGE_CONTROL     (0),
        .READ_DATA_WIDTH_B   (2*COORD_W),
        .READ_LATENCY_B      (1),
        .READ_RESET_VALUE_B  ("0"),
        .RST_MODE_A          ("SYNC"),
        .RST_MODE_B          ("SYNC"),
        .SIM_ASSERT_CHK      (0),
        .USE_EMBEDDED_CONSTRAINT (0),
        .USE_MEM_INIT        (0),
        .WAKEUP_TIME         ("disable_sleep"),
        .WRITE_DATA_WIDTH_A  (2*COORD_W),
        .WRITE_MODE_B        ("no_change")
    ) u_row_base_table_ram (
        .clka           (clk),
        .ena            (row_base_wr_en),
        .wea            (row_base_wr_en),
        .addra          (row_base_wr_addr),
        .dina           (row_base_wr_data),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (clk),
        .rstb           (1'b0),
        .enb            (row_base_rd_en_reg),
        .regceb         (1'b1),
        .addrb          (row_base_rd_addr_reg),
        .doutb          (row_base_rd_data),
        .sbiterrb       (),
        .dbiterrb       (),
        .sleep          (1'b0)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            row_base_rd_en_reg   <= 1'b0;
            row_base_rd_addr_reg <= '0;
        end else begin
            row_base_rd_en_reg <= (state_reg == S_LOAD0);
            if (state_reg == S_LOAD0) begin
                row_base_rd_addr_reg <= dst_y_reg;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            row0_x_base_reg <= '0;
        end else if (state_reg == S_ROW0_X_COMMIT) begin
            row0_x_base_reg <= row0_x_base_wide_reg[COORD_W-1:0];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            row0_y_base_reg <= '0;
        end else if (state_reg == S_ROW0_Y_COMMIT) begin
            row0_y_base_reg <= row0_y_base_wide_reg[COORD_W-1:0];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cur_x_reg <= '0;
        end else begin
            if (state_reg == S_LOAD2) begin
                cur_x_reg <= row_base_rd_data[COORD_W-1:0];
            end else if ((state_reg == S_OUT) && pix_fire && !last_col) begin
                cur_x_reg <= next_x_calc;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cur_y_reg <= '0;
        end else begin
            if (state_reg == S_LOAD2) begin
                cur_y_reg <= row_base_rd_data[2*COORD_W-1:COORD_W];
            end else if ((state_reg == S_OUT) && pix_fire && !last_col) begin
                cur_y_reg <= next_y_calc;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg      <= S_IDLE;
            dst_x_reg      <= '0;
            dst_y_reg      <= '0;
            step_x_x_reg   <= '0;
            step_y_x_reg   <= '0;
            step_x_y_reg   <= '0;
            step_y_y_reg   <= '0;
            scale_x_q16_reg <= '0;
            scale_y_q16_reg <= '0;
            cfg_dst_w_reg   <= '0;
            cfg_dst_h_reg   <= '0;
            cfg_src_w_reg   <= '0;
            cfg_src_h_reg   <= '0;
            cfg_angle_cos_q16_reg <= '0;
            cfg_angle_sin_q16_reg <= '0;
            src_cx_q16_reg <= '0;
            src_cy_q16_reg <= '0;
            dst_cx_q16_reg <= '0;
            dst_cy_q16_reg <= '0;
            row0_src_cx_hold_reg <= '0;
            row0_src_cy_hold_reg <= '0;
            row0_dst_cx_hold_reg <= '0;
            row0_dst_cy_hold_reg <= '0;
            row0_step_x_x_hold_reg <= '0;
            row0_step_y_x_hold_reg <= '0;
            row0_step_x_y_hold_reg <= '0;
            row0_step_y_y_hold_reg <= '0;
            cfg_src_x_max_q16_reg <= '0;
            cfg_src_y_max_q16_reg <= '0;
            cfg_src_x_last_reg <= '0;
            cfg_src_y_last_reg <= '0;
            clamp_x_reg <= '0;
            clamp_y_reg <= '0;
            row_x_next_reg <= '0;
            row_y_next_reg <= '0;
            precalc_base_x_reg <= '0;
            precalc_base_y_reg <= '0;
            precalc_idx_reg <= '0;
            sample_x0_reg <= '0;
            sample_x1_reg <= '0;
            sample_y0_reg <= '0;
            sample_y1_reg <= '0;
            frac_x_reg     <= '0;
            frac_y_reg     <= '0;
            sample_p00_reg <= '0;
            sample_p01_reg <= '0;
            sample_p10_reg <= '0;
            sample_p11_reg <= '0;
            mix_p00_reg    <= '0;
            mix_p01_reg    <= '0;
            mix_p10_reg    <= '0;
            mix_p11_reg    <= '0;
            mix_frac_x_reg <= '0;
            mix_frac_y_reg <= '0;
            top_mul0_reg   <= '0;
            top_mul1_reg   <= '0;
            bot_mul0_reg   <= '0;
            bot_mul1_reg   <= '0;
            top_mix_reg    <= '0;
            bot_mix_reg    <= '0;
            out_mix_reg    <= '0;
            pix_data_reg   <= '0;
            pix_valid_reg  <= 1'b0;
            div_dividend_reg <= '0;
            div_divisor_reg  <= '0;
            div_quotient_reg <= '0;
            div_remainder_reg <= '0;
            div_count_reg     <= '0;
            row0_x_mul0_reg <= '0;
            row0_x_mul1_reg <= '0;
            row0_x_dst_cx_mul_reg <= '0;
            row0_x_dst_cy_mul_reg <= '0;
            row0_x_step_x_x_mul_reg <= '0;
            row0_x_step_x_y_mul_reg <= '0;
            row0_y_mul0_reg <= '0;
            row0_y_mul1_reg <= '0;
            row0_x_base_wide_reg <= '0;
            row0_y_base_wide_reg <= '0;
            step_y_x_mul_reg <= '0;
            done           <= 1'b0;
            error          <= 1'b0;
            row_done       <= 1'b0;
        end else begin
            done     <= 1'b0;
            row_done <= 1'b0;

            case (state_reg)
                S_IDLE: begin
                    pix_valid_reg <= 1'b0;
                    error         <= 1'b0;  
                    // 开始 并进行初始化
                    if (start) begin
                        if ((src_w == 0) || (src_h == 0) || (dst_w == 0) || (dst_h == 0)) begin
                            error    <= 1'b1;
                            state_reg <= S_IDLE;
                        end else begin
                            dst_x_reg      <= '0;
                            dst_y_reg      <= '0;
                            cfg_src_w_reg  <= src_w;
                            cfg_src_h_reg  <= src_h;
                            cfg_dst_w_reg  <= dst_w;
                            cfg_dst_h_reg  <= dst_h;
                            cfg_angle_cos_q16_reg <= angle_cos_q16;
                            cfg_angle_sin_q16_reg <= angle_sin_q16;
                            cfg_src_x_last_reg <= src_w[SRC_X_W-1:0] - 1'b1;
                            cfg_src_y_last_reg <= src_h[SRC_Y_W-1:0] - 1'b1;
                            cfg_src_x_max_q16_reg <= ($signed({1'b0, src_w}) - 1) <<< FRAC_W; // 这里将最大坐标转换为Q16格式，乘以2^FRAC_W
                            cfg_src_y_max_q16_reg <= ($signed({1'b0, src_h}) - 1) <<< FRAC_W;
                            state_reg      <= S_DIV_X_INIT;
                        end
                    end
                end

                // 计算缩放因子除法初始化
                S_DIV_X_INIT: begin
                    div_dividend_reg  <= 32'sh0001_0000 * $signed({1'b0, cfg_src_w_reg}); // 这里将被除数设置为src_w的Q16格式，即src_w乘以2^FRAC_W
                    div_divisor_reg   <= {16'd0, cfg_dst_w_reg}; // 这里将除数设置为dst_w的整数格式，低16位为0
                    div_quotient_reg  <= '0;
                    div_remainder_reg <= '0;
                    div_count_reg     <= 6'd32;
                    state_reg         <= S_DIV_X_RUN;
                end

                // 计算缩放因子
                S_DIV_X_RUN: begin
                    div_dividend_reg  <= div_dividend_next_calc;
                    div_quotient_reg  <= div_quotient_next_calc;
                    div_remainder_reg <= div_remainder_next_calc;
                    div_count_reg     <= div_count_reg - 1'b1;

                    if (div_count_reg == 6'd1) begin
                        scale_x_q16_reg <= div_quotient_next_calc;
                        state_reg       <= S_DIV_Y_INIT;
                    end
                end

                // 计算缩放因子除法初始化
                S_DIV_Y_INIT: begin
                    div_dividend_reg  <= 32'sh0001_0000 * $signed({1'b0, cfg_src_h_reg});
                    div_divisor_reg   <= {16'd0, cfg_dst_h_reg};
                    div_quotient_reg  <= '0;
                    div_remainder_reg <= '0;
                    div_count_reg     <= 6'd32;
                    state_reg         <= S_DIV_Y_RUN;
                end

                // 计算缩放因子
                S_DIV_Y_RUN: begin
                    div_dividend_reg  <= div_dividend_next_calc;
                    div_quotient_reg  <= div_quotient_next_calc;
                    div_remainder_reg <= div_remainder_next_calc;
                    div_count_reg     <= div_count_reg - 1'b1;

                    if (div_count_reg == 6'd1) begin
                        scale_y_q16_reg <= div_quotient_next_calc;
                        state_reg       <= S_CENTER;
                    end
                end

                // 计算旋转中心
                S_CENTER: begin
                    src_cx_q16_reg <= ($signed({1'b0, cfg_src_w_reg}) - 1) <<< (FRAC_W-1);
                    src_cy_q16_reg <= ($signed({1'b0, cfg_src_h_reg}) - 1) <<< (FRAC_W-1);
                    dst_cx_q16_reg <= ($signed({1'b0, cfg_dst_w_reg}) - 1) <<< (FRAC_W-1);
                    dst_cy_q16_reg <= ($signed({1'b0, cfg_dst_h_reg}) - 1) <<< (FRAC_W-1);
                    row0_src_cx_hold_reg <= ($signed({1'b0, cfg_src_w_reg}) - 1) <<< (FRAC_W-1);
                    row0_src_cy_hold_reg <= ($signed({1'b0, cfg_src_h_reg}) - 1) <<< (FRAC_W-1);
                    row0_dst_cx_hold_reg <= ($signed({1'b0, cfg_dst_w_reg}) - 1) <<< (FRAC_W-1);
                    row0_dst_cy_hold_reg <= ($signed({1'b0, cfg_dst_h_reg}) - 1) <<< (FRAC_W-1);
                    state_reg           <= S_STEP_XX;
                end

                // 计算步进量：当输出图x加1时，源图坐标x增量step_x_x
                S_STEP_XX: begin
                    step_x_x_reg <= ($signed(cfg_angle_cos_q16_reg) * $signed(scale_x_q16_reg)) >>> FRAC_W;
                    row0_step_x_x_hold_reg <= ($signed(cfg_angle_cos_q16_reg) * $signed(scale_x_q16_reg)) >>> FRAC_W;
                    state_reg    <= S_STEP_YX_MUL;
                end

                // 计算步进量：当输出图x加1时，源图坐标y增量step_y_x的乘法中间结果
                // 有负号加入，故插入一级流水
                S_STEP_YX_MUL: begin
                    step_y_x_mul_reg <= $signed(cfg_angle_sin_q16_reg) * $signed(scale_x_q16_reg);
                    state_reg        <= S_STEP_YX;
                end

                // 计算步进量：当输出图x加1时，源图坐标y增量step_y_x
                S_STEP_YX: begin
                    step_y_x_reg <= -($signed(step_y_x_mul_reg) >>> FRAC_W);
                    row0_step_y_x_hold_reg <= -($signed(step_y_x_mul_reg) >>> FRAC_W);
                    state_reg <= S_STEP_XY;
                end

                // 计算步进量：当输出图y加1时，源图坐标x增量step_x_y
                S_STEP_XY: begin
                    step_x_y_reg <= ($signed(cfg_angle_sin_q16_reg) * $signed(scale_y_q16_reg)) >>> FRAC_W;
                    row0_step_x_y_hold_reg <= ($signed(cfg_angle_sin_q16_reg) * $signed(scale_y_q16_reg)) >>> FRAC_W;
                    state_reg    <= S_STEP_YY;
                end

                // 计算步进量：当输出图y加1时，源图坐标x增量step_y_y
                S_STEP_YY: begin
                    step_y_y_reg <= ($signed(cfg_angle_cos_q16_reg) * $signed(scale_y_q16_reg)) >>> FRAC_W;
                    row0_step_y_y_hold_reg <= ($signed(cfg_angle_cos_q16_reg) * $signed(scale_y_q16_reg)) >>> FRAC_W;
                    state_reg    <= S_ROW0_X_PREP;
                end

                // 下面几个状态计算第0行第0列的目标像素对应源图坐标，作为后续计算基点
                S_ROW0_X_PREP: begin
                    row0_x_dst_cx_mul_reg   <= row0_dst_cx_hold_reg;
                    row0_x_dst_cy_mul_reg   <= row0_dst_cy_hold_reg;
                    row0_x_step_x_x_mul_reg <= row0_step_x_x_hold_reg;
                    row0_x_step_x_y_mul_reg <= row0_step_x_y_hold_reg;
                    state_reg               <= S_ROW0_X_MUL;
                end

                S_ROW0_X_MUL: begin
                    row0_x_mul0_reg <= $signed(row0_x_dst_cx_mul_reg) * $signed(row0_x_step_x_x_mul_reg);
                    row0_x_mul1_reg <= $signed(row0_x_dst_cy_mul_reg) * $signed(row0_x_step_x_y_mul_reg);
                    state_reg       <= S_ROW0_X_SUM;
                end

                S_ROW0_X_SUM: begin
                    row0_x_base_wide_reg <= $signed(row0_src_cx_hold_reg)
                        - $signed(row0_x_mul0_reg >>> FRAC_W)
                        - $signed(row0_x_mul1_reg >>> FRAC_W);
                    state_reg <= S_ROW0_X_COMMIT;
                end

                S_ROW0_X_COMMIT: begin
                    state_reg <= S_ROW0_Y_MUL;
                end

                S_ROW0_Y_MUL: begin
                    row0_y_mul0_reg <= $signed(row0_dst_cx_hold_reg) * $signed(row0_step_y_x_hold_reg);
                    row0_y_mul1_reg <= $signed(row0_dst_cy_hold_reg) * $signed(row0_step_y_y_hold_reg);
                    state_reg       <= S_ROW0_Y_SUM;
                end

                S_ROW0_Y_SUM: begin
                    row0_y_base_wide_reg <= $signed(row0_src_cy_hold_reg)
                        - $signed(row0_y_mul0_reg >>> FRAC_W)
                        - $signed(row0_y_mul1_reg >>> FRAC_W);
                    state_reg <= S_ROW0_Y_COMMIT;
                end

                S_ROW0_Y_COMMIT: begin
                    state_reg <= S_PRECALC_INIT;
                end

                // 先把每一行的第一个起始源图坐标算出来，存到ram里
                S_PRECALC_INIT: begin
                    precalc_base_x_reg  <= row0_x_base_reg;
                    precalc_base_y_reg  <= row0_y_base_reg;
                    precalc_idx_reg     <= '0;
                    if (cfg_dst_h_reg == 1) begin
                        state_reg <= S_LOAD0;
                    end else begin
                        state_reg <= S_PRECALC_RUN;
                    end
                end

                S_PRECALC_RUN: begin
                    state_reg <= S_PRECALC_WAIT;
                end

                S_PRECALC_WAIT: begin
                    if (row_adv_done_reg) begin
                        row_x_next_reg <= row_adv_next_x;
                        row_y_next_reg <= row_adv_next_y;
                        state_reg      <= S_PRECALC_STORE;
                    end
                end

                // 算后续各行
                S_PRECALC_STORE: begin
                    precalc_base_x_reg <= row_x_next_reg;
                    precalc_base_y_reg <= row_y_next_reg;
                    if ((precalc_idx_reg + 1'b1) >= (cfg_dst_h_reg - 1'b1)) begin
                        state_reg <= S_LOAD0;
                    end else begin
                        precalc_idx_reg <= precalc_idx_reg + 1'b1;
                        state_reg        <= S_PRECALC_RUN;
                    end
                end

                // 给BRAM发读地址
                S_LOAD0: begin
                    state_reg  <= S_LOAD1;
                end

                S_LOAD1: begin
                    state_reg  <= S_LOAD2;
                end

                // 把 row_base_rd_data 分别装进 cur_x_reg 和 cur_y_reg
                S_LOAD2: begin
                    state_reg  <= S_CLAMP;
                end

                // 坐标钳位将其限制在源图坐标内
                S_CLAMP: begin
                    clamp_x_reg <= clamped_x_q16_calc;
                    clamp_y_reg <= clamped_y_q16_calc;
                    frac_x_reg  <= clamped_x_q16_calc[FRAC_W-1:0];
                    frac_y_reg  <= clamped_y_q16_calc[FRAC_W-1:0];
                    state_reg   <= S_INDEX;
                end

                S_INDEX: begin
                    sample_x0_reg <= sample_x0_calc;
                    sample_x1_reg <= sample_x1_calc;
                    sample_y0_reg <= sample_y0_calc;
                    sample_y1_reg <= sample_y1_calc;
                    state_reg     <= S_REQ;
                end

                // 向cache发2x2采样请求
                // 只有在sample_req_ready也为1（cache里真的有所请求的四个像素）时，
                // 这次请求才真正被cache接受，然后状态进入S_WAIT
                S_REQ: begin
                    if (sample_req_valid && sample_req_ready) begin
                        state_reg <= S_WAIT;
                    end
                end

                // 将cache给的4个点拉进来
                S_WAIT: begin
                    if (sample_rsp_valid) begin
                        sample_p00_reg <= sample_p00;
                        sample_p01_reg <= sample_p01;
                        sample_p10_reg <= sample_p10;
                        sample_p11_reg <= sample_p11;
                        mix_p00_reg    <= sample_p00;
                        mix_p01_reg    <= sample_p01;
                        mix_p10_reg    <= sample_p10;
                        mix_p11_reg    <= sample_p11;
                        mix_frac_x_reg <= frac_x_reg;
                        mix_frac_y_reg <= frac_y_reg;
                        state_reg      <= S_MIX0_MUL;
                    end
                end

                // 横向乘法
                S_MIX0_MUL: begin
                    top_mul0_reg <= top_mul0_calc;
                    top_mul1_reg <= top_mul1_calc;
                    bot_mul0_reg <= bot_mul0_calc;
                    bot_mul1_reg <= bot_mul1_calc;
                    state_reg    <= S_MIX0_SUM;
                end

                // 把上下两行分别横向混合
                S_MIX0_SUM: begin
                    top_mix_reg <= top_mix_calc;
                    bot_mix_reg <= bot_mix_calc;
                    state_reg   <= S_MIX1;
                end

                // 纵向混合
                S_MIX1: begin
                    out_mix_reg <= out_mix_calc; // out_mix_reg此即为输出像素
                    state_reg   <= S_OUT;
                end

                S_OUT: begin
                    if (!pix_valid_reg) begin
                        pix_data_reg  <= out_mix_reg[PIXEL_W-1:0];
                        pix_valid_reg <= 1'b1;
                    end

                    if (pix_fire) begin
                        pix_valid_reg <= 1'b0;
                        if (last_col) begin
                            row_done <= 1'b1;
                            if (last_row) begin
                                // 是最后一行最后一列
                                done     <= 1'b1;
                                state_reg <= S_IDLE;
                            end else begin
                                // 是本行最后一个像素，但不是最后一行
                                dst_x_reg      <= '0;
                                dst_y_reg      <= dst_y_reg + 1'b1;
                                state_reg      <= S_LOAD0;
                            end
                        end else begin
                            // 不是本行最后一个像素
                            dst_x_reg <= dst_x_reg + 1'b1;
                            state_reg <= S_CLAMP;
                        end
                    end
                end

                default: begin
                    state_reg <= S_IDLE;
                end
            endcase
        end
    end

endmodule
