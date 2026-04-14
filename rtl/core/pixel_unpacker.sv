// 模块职责：
// 1. 在 core_clk 域从异步 FIFO 读取完整的 DATA_W 位数据字
// 2. 根据 task_addr 指定的首地址偏移跳过首个数据字中的无效字节
// 3. 根据 task_byte_count 裁掉最后一个数据字中的无效尾部字节
// 4. 按像素流接口输出有效字节，并在任务结束时给出完成或错误脉冲
`timescale 1ns/1ps

module pixel_unpacker #(
    parameter int DATA_W  = 32, // 上游 FIFO 数据位宽
    parameter int ADDR_W  = 32, // 地址位宽
    parameter int PIXEL_W = 8   // 输出像素位宽
) (
    input  logic               core_clk,            // core 域时钟
    input  logic               sys_rst,             // 高电平复位
    input  logic               task_start,          // 启动一次拆包任务
    input  logic [ADDR_W-1:0]  task_addr,           // 任务起始地址，用于计算首字节偏移
    input  logic [31:0]        task_byte_count,     // 本次任务需要输出的总字节数
    input  logic               reader_status_valid, // 上游读引擎状态事件有效
    input  logic               reader_done_evt,     // 上游读引擎完成事件
    input  logic               reader_error_evt,    // 上游读引擎错误事件
    output logic               fifo_rd_en,          // 从 FIFO 读取一个完整数据字
    input  logic [DATA_W-1:0]  fifo_rd_data,        // FIFO 返回的数据字
    input  logic               fifo_empty,          // FIFO 当前为空
    input  logic               fifo_underflow,      // FIFO 下溢告警
    output logic [PIXEL_W-1:0] pixel_data,          // 拆包后的像素数据
    output logic               pixel_valid,         // 输出像素有效
    input  logic               pixel_ready,         // 下游接受当前像素
    output logic               task_done_pulse,     // 本次任务成功完成脉冲
    output logic               task_error_pulse,    // 本次任务错误结束脉冲
    output logic               task_error_flag      // 本次任务内部错误锁存标志
);

    localparam int BYTE_W   = DATA_W / 8;                         // 一个数据字包含的字节数
    localparam int OFFSET_W = (BYTE_W > 1) ? $clog2(BYTE_W) : 1; // 字内字节偏移位宽
    localparam int COUNT_W  = 33;                                 // 字节计数器位宽

    logic               task_active_reg;           // 当前任务处于活动状态
    logic [COUNT_W-1:0] bytes_remaining_reg;       // 剩余待输出的有效字节数
    logic [OFFSET_W-1:0] first_offset_reg;         // 首个数据字中的起始字节偏移
    logic               first_word_reg;            // 下一次装载的是否仍是首个数据字
    logic               reader_done_seen_reg;      // 已收到上游 reader done 事件
    logic [DATA_W-1:0]  current_word_reg;          // 当前正在拆包的数据字
    logic               current_word_valid_reg;    // 当前数据字内仍有可输出字节
    logic [OFFSET_W-1:0] current_byte_idx_reg;     // 当前输出到数据字中的第几个字节
    logic [OFFSET_W:0]  current_valid_bytes_reg;   // 当前数据字剩余有效字节数
    logic               load_new_word;             // 需要从 FIFO 装载新数据字
    logic               pixel_fire;                // 当前拍成功输出一个像素
    logic [OFFSET_W-1:0] next_word_offset_calc;    // 下一次装载数据字时的起始字节偏移
    logic [COUNT_W-1:0] next_word_valid_bytes_calc;// 下一次装载数据字时的有效字节数
    logic               terminal_done_calc;        // 当前是否满足成功结束条件
    logic               terminal_error_calc;       // 当前是否满足错误结束条件

    // 当前实现按 8bit 像素拆包，因此加入显式参数保护。
    initial begin
        if (DATA_W % 8 != 0) $error("pixel_unpacker requires DATA_W to be byte aligned.");
        if (PIXEL_W != 8) $error("Current pixel_unpacker implementation expects PIXEL_W == 8.");
    end

    assign load_new_word = task_active_reg && !current_word_valid_reg && (bytes_remaining_reg != 0) && !fifo_empty;
    assign fifo_rd_en    = load_new_word;
    assign pixel_valid   = current_word_valid_reg;
    assign pixel_data    = current_word_reg[current_byte_idx_reg*8 +: PIXEL_W];
    assign pixel_fire    = pixel_valid && pixel_ready;

    // 组合预计算：
    // 1. 给出下一次装载数据字时的起始偏移
    // 2. 计算当前数据字中实际有效的字节数量
    // 3. 给出 done/error 的终止条件
    always_comb begin
        next_word_offset_calc      = first_word_reg ? first_offset_reg : '0;
        next_word_valid_bytes_calc = BYTE_W - next_word_offset_calc;
        if (next_word_valid_bytes_calc > bytes_remaining_reg) next_word_valid_bytes_calc = bytes_remaining_reg;

        terminal_done_calc = task_active_reg && reader_done_seen_reg && (bytes_remaining_reg == 0) && !current_word_valid_reg;
        terminal_error_calc = task_active_reg && task_error_flag && !current_word_valid_reg &&
                              ((bytes_remaining_reg == 0) || fifo_empty);
    end

    // 时序主过程：
    // 1. 管理任务生命周期
    // 2. 从 FIFO 装载完整数据字
    // 3. 按字节拆出像素并驱动流接口
    always_ff @(posedge core_clk) begin
        if (sys_rst) begin
            task_active_reg         <= 1'b0;
            bytes_remaining_reg     <= '0;
            first_offset_reg        <= '0;
            first_word_reg          <= 1'b0;
            reader_done_seen_reg    <= 1'b0;
            current_word_reg        <= '0;
            current_word_valid_reg  <= 1'b0;
            current_byte_idx_reg    <= '0;
            current_valid_bytes_reg <= '0;
            task_done_pulse         <= 1'b0;
            task_error_pulse        <= 1'b0;
            task_error_flag         <= 1'b0;
        end else begin
            task_done_pulse  <= 1'b0;
            task_error_pulse <= 1'b0;

            if (task_start) begin
                task_active_reg         <= 1'b1;
                bytes_remaining_reg     <= task_byte_count;
                first_offset_reg        <= task_addr[OFFSET_W-1:0];
                first_word_reg          <= 1'b1;
                reader_done_seen_reg    <= 1'b0;
                current_word_reg        <= '0;
                current_word_valid_reg  <= 1'b0;
                current_byte_idx_reg    <= '0;
                current_valid_bytes_reg <= '0;
                task_error_flag         <= 1'b0;
            end

            if (reader_status_valid && reader_done_evt) reader_done_seen_reg <= 1'b1;
            if (reader_status_valid && reader_error_evt) begin
                task_error_flag <= 1'b1;
            end

            if (fifo_underflow) task_error_flag <= 1'b1;

            if (reader_done_seen_reg && (bytes_remaining_reg != 0) && !current_word_valid_reg && fifo_empty) begin
                task_error_flag <= 1'b1;
            end

            if (load_new_word) begin
                current_word_reg        <= fifo_rd_data;
                current_word_valid_reg  <= (next_word_valid_bytes_calc != 0);
                current_byte_idx_reg    <= next_word_offset_calc;
                current_valid_bytes_reg <= next_word_valid_bytes_calc[OFFSET_W:0];
                first_word_reg          <= 1'b0;
            end

            if (pixel_fire) begin
                bytes_remaining_reg <= bytes_remaining_reg - 1'b1;
                if (current_valid_bytes_reg == 1) begin
                    current_word_valid_reg  <= 1'b0;
                    current_valid_bytes_reg <= '0;
                end else begin
                    current_byte_idx_reg    <= current_byte_idx_reg + 1'b1;
                    current_valid_bytes_reg <= current_valid_bytes_reg - 1'b1;
                end
            end

            if (terminal_done_calc) begin
                task_done_pulse <= 1'b1;
                task_active_reg <= 1'b0;
                task_error_flag <= 1'b0;
            end else if (terminal_error_calc) begin
                task_error_pulse <= 1'b1;
                task_active_reg  <= 1'b0;
            end
        end
    end

endmodule
