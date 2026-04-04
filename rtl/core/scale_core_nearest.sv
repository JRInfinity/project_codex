`timescale 1ns/1ps

module scale_core_nearest #(
    parameter int PIXEL_W   = 8,    // 像素位宽
    parameter int MAX_SRC_W = 7200, // 支持的源图最大宽度
    parameter int MAX_SRC_H = 7200, // 支持的源图最大高度
    parameter int MAX_DST_W = 600,  // 支持的目标图最大宽度
    parameter int MAX_DST_H = 600,  // 支持的目标图最大高度
    parameter int FRAC_W    = 16,   // 定点缩放步长的小数位宽
    parameter int LINE_NUM  = 2     // 外部可用的行缓冲数量
) (
    input  logic clk,                                     // 核心时钟
    input  logic rst,                                     // 高电平复位
    input  logic start,                                   // 启动一次缩放任务
    input  logic [$clog2(MAX_SRC_W+1)-1:0] src_w,         // 当前源图宽度
    input  logic [$clog2(MAX_SRC_H+1)-1:0] src_h,         // 当前源图高度
    input  logic [$clog2(MAX_DST_W+1)-1:0] dst_w,         // 当前目标图宽度
    input  logic [$clog2(MAX_DST_H+1)-1:0] dst_h,         // 当前目标图高度
    output logic busy,                                    // 核心忙标志
    output logic done,                                    // 正常完成脉冲
    output logic error,                                   // 参数非法错误标志

    output logic                                            line_req_valid,      // 源行请求有效
    output logic [$clog2(MAX_SRC_H)-1:0]                    line_req_y,          // 请求的源图 y 坐标
    input  logic                                            line_req_ready,      // 外部确认该源行已准备好
    input  logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0] line_req_sel,      // 该源行对应的行缓冲槽位
    output logic                                            pixel_req_valid,     // 源像素请求有效
    output logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0] pixel_req_line_sel, // 请求像素所在的行缓冲槽位
    output logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] pixel_req_x,      // 请求的源图 x 坐标
    
    input  logic [PIXEL_W-1:0]                              pixel_rsp_data,      // 返回的源像素数据
    input  logic                                            pixel_rsp_valid,     // 返回的源像素有效
    output logic [PIXEL_W-1:0]                              pix_data,            // 输出的目标像素数据
    output logic                                            pix_valid,           // 输出目标像素有效
    input  logic                                            pix_ready,           // 下游接受目标像素
    output logic                                            row_done             // 一整行目标像素输出完成
);

    localparam int SRC_X_W    = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1; // 源图 x 坐标位宽
    localparam int SRC_Y_W    = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1; // 源图 y 坐标位宽
    localparam int DST_X_W    = $clog2(MAX_DST_W+1);                      // 目标图 x 坐标位宽
    localparam int DST_Y_W    = $clog2(MAX_DST_H+1);                      // 目标图 y 坐标位宽
    localparam int LINE_SEL_W = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;    // 行缓冲选择信号位宽
    localparam int SCALE_W    = FRAC_W + 16;                              // 定点缩放步长总位宽
    localparam logic [FRAC_W:0] HALF_STEP = (1 << (FRAC_W-1));            // 最近邻取整时使用的半步偏移

    // 最近邻缩放核心状态机：
    // 1. 根据当前目标坐标换算源坐标
    // 2. 先请求所需源行
    // 3. 再请求该行上的源像素
    // 4. 收到像素后输出给下游
    typedef enum logic [2:0] {
        S_IDLE,       // 空闲，等待 start
        S_PREP,       // 计算当前目标行对应的源行
        S_REQ_LINE,   // 请求源行
        S_REQ_PIXEL,  // 请求源像素
        S_WAIT_PIXEL, // 等待源像素返回
        S_OUT,        // 向下游输出目标像素
        S_DONE        // 结束并拉高 done 脉冲
    } state_t;

    state_t state_reg;                           // 当前状态
    state_t state_next;                          // 下一状态
    logic [DST_X_W-1:0] dst_x_reg;               // 当前目标图 x 坐标
    logic [DST_Y_W-1:0] dst_y_reg;               // 当前目标图 y 坐标
    logic [SCALE_W-1:0] scale_x_reg;             // x 方向定点缩放步长
    logic [SCALE_W-1:0] scale_y_reg;             // y 方向定点缩放步长
    logic [SCALE_W-1:0] x_pos_reg;               // 当前目标 x 对应的源图定点位置
    logic [SCALE_W-1:0] y_pos_reg;               // 当前目标 y 对应的源图定点位置
    logic [SRC_Y_W-1:0] src_y_reg;               // 当前请求的源图 y 坐标
    logic [SRC_X_W-1:0] src_x_reg;               // 当前请求的源图 x 坐标
    logic [LINE_SEL_W-1:0] active_line_sel_reg;  // 当前源行对应的行缓冲槽位
    logic [PIXEL_W-1:0] pix_data_reg;            // 输出像素寄存器
    logic pix_valid_reg;                         // 输出像素 valid 寄存器
    logic last_col;                              // 当前是否为目标行最后一列
    logic last_row;                              // 当前是否为目标图最后一行
    logic pix_fire;                              // 目标像素输出握手成功

    logic [SCALE_W-1:0] x_round_calc;            // 当前 x 定点位置加半步后的结果
    logic [SCALE_W-1:0] y_round_calc;            // 当前 y 定点位置加半步后的结果
    logic [SRC_X_W:0]   src_x_full_calc;         // 当前目标像素映射得到的源 x 坐标
    logic [SRC_Y_W:0]   src_y_full_calc;         // 当前目标像素映射得到的源 y 坐标
    logic [SCALE_W-1:0] next_x_round_calc;       // 下一个目标列加半步后的 x 结果
    logic [SCALE_W-1:0] next_y_round_calc;       // 下一目标行加半步后的 y 结果
    logic [SRC_X_W:0]   next_src_x_full_calc;    // 下一个目标列映射得到的源 x 坐标
    logic [SRC_Y_W:0]   next_src_y_full_calc;    // 下一目标行映射得到的源 y 坐标

    // 组合逻辑：
    // 1. 用定点步长计算当前/下一目标像素映射到的源坐标
    // 2. 根据握手情况给出状态跳转条件
    always_comb begin
        x_round_calc         = x_pos_reg + HALF_STEP;
        y_round_calc         = y_pos_reg + HALF_STEP;
        src_x_full_calc      = x_round_calc >> FRAC_W;
        src_y_full_calc      = y_round_calc >> FRAC_W;
        next_x_round_calc    = x_pos_reg + scale_x_reg + HALF_STEP;
        next_y_round_calc    = y_pos_reg + scale_y_reg + HALF_STEP;
        next_src_x_full_calc = next_x_round_calc >> FRAC_W;
        next_src_y_full_calc = next_y_round_calc >> FRAC_W;

        state_next = state_reg;

        case (state_reg)
            S_IDLE: begin
                if (start) begin
                    state_next = S_PREP;
                end
            end

            S_PREP: begin
                if (error) begin
                    state_next = S_DONE;
                end else begin
                    state_next = S_REQ_LINE;
                end
            end

            S_REQ_LINE: begin
                if (line_req_valid && line_req_ready) begin
                    state_next = S_REQ_PIXEL;
                end
            end

            S_REQ_PIXEL: begin
                if (pixel_req_valid) begin
                    state_next = S_WAIT_PIXEL;
                end
            end

            S_WAIT_PIXEL: begin
                if (pixel_rsp_valid) begin
                    state_next = S_OUT;
                end
            end

            S_OUT: begin
                if (pix_fire) begin
                    if (last_col && last_row) begin
                        state_next = S_DONE;
                    end else if (last_col) begin
                        state_next = S_REQ_LINE;
                    end else begin
                        state_next = S_REQ_PIXEL;
                    end
                end
            end

            S_DONE: begin
                state_next = S_IDLE;
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    assign last_col          = (dst_x_reg == dst_w - 1'b1);
    assign last_row          = (dst_y_reg == dst_h - 1'b1);
    assign pix_fire          = pix_valid && pix_ready;

    assign busy              = (state_reg != S_IDLE);
    assign line_req_valid    = (state_reg == S_REQ_LINE);
    assign line_req_y        = src_y_reg;
    assign pixel_req_valid   = (state_reg == S_REQ_PIXEL);
    assign pixel_req_line_sel = active_line_sel_reg;
    assign pixel_req_x       = src_x_reg;
    assign pix_data          = pix_data_reg;
    assign pix_valid         = pix_valid_reg;

    // 时序主过程：
    // 1. 维护目标坐标推进
    // 2. 计算并锁存源坐标
    // 3. 处理像素返回与输出握手
    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg           <= S_IDLE;
            dst_x_reg           <= '0;
            dst_y_reg           <= '0;
            scale_x_reg         <= '0;
            scale_y_reg         <= '0;
            x_pos_reg           <= '0;
            y_pos_reg           <= '0;
            src_y_reg           <= '0;
            src_x_reg           <= '0;
            active_line_sel_reg <= '0;
            pix_data_reg        <= '0;
            pix_valid_reg       <= 1'b0;
            done                <= 1'b0;
            error               <= 1'b0;
            row_done            <= 1'b0;
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

                S_PREP: begin
                    if (!error) begin
                        if (src_y_full_calc >= src_h) begin
                            src_y_reg <= src_h - 1'b1;
                        end else begin
                            src_y_reg <= src_y_full_calc[SRC_Y_W-1:0];
                        end
                    end
                end

                S_REQ_LINE: begin
                    if (line_req_valid && line_req_ready) begin
                        active_line_sel_reg <= line_req_sel;

                        if (src_x_full_calc >= src_w) begin
                            src_x_reg <= src_w - 1'b1;
                        end else begin
                            src_x_reg <= src_x_full_calc[SRC_X_W-1:0];
                        end
                    end
                end

                S_REQ_PIXEL: begin
                    // 像素请求信号在该状态下直接由组合逻辑给出，无需额外寄存。
                end

                S_WAIT_PIXEL: begin
                    if (pixel_rsp_valid) begin
                        pix_data_reg  <= pixel_rsp_data;
                        pix_valid_reg <= 1'b1;
                    end
                end

                S_OUT: begin
                    if (pix_fire) begin
                        pix_valid_reg <= 1'b0;

                        if (last_col) begin
                            row_done <= 1'b1;

                            if (!last_row) begin
                                dst_x_reg <= '0;
                                dst_y_reg <= dst_y_reg + 1'b1;
                                x_pos_reg <= '0;
                                y_pos_reg <= y_pos_reg + scale_y_reg;

                                if (next_src_y_full_calc >= src_h) begin
                                    src_y_reg <= src_h - 1'b1;
                                end else begin
                                    src_y_reg <= next_src_y_full_calc[SRC_Y_W-1:0];
                                end
                            end
                        end else begin
                            dst_x_reg <= dst_x_reg + 1'b1;
                            x_pos_reg <= x_pos_reg + scale_x_reg;

                            if (next_src_x_full_calc >= src_w) begin
                                src_x_reg <= src_w - 1'b1;
                            end else begin
                                src_x_reg <= next_src_x_full_calc[SRC_X_W-1:0];
                            end
                        end
                    end
                end

                S_DONE: begin
                    pix_valid_reg <= 1'b0;
                    done          <= !error;
                end

                default: begin
                    state_reg <= S_IDLE;
                end
            endcase
        end
    end

endmodule
