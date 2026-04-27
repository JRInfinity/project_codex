`timescale 1ns/1ps

// 模块职责：
// 1. 使用 bilinear 插值完成单通道图像缩放。
// 2. 通过 line_req_* 与控制器握手，确保当前目标行所需的两条源行已经缓存到位。
// 3. 使用 line buffer 的两个读口，分两拍读取 x0 和 x1 对应的上下两行像素。
module scale_core_bilinear #(
    parameter int PIXEL_W   = 8,
    parameter int MAX_SRC_W = 7200,
    parameter int MAX_SRC_H = 7200,
    parameter int MAX_DST_W = 600,
    parameter int MAX_DST_H = 600,
    parameter int FRAC_W    = 16,
    parameter int LINE_NUM  = 2
) (
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic [$clog2(MAX_SRC_W+1)-1:0] src_w,
    input  logic [$clog2(MAX_SRC_H+1)-1:0] src_h,
    input  logic [$clog2(MAX_DST_W+1)-1:0] dst_w,
    input  logic [$clog2(MAX_DST_H+1)-1:0] dst_h,
    output logic busy,
    output logic done,
    output logic error,

    // 
    output logic                                              line_req_valid, // 请求当前行所需的两条源行已经准备好
    output logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] line_req_y, // 请求的行号
    input  logic                                              line_req_ready, // 控制器准备好接受行请求
    input  logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0]  line_req_sel, // 请求的行选择信号，指示控制器将哪两条源行数据提供到 rd0 和 rd1 读口

    output logic                                              pixel_req_valid, // 请求当前像素的两条源行数据已经准备好
    output logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] pixel_req_x, // 请求的像素列号
    input  logic [PIXEL_W-1:0]                                rd0_rsp_data, // 
    input  logic                                              rd0_rsp_valid,
    input  logic [PIXEL_W-1:0]                                rd1_rsp_data,
    input  logic                                              rd1_rsp_valid,

    output logic [PIXEL_W-1:0] pix_data, // 插值后输出像素数据
    output logic               pix_valid,
    input  logic               pix_ready,
    output logic               row_done
);

    localparam int SRC_X_W    = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int SRC_Y_W    = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;
    localparam int DST_X_W    = $clog2(MAX_DST_W+1);
    localparam int DST_Y_W    = $clog2(MAX_DST_H+1);
    localparam int LINE_SEL_W = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;
    localparam int SCALE_W    = FRAC_W + 16;
    localparam int MUL_W      = PIXEL_W + FRAC_W + 1; // 乘法结果宽度：像素值宽度 + 小数部分宽度 + 1（防止溢出）
    localparam int ACC_W      = MUL_W + 1; // 加法结果宽度：乘法结果宽度 + 1（防止溢出）

    typedef enum logic [2:0] {
        S_IDLE,
        S_PREP_ROW,
        S_REQ_LINES,
        S_REQ_X0,
        S_WAIT_X0,
        S_REQ_X1,
        S_WAIT_X1,
        S_OUT
    } state_t;

    state_t state_reg;
    state_t state_next;

    logic [DST_X_W-1:0] dst_x_reg;
    logic [DST_Y_W-1:0] dst_y_reg;
    logic [SCALE_W-1:0] scale_x_reg;
    logic [SCALE_W-1:0] scale_y_reg;
    logic [SCALE_W-1:0] x_pos_reg;
    logic [SCALE_W-1:0] y_pos_reg;

    logic [SRC_X_W-1:0] src_x0_reg;
    logic [SRC_X_W-1:0] src_x1_reg;
    logic [SRC_Y_W-1:0] src_y0_reg;
    logic [SRC_Y_W-1:0] src_y1_reg;
    logic [FRAC_W-1:0] frac_x_reg;
    logic [FRAC_W-1:0] frac_y_reg;
    logic [LINE_SEL_W-1:0] line_sel0_reg; // 当前行所需的两条源行在 line buffer 中的选择信号
    logic [LINE_SEL_W-1:0] line_sel1_reg;

    logic [PIXEL_W-1:0] p00_reg;
    logic [PIXEL_W-1:0] p10_reg;
    logic [PIXEL_W-1:0] p01_reg;
    logic [PIXEL_W-1:0] p11_reg;
    logic [PIXEL_W-1:0] pix_data_reg;
    logic               pix_valid_reg;

    logic [SCALE_W-1:0] x_pos_next_calc;
    logic [SCALE_W-1:0] y_pos_next_calc;
    logic [SRC_X_W:0]   src_x0_calc_full;
    logic [SRC_Y_W:0]   src_y0_calc_full;
    logic [SRC_X_W:0]   src_x1_calc_full;
    logic [SRC_Y_W:0]   src_y1_calc_full;
    logic [SRC_X_W:0]   next_src_x0_calc_full;
    logic [SRC_Y_W:0]   next_src_y0_calc_full;
    logic [SRC_X_W:0]   next_src_x1_calc_full;
    logic [SRC_Y_W:0]   next_src_y1_calc_full;
    logic [FRAC_W-1:0]  frac_x_calc;
    logic [FRAC_W-1:0]  frac_y_calc;
    logic [FRAC_W-1:0]  next_frac_x_calc;
    logic [FRAC_W-1:0]  next_frac_y_calc;
    logic [SRC_X_W-1:0] src_x0_calc;
    logic [SRC_X_W-1:0] src_x1_calc;
    logic [SRC_Y_W-1:0] src_y0_calc;
    logic [SRC_Y_W-1:0] src_y1_calc;
    logic [SRC_X_W-1:0] next_src_x0_calc;
    logic [SRC_X_W-1:0] next_src_x1_calc;
    logic [SRC_Y_W-1:0] next_src_y0_calc;
    logic [SRC_Y_W-1:0] next_src_y1_calc;
    logic [ACC_W-1:0]   top_mix_calc;
    logic [ACC_W-1:0]   bot_mix_calc;
    logic [ACC_W-1:0]   out_mix_calc;
    logic [PIXEL_W-1:0] out_pix_calc;
    logic [ACC_W-1:0]   top_mix_live_calc;
    logic [ACC_W-1:0]   bot_mix_live_calc;
    logic [ACC_W-1:0]   out_mix_live_calc;
    logic [PIXEL_W-1:0] out_pix_live_calc;
    logic               last_col;
    logic               last_row;
    logic               pix_fire;

    always_comb begin
        x_pos_next_calc = x_pos_reg + scale_x_reg; // x_pos_reg 在源图坐标系下的目标图像素坐标（定点数表示）
        y_pos_next_calc = y_pos_reg + scale_y_reg;

        src_x0_calc_full = x_pos_reg >> FRAC_W; // 整数部分
        src_y0_calc_full = y_pos_reg >> FRAC_W;
        frac_x_calc      = x_pos_reg[FRAC_W-1:0]; // 小数部分
        frac_y_calc      = y_pos_reg[FRAC_W-1:0];
        next_src_x0_calc_full = x_pos_next_calc >> FRAC_W;
        next_src_y0_calc_full = y_pos_next_calc >> FRAC_W;
        next_frac_x_calc      = x_pos_next_calc[FRAC_W-1:0];
        next_frac_y_calc      = y_pos_next_calc[FRAC_W-1:0];

        if (src_x0_calc_full >= src_w) begin
            src_x0_calc = src_w - 1'b1;
        end else begin
            src_x0_calc = src_x0_calc_full[SRC_X_W-1:0]; //  
        end

        if (src_y0_calc_full >= src_h) begin
            src_y0_calc = src_h - 1'b1;
        end else begin
            src_y0_calc = src_y0_calc_full[SRC_Y_W-1:0];
        end

        src_x1_calc_full = src_x0_calc + 1'b1;
        src_y1_calc_full = src_y0_calc + 1'b1;

        if (src_x1_calc_full >= src_w) begin
            src_x1_calc = src_w - 1'b1;
        end else begin
            src_x1_calc = src_x1_calc_full[SRC_X_W-1:0];
        end

        if (src_y1_calc_full >= src_h) begin
            src_y1_calc = src_h - 1'b1;
        end else begin
            src_y1_calc = src_y1_calc_full[SRC_Y_W-1:0];
        end

        if (next_src_x0_calc_full >= src_w) begin
            next_src_x0_calc = src_w - 1'b1;
        end else begin
            next_src_x0_calc = next_src_x0_calc_full[SRC_X_W-1:0];
        end

        if (next_src_y0_calc_full >= src_h) begin
            next_src_y0_calc = src_h - 1'b1;
        end else begin
            next_src_y0_calc = next_src_y0_calc_full[SRC_Y_W-1:0];
        end

        next_src_x1_calc_full = next_src_x0_calc + 1'b1;
        next_src_y1_calc_full = next_src_y0_calc + 1'b1;

        if (next_src_x1_calc_full >= src_w) begin
            next_src_x1_calc = src_w - 1'b1;
        end else begin
            next_src_x1_calc = next_src_x1_calc_full[SRC_X_W-1:0];
        end

        if (next_src_y1_calc_full >= src_h) begin
            next_src_y1_calc = src_h - 1'b1;
        end else begin
            next_src_y1_calc = next_src_y1_calc_full[SRC_Y_W-1:0];
        end

        top_mix_calc = ((ACC_W'(p00_reg) * ACC_W'((1 << FRAC_W) - frac_x_reg)) +
                        (ACC_W'(p01_reg) * ACC_W'(frac_x_reg)) +
                        ACC_W'(1 << (FRAC_W - 1))) >> FRAC_W; //
        bot_mix_calc = ((ACC_W'(p10_reg) * ACC_W'((1 << FRAC_W) - frac_x_reg)) +
                        (ACC_W'(p11_reg) * ACC_W'(frac_x_reg)) +
                        ACC_W'(1 << (FRAC_W - 1))) >> FRAC_W;
        out_mix_calc = ((top_mix_calc * ACC_W'((1 << FRAC_W) - frac_y_reg)) +
                        (bot_mix_calc * ACC_W'(frac_y_reg)) +
                        ACC_W'(1 << (FRAC_W - 1))) >> FRAC_W;
        out_pix_calc = out_mix_calc[PIXEL_W-1:0];

        top_mix_live_calc = ((ACC_W'(p00_reg) * ACC_W'((1 << FRAC_W) - frac_x_reg)) +
                             (ACC_W'(rd0_rsp_data) * ACC_W'(frac_x_reg)) +
                             ACC_W'(1 << (FRAC_W - 1))) >> FRAC_W;
        bot_mix_live_calc = ((ACC_W'(p10_reg) * ACC_W'((1 << FRAC_W) - frac_x_reg)) +
                             (ACC_W'(rd1_rsp_data) * ACC_W'(frac_x_reg)) +
                             ACC_W'(1 << (FRAC_W - 1))) >> FRAC_W;
        out_mix_live_calc = ((top_mix_live_calc * ACC_W'((1 << FRAC_W) - frac_y_reg)) +
                             (bot_mix_live_calc * ACC_W'(frac_y_reg)) +
                             ACC_W'(1 << (FRAC_W - 1))) >> FRAC_W;
        out_pix_live_calc = out_mix_live_calc[PIXEL_W-1:0];

        state_next = state_reg;
        case (state_reg)
            S_IDLE: begin // 空闲状态
                if (start) begin
                    state_next = S_PREP_ROW;
                end
            end

            S_PREP_ROW: begin // 
                if (error) begin
                    state_next = S_IDLE;
                end else begin
                    state_next = S_REQ_LINES;
                end
            end

            S_REQ_LINES: begin
                if (line_req_valid && line_req_ready) begin
                    state_next = S_REQ_X0;
                end
            end

            S_REQ_X0: begin
                state_next = S_WAIT_X0;
            end

            S_WAIT_X0: begin
                if (rd0_rsp_valid && rd1_rsp_valid) begin
                    state_next = S_REQ_X1;
                end
            end

            S_REQ_X1: begin
                state_next = S_WAIT_X1;
            end

            S_WAIT_X1: begin
                if (rd0_rsp_valid && rd1_rsp_valid) begin
                    state_next = S_OUT;
                end
            end

            S_OUT: begin
                if (pix_fire) begin
                    if (last_col && last_row) begin
                        state_next = S_IDLE;
                    end else if (last_col) begin
                        state_next = S_PREP_ROW;
                    end else begin
                        state_next = S_REQ_X0;
                    end
                end
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    assign busy           = (state_reg != S_IDLE);
    assign last_col       = (dst_x_reg == dst_w - 1'b1);
    assign last_row       = (dst_y_reg == dst_h - 1'b1);
    assign pix_fire       = pix_valid_reg && pix_ready;
    assign line_req_valid = (state_reg == S_REQ_LINES);
    assign line_req_y     = src_y0_reg;

    assign pixel_req_valid  = (state_reg == S_REQ_X0) || (state_reg == S_REQ_X1);
    assign pixel_req_x      = (state_reg == S_REQ_X0) ? src_x0_reg : src_x1_reg;

    assign pix_data  = pix_data_reg;
    assign pix_valid = pix_valid_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg      <= S_IDLE;
            dst_x_reg      <= '0;
            dst_y_reg      <= '0;
            scale_x_reg    <= '0;
            scale_y_reg    <= '0;
            x_pos_reg      <= '0;
            y_pos_reg      <= '0;
            src_x0_reg     <= '0;
            src_x1_reg     <= '0;
            src_y0_reg     <= '0;
            src_y1_reg     <= '0;
            frac_x_reg     <= '0;
            frac_y_reg     <= '0;
            line_sel0_reg  <= '0;
            line_sel1_reg  <= '0;
            p00_reg        <= '0;
            p10_reg        <= '0;
            p01_reg        <= '0;
            p11_reg        <= '0;
            pix_data_reg   <= '0;
            pix_valid_reg  <= 1'b0;
            done           <= 1'b0;
            error          <= 1'b0;
            row_done       <= 1'b0;
        end else begin
            state_reg <= state_next;
            done      <= 1'b0;
            row_done  <= 1'b0;

            case (state_reg)
                S_IDLE: begin
                    pix_valid_reg <= 1'b0;
                    error         <= 1'b0;

                    if (start) begin
                        dst_x_reg <= '0;
                        dst_y_reg <= '0;
                        x_pos_reg <= '0;
                        y_pos_reg <= '0;

                        if ((src_w == 0) || (src_h == 0) || (dst_w == 0) || (dst_h == 0)) begin
                            error <= 1'b1;
                        end else begin
                            scale_x_reg <= (src_w << FRAC_W) / dst_w;
                            scale_y_reg <= (src_h << FRAC_W) / dst_h;
                        end
                    end
                end

                S_PREP_ROW: begin
                    src_x0_reg    <= src_x0_calc;
                    src_x1_reg    <= src_x1_calc;
                    src_y0_reg    <= src_y0_calc;
                    src_y1_reg    <= src_y1_calc;
                    frac_x_reg    <= frac_x_calc;
                    frac_y_reg    <= frac_y_calc;
                end

                S_REQ_LINES: begin
                    if (line_req_valid && line_req_ready) begin
                        line_sel0_reg <= line_req_sel;
                        line_sel1_reg <= line_req_sel ^ ((LINE_NUM == 2) ? 1'b1 : 1'b0);
                    end
                end

                S_WAIT_X0: begin
                    if (rd0_rsp_valid && rd1_rsp_valid) begin
                        p00_reg <= rd0_rsp_data;
                        p10_reg <= rd1_rsp_data;
                    end
                end

                S_WAIT_X1: begin
                    if (rd0_rsp_valid && rd1_rsp_valid) begin
                        p01_reg       <= rd0_rsp_data;
                        p11_reg       <= rd1_rsp_data;
                        pix_data_reg  <= out_pix_live_calc;
                        pix_valid_reg <= 1'b1;
                    end
                end

                S_OUT: begin
                    if (pix_fire) begin
                        pix_valid_reg <= 1'b0;

                        if (last_col) begin
                            row_done <= 1'b1;

                            if (last_row) begin
                                done <= 1'b1;
                            end else begin
                                dst_x_reg <= '0;
                                dst_y_reg <= dst_y_reg + 1'b1;
                                x_pos_reg <= '0;
                                y_pos_reg <= y_pos_next_calc;
                            end
                        end else begin
                            dst_x_reg <= dst_x_reg + 1'b1;
                            x_pos_reg <= x_pos_next_calc;
                            src_x0_reg <= next_src_x0_calc;
                            src_x1_reg <= next_src_x1_calc;
                            frac_x_reg <= next_frac_x_calc;
                        end
                    end
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

endmodule
