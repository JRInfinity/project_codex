`timescale 1ns/1ps

// 模块职责：
// 1. 作为整条缩放链路的控制器，串接 DDR 读、源行缓存、缩放 core、行缓冲和 DDR 写回。
// 2. 在任务启动后先把前 LINE_NUM 条源行装入缓存，再启动 core。
// 3. 对 bilinear 这类需要两条相邻源行的 core，负责判断请求的两条行是否都已就绪。
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

    // 输出状态信号，表示当前控制器的状态
    output logic              busy,
    output logic              done,
    output logic              error,

    // DDR 读接口：控制器通过这个接口启动 DDR 读，并监视读的状态
    output logic              read_start, // 启动 DDR 读的信号，配合 read_addr 和 read_byte_count 指定读什么数据
    output logic [ADDR_W-1:0] read_addr, // DDR 读的地址
    output logic [31:0]       read_byte_count, // DDR 读的字节数
    input  logic              read_busy, // DDR 读正在进行中
    input  logic              read_done, // DDR 读完成信号
    input  logic              read_error, // DDR 读错误信号

    // 行缓冲装载接口：控制器通过这个接口把 DDR 读回来的数据装入行缓冲，并监视装载状态
    output logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0] lb_load_sel, // 行缓冲装载时指定装载到哪个缓存槽
    output logic                                              lb_load_start, // 行缓冲装载启动信号
    output logic [$clog2(MAX_SRC_W+1)-1:0]                   lb_load_pixel_count,// 行缓冲装载的像素数 == 源图宽
    input  logic                                             lb_load_busy, // 行缓冲装载正在进行中
    input  logic                                             lb_load_done, // 行缓冲装载完成
    input  logic                                             lb_load_error, // 行缓冲装载错误

    // core 接口：控制器通过这个接口启动 core 进行缩放计算，并监视 core 的状态；同时响应 core 请求的行数据
    output logic                                             core_start, // 启动 core 进行缩放计算
    input  logic                                             core_busy, // core 正在进行缩放计算
    input  logic                                             core_done, // core 缩放计算完成
    input  logic                                             core_error, // core 缩放计算错误
    input  logic                                             line_req_valid, // core 请求的行号有效信号：需要提供 line_req_y 指定的行数据
    input  logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] line_req_y, // core 请求的行号
    output logic                                             line_req_ready, // 行数据准备就绪信号：当 core 请求的行数据已经准备好时置高，配合 line_req_sel 指明是缓存中的哪一行
    output logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0] line_req_sel, // 当 line_req_ready 置高时，指明 core 请求的行数据来自缓存中的哪一行
    input  logic                                             row_done, // 行缓冲输出一行数据完成信号

    // 行缓冲输出接口：控制器通过这个接口启动行缓冲输出数据，并监视输出状态
    output logic                           row_start, // 启动行缓冲输出一行数据的信号
    output logic [$clog2(MAX_DST_W+1)-1:0] row_pixel_count, // 行缓冲输出的像素数 == 目标图宽
    input  logic                           row_busy, // 行缓冲正在输出数据
    input  logic                           row_done_buf, // 行缓冲输出完成信号
    input  logic                           row_error, // 行缓冲输出错误信号
    output logic                           row_out_start, // 启动行缓冲输出数据的信号
    input  logic                           row_out_done, // 行缓冲输出数据完成信号

    // DDR 写回接口：控制器通过这个接口把行缓冲输出的数据写回 DDR，并监视写回状态
    output logic              write_start, // 启动 DDR 写回的信号
    output logic [ADDR_W-1:0] write_addr, // DDR 写回的地址
    output logic [31:0]       write_byte_count, // DDR 写回的字节数
    input  logic              write_busy, // DDR 写回正在进行中
    input  logic              write_done, // DDR 写回完成信号
    input  logic              write_error // DDR 写回错误信号
);

    localparam int SRC_Y_W    = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1; // 表示源行号的位宽
    localparam int DST_Y_W    = $clog2(MAX_DST_H+1); // 表示目标行号的位宽，注意这里是 MAX_DST_H+1，因为可能需要表示 dst_h 这个值本身（当 dst_h == MAX_DST_H 时，dst_h 就是一个合法的行号，用来表示最后一行）
    localparam int LINE_SEL_W = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1; // 表示缓存行选择的位宽

    typedef enum logic [1:0] {
        S_IDLE,
        S_RUN,
        S_DONE,
        S_ERROR
    } state_t;

    state_t state_reg;
    state_t state_next;

    logic [ADDR_W-1:0] src_base_addr_reg;
    logic [ADDR_W-1:0] dst_base_addr_reg;
    logic [ADDR_W-1:0] src_stride_reg;
    logic [ADDR_W-1:0] dst_stride_reg;
    logic [$clog2(MAX_SRC_W+1)-1:0] src_w_reg;
    logic [$clog2(MAX_SRC_H+1)-1:0] src_h_reg;
    logic [$clog2(MAX_DST_W+1)-1:0] dst_w_reg;
    logic [$clog2(MAX_DST_H+1)-1:0] dst_h_reg;

    logic [DST_Y_W-1:0] row_started_count_reg;
    logic [DST_Y_W-1:0] row_written_count_reg;
    logic               pending_row_write_reg;
    logic               core_done_seen_reg;

    logic [LINE_NUM-1:0] cache_valid_reg;
    logic [SRC_Y_W-1:0]  cache_y_reg [0:LINE_NUM-1];

    logic               line_load_pending_reg;
    logic [SRC_Y_W-1:0] line_load_y_reg;
    logic [LINE_SEL_W-1:0] line_load_sel_reg;
    logic [SRC_Y_W-1:0] prefill_limit_reg; // 能够预填充的数目，最开始就定死
    logic [SRC_Y_W-1:0] prefill_next_y_reg;
    logic [LINE_SEL_W-1:0] replace_sel_reg;

    logic               cache_hit0;
    logic               cache_hit1;
    logic [LINE_SEL_W-1:0] cache_hit_sel0;
    logic [SRC_Y_W-1:0] line_req_y1;
    logic               line_pair_ready;
    logic               prefill_done;
    logic               launch_first_row;
    logic               launch_next_row;
    logic               launch_write_row;
    logic               launch_prefill_load;
    logic               launch_req_load;
    logic               launch_line_load;
    logic               launch_core;
    logic               final_write_done;
    logic [SRC_Y_W-1:0] load_issue_y;
    logic [LINE_SEL_W-1:0] load_issue_sel;

    integer cache_idx_comb;
    integer cache_idx_ff;

    // 组合逻辑：
    // 1. 顶层状态转移。
    // 2. 查询请求的两条源行是否都已经在缓存中。
    always_comb begin
        state_next = state_reg;

        case (state_reg)
            S_IDLE: begin
                if (start) begin
                    if ((src_w == 0) || (src_h == 0) || (dst_w == 0) || (dst_h == 0)) begin
                        state_next = S_ERROR;
                    end else begin
                        state_next = S_RUN;
                    end
                end
            end

            S_RUN: begin
                if (read_error || lb_load_error || core_error || row_error || write_error) begin
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

    always_comb begin
        cache_hit0     = 1'b0;
        cache_hit1     = 1'b0;
        cache_hit_sel0 = '0;
        
        // 
        for (cache_idx_comb = 0; cache_idx_comb < LINE_NUM; cache_idx_comb++) begin
            if (cache_valid_reg[cache_idx_comb] && (cache_y_reg[cache_idx_comb] == line_req_y)) begin
                cache_hit0     = 1'b1;
                cache_hit_sel0 = LINE_SEL_W'(cache_idx_comb);
            end

            if (cache_valid_reg[cache_idx_comb] && (cache_y_reg[cache_idx_comb] == line_req_y1)) begin
                cache_hit1     = 1'b1;
            end
        end
    end

    assign line_req_y1 = (line_req_y + 1'b1 >= src_h_reg) ? (src_h_reg - 1'b1) : (line_req_y + 1'b1);
    assign line_pair_ready = cache_hit0 && cache_hit1;
    assign prefill_done    = (prefill_next_y_reg >= prefill_limit_reg) && !line_load_pending_reg;

    assign launch_first_row = (state_reg == S_RUN) &&
        prefill_done &&
        (row_started_count_reg == 0) &&
        !row_busy;

    assign launch_next_row = (state_reg == S_RUN) &&
        write_done &&
        (row_started_count_reg < dst_h_reg);

    assign launch_write_row = (state_reg == S_RUN) &&
        pending_row_write_reg &&
        !write_busy;

    // 预填充的优先级高于按需换入，因为按需换入是为了满足 core 的行请求，而 core 的启动条件之一就是预填充完成。
    assign launch_prefill_load = (state_reg == S_RUN) &&
        (prefill_next_y_reg < prefill_limit_reg) &&
        !line_load_pending_reg &&
        !read_busy &&
        !lb_load_busy;

    // 按需换入的条件：core 需要的行不在缓存里；当前没有正在进行的行装载；DDR 读和行缓冲都空闲。
    assign launch_req_load = (state_reg == S_RUN) &&
        prefill_done &&
        line_req_valid &&
        !line_pair_ready &&
        !line_load_pending_reg &&
        !read_busy &&
        !lb_load_busy;

    assign launch_line_load = launch_prefill_load || launch_req_load;

    assign launch_core = (state_reg == S_RUN) &&
        prefill_done &&
        (row_started_count_reg == 0) &&
        !core_busy &&
        !core_done_seen_reg;

    assign final_write_done = (state_reg == S_RUN) &&
        write_done &&
        core_done_seen_reg &&
        (row_written_count_reg == dst_h_reg - 1'b1);

    assign load_issue_y = launch_prefill_load ? prefill_next_y_reg :
        (!cache_hit0 ? line_req_y : line_req_y1); // 这次去DDR读哪一行
        // 如果是预填充，就按照顺序来；如果是按需换入，就优先把缺的那一行换入

    assign load_issue_sel = launch_prefill_load ? LINE_SEL_W'(prefill_next_y_reg) : replace_sel_reg; // 从DDR都回来的东西放到哪一个缓存槽
    // 预填充时，按照行号顺序放；按需换入时，轮询替换

    assign busy  = (state_reg == S_RUN);
    assign done  = (state_reg == S_DONE);
    assign error = (state_reg == S_ERROR);

    assign read_start      = launch_line_load;
    assign read_addr       = src_base_addr_reg + load_issue_y * src_stride_reg;
    assign read_byte_count = src_w_reg;

    assign lb_load_start       = launch_line_load;
    assign lb_load_sel         = load_issue_sel;
    assign lb_load_pixel_count = src_w_reg;

    assign core_start      = launch_core;
    assign line_req_ready  = (state_reg == S_RUN) && line_pair_ready;
    assign line_req_sel    = cache_hit_sel0;

    assign row_start       = launch_first_row || launch_next_row;
    assign row_pixel_count = dst_w_reg;
    assign row_out_start   = launch_write_row;

    assign write_start      = launch_write_row;
    assign write_addr       = dst_base_addr_reg + row_written_count_reg * dst_stride_reg;
    assign write_byte_count = dst_w_reg;

    // 时序过程：
    // 1. 锁存任务配置。
    // 2. 推进预装缓存、按需换入和目标行写回计数。
    always_ff @(posedge clk) begin
        if (sys_rst) begin
            state_reg             <= S_IDLE;
            src_base_addr_reg     <= '0;
            dst_base_addr_reg     <= '0;
            src_stride_reg        <= '0;
            dst_stride_reg        <= '0;
            src_w_reg             <= '0;
            src_h_reg             <= '0;
            dst_w_reg             <= '0;
            dst_h_reg             <= '0;
            row_started_count_reg <= '0;
            row_written_count_reg <= '0;
            pending_row_write_reg <= 1'b0;
            core_done_seen_reg    <= 1'b0;
            cache_valid_reg       <= '0;
            line_load_pending_reg <= 1'b0;
            line_load_y_reg       <= '0;
            line_load_sel_reg     <= '0;
            prefill_limit_reg     <= '0;
            prefill_next_y_reg    <= '0;
            replace_sel_reg       <= '0;
            for (cache_idx_ff = 0; cache_idx_ff < LINE_NUM; cache_idx_ff++) begin
                cache_y_reg[cache_idx_ff] <= '0;
            end
        end else begin
            state_reg <= state_next;

            case (state_reg)
                S_IDLE: begin
                    row_started_count_reg <= '0;
                    row_written_count_reg <= '0;
                    pending_row_write_reg <= 1'b0;
                    core_done_seen_reg    <= 1'b0;
                    cache_valid_reg       <= '0;
                    line_load_pending_reg <= 1'b0;
                    line_load_y_reg       <= '0;
                    line_load_sel_reg     <= '0;
                    prefill_next_y_reg    <= '0;
                    replace_sel_reg       <= '0;
                    for (cache_idx_ff = 0; cache_idx_ff < LINE_NUM; cache_idx_ff++) begin
                        cache_y_reg[cache_idx_ff] <= '0;
                    end

                    if (start) begin
                        src_base_addr_reg <= src_base_addr;
                        dst_base_addr_reg <= dst_base_addr;
                        src_stride_reg    <= src_stride;
                        dst_stride_reg    <= dst_stride;
                        src_w_reg         <= src_w;
                        src_h_reg         <= src_h;
                        dst_w_reg         <= dst_w;
                        dst_h_reg         <= dst_h;
                        prefill_limit_reg <= (src_h < LINE_NUM) ? src_h[SRC_Y_W-1:0] : SRC_Y_W'(LINE_NUM);
                    end
                end

                S_RUN: begin
                    if (launch_first_row) begin
                        row_started_count_reg <= row_started_count_reg + 1'b1;
                    end

                    if (launch_next_row) begin
                        row_started_count_reg <= row_started_count_reg + 1'b1;
                    end

                    if (launch_line_load) begin
                        line_load_pending_reg             <= 1'b1;
                        line_load_y_reg                   <= load_issue_y;
                        line_load_sel_reg                 <= load_issue_sel;
                        cache_valid_reg[load_issue_sel]   <= 1'b0;

                        if (launch_prefill_load) begin
                            prefill_next_y_reg <= prefill_next_y_reg + 1'b1;
                        end else begin
                            replace_sel_reg <= replace_sel_reg + 1'b1;
                        end
                    end

                    if (lb_load_done) begin
                        line_load_pending_reg               <= 1'b0;
                        cache_valid_reg[line_load_sel_reg]  <= 1'b1;
                        cache_y_reg[line_load_sel_reg]      <= line_load_y_reg;
                    end

                    if (row_done_buf) begin
                        pending_row_write_reg <= 1'b1;
                    end

                    if (launch_write_row) begin
                        pending_row_write_reg <= 1'b0;
                    end

                    if (write_done) begin
                        row_written_count_reg <= row_written_count_reg + 1'b1;
                    end

                    if (core_done) begin
                        core_done_seen_reg <= 1'b1;
                    end
                end

                S_DONE: begin
                    // 单拍完成脉冲
                end

                S_ERROR: begin
                    // 单拍错误脉冲
                end

                default: begin
                    state_reg <= S_IDLE;
                end
            endcase
        end
    end

    logic unused_signals;
    assign unused_signals = &{1'b0, PIXEL_W'(0), read_done, row_done, row_out_done};

endmodule
