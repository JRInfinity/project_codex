// 模块职责：
// 1. 先把一整行缩放结果写入内部行缓存
// 2. 再按输出请求顺序把这一行像素重新送出
// 3. 为写回模块提供按行缓存和顺序回放能力
module row_out_buffer #(
    parameter int PIXEL_W   = 8,
    parameter int MAX_DST_W = 600
) (
    input  logic clk,                               // 行输出缓存时钟
    input  logic sys_rst,                           // 高有效复位

    input  logic                           row_start,       // 启动接收一整行结果
    input  logic [$clog2(MAX_DST_W+1)-1:0] row_pixel_count, // 当前行的像素总数
    output logic                           row_busy,        // 行缓存当前忙
    output logic                           row_done,        // 一整行写入缓存完成
    output logic                           row_error,       // 当前行处理错误

    input  logic [PIXEL_W-1:0]             in_data,         // 写入缓存的像素数据
    input  logic                           in_valid,        // 输入像素有效
    output logic                           in_ready,        // 缓存可以接受像素

    input  logic                           out_start,       // 启动把该行重新输出
    output logic [PIXEL_W-1:0]             out_data,        // 输出像素数据
    output logic                           out_valid,       // 输出像素有效
    input  logic                           out_ready,       // 下游接受当前像素
    output logic                           out_done         // 当前行已全部输出完成
);

    localparam int COUNT_W = $clog2(MAX_DST_W+1);
    localparam int ADDR_W  = (MAX_DST_W > 1) ? $clog2(MAX_DST_W) : 1;

    // 行缓存状态机：装载一行、等待输出启动、再顺序排空。
    typedef enum logic [1:0] {
        S_IDLE,
        S_FILL,
        S_READY,
        S_DRAIN
    } state_t;

    state_t state_reg;                   // 当前状态
    state_t state_next;                  // 下一状态

    logic [PIXEL_W-1:0] mem_reg [0:MAX_DST_W-1]; // 一整行输出像素缓存

    logic [COUNT_W-1:0] row_pixel_count_reg; // 当前行应缓存的像素数
    logic [COUNT_W-1:0] wr_ptr_reg;          // 行缓存写指针
    logic [COUNT_W-1:0] rd_ptr_reg;          // 行缓存读指针
    logic [PIXEL_W-1:0] out_data_reg;        // 输出像素寄存器
    logic               out_valid_reg;       // 输出 valid 寄存器

    logic in_fire;                           // 当前拍成功接收一个输入像素
    logic out_fire;                          // 当前拍成功输出一个像素
    logic fill_done;                         // 一整行像素已经收满
    logic drain_done;                        // 一整行像素已经吐完
    logic [ADDR_W-1:0] rd_ptr_next_calc;     // 下一拍读指针值

    // 组合状态转移。
    always_comb begin
        state_next = state_reg;

        case (state_reg)
            S_IDLE: begin
                if (row_start && (row_pixel_count != 0)) begin
                    state_next = S_FILL;
                end
            end

            S_FILL: begin
                if (row_error) begin
                    state_next = S_IDLE;
                end else if (fill_done) begin
                    state_next = S_READY;
                end
            end

            S_READY: begin
                if (out_start && (row_pixel_count_reg != 0)) begin
                    state_next = S_DRAIN;
                end
            end

            S_DRAIN: begin
                if (drain_done) begin
                    state_next = S_IDLE;
                end
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    assign in_fire   = in_valid && in_ready;
    assign out_fire  = out_valid && out_ready;
    assign fill_done = (wr_ptr_reg == row_pixel_count_reg) && (row_pixel_count_reg != 0);
    assign drain_done = out_fire && (rd_ptr_reg == row_pixel_count_reg - 1'b1);
    assign rd_ptr_next_calc = rd_ptr_reg[ADDR_W-1:0] + 1'b1;

    assign row_busy  = (state_reg == S_FILL) || (state_reg == S_READY) || (state_reg == S_DRAIN);
    assign in_ready  = (state_reg == S_FILL) && (wr_ptr_reg < row_pixel_count_reg) && !row_error;
    assign out_data  = out_data_reg;
    assign out_valid = out_valid_reg;

    // 时序主过程负责内存写入、输出指针推进以及 done/error 脉冲生成。
    always_ff @(posedge clk) begin
        if (sys_rst) begin
            state_reg          <= S_IDLE;
            row_pixel_count_reg <= '0;
            wr_ptr_reg         <= '0;
            rd_ptr_reg         <= '0;
            out_data_reg       <= '0;
            out_valid_reg      <= 1'b0;
            row_done           <= 1'b0;
            row_error          <= 1'b0;
            out_done           <= 1'b0;
        end else begin
            state_reg     <= state_next;
            row_done      <= 1'b0;
            out_done      <= 1'b0;

            case (state_reg)
                S_IDLE: begin
                    out_valid_reg <= 1'b0;
                    row_error     <= 1'b0;
                    wr_ptr_reg    <= '0;
                    rd_ptr_reg    <= '0;

                    if (row_start) begin
                        row_pixel_count_reg <= row_pixel_count;
                        if ((row_pixel_count == 0) || (row_pixel_count > MAX_DST_W)) begin
                            row_error <= 1'b1;
                        end
                    end
                end

                S_FILL: begin
                    if (in_fire) begin
                        mem_reg[wr_ptr_reg[ADDR_W-1:0]] <= in_data;
                        wr_ptr_reg <= wr_ptr_reg + 1'b1;
                    end

                    if (fill_done) begin
                        row_done <= 1'b1;
                    end
                end

                S_READY: begin
                    rd_ptr_reg <= '0;
                    if (out_start && (row_pixel_count_reg != 0)) begin
                        out_data_reg  <= mem_reg[0];
                        out_valid_reg <= 1'b1;
                    end
                end

                S_DRAIN: begin
                    if (out_fire) begin
                        if (rd_ptr_reg == row_pixel_count_reg - 1'b1) begin
                            out_valid_reg <= 1'b0;
                            out_done      <= 1'b1;
                        end else begin
                            rd_ptr_reg    <= rd_ptr_reg + 1'b1;
                            out_data_reg  <= mem_reg[rd_ptr_next_calc];
                            out_valid_reg <= 1'b1;
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
