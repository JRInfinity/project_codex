// 模块职责：
// 1. 将 PIXEL_W 位宽的像素流打包成 DATA_W 位宽的数据字
// 2. 根据 task_addr 指定的首地址偏移填充首个数据字
// 3. 在最后一个数据字输出与有效字节匹配的 strobe 掩码
module pixel_packer #(
    parameter int DATA_W  = 32, // 输出数据字位宽
    parameter int ADDR_W  = 32, // 地址位宽
    parameter int PIXEL_W = 8   // 输入像素位宽
) (
    input  logic                  clk,             // 打包逻辑时钟
    input  logic                  sys_rst,         // 高电平复位
    input  logic                  task_start,      // 启动一次打包任务
    input  logic [ADDR_W-1:0]     task_addr,       // 任务起始地址，用于计算首字节偏移
    input  logic [31:0]           task_byte_count, // 本次任务总字节数
    input  logic [PIXEL_W-1:0]    pixel_data,      // 输入像素数据
    input  logic                  pixel_valid,     // 输入像素有效
    output logic                  pixel_ready,     // 当前可接受输入像素
    output logic [DATA_W-1:0]     word_data,       // 打包后的数据字
    output logic [(DATA_W/8)-1:0] word_strb,       // 数据字按字节有效掩码
    output logic                  word_valid,      // 输出数据字有效
    input  logic                  word_ready       // 下游接受当前数据字
);

    localparam int BYTE_W   = DATA_W / 8;                         // 一个数据字包含的字节数
    localparam int OFFSET_W = (BYTE_W > 1) ? $clog2(BYTE_W) : 1; // 字内字节偏移位宽
    localparam int COUNT_W  = 33;                                 // 字节计数器位宽

    logic               task_active_reg;       // 当前任务处于活动状态
    logic [COUNT_W-1:0] bytes_remaining_reg;   // 剩余待打包字节数
    logic [OFFSET_W:0]  bytes_in_word_reg;     // 当前数据字还需填入的字节数
    logic [OFFSET_W:0]  first_word_bytes_calc; // 首个数据字可写入的有效字节数
    logic [OFFSET_W-1:0] byte_idx_reg;         // 当前写入到数据字中的字节索引
    logic [DATA_W-1:0]  word_data_reg;         // 数据字寄存器
    logic [BYTE_W-1:0]  word_strb_reg;         // 数据字 strobe 寄存器
    logic               word_valid_reg;        // 数据字 valid 寄存器
    logic               pixel_fire;            // 当前拍成功接收一个像素
    logic               word_fire;             // 当前拍成功送出一个数据字
    logic [OFFSET_W:0]  next_word_bytes_calc;  // 下一数据字需要填入的字节数

    // 当前实现按 8bit 像素打包，因此加入显式参数保护。
    initial begin
        if (DATA_W % 8 != 0) $error("pixel_packer requires DATA_W to be byte aligned.");
        if (PIXEL_W != 8) $error("Current pixel_packer implementation expects PIXEL_W == 8.");
    end

    assign first_word_bytes_calc = BYTE_W - task_addr[OFFSET_W-1:0];
    assign next_word_bytes_calc  = (bytes_remaining_reg > BYTE_W) ? BYTE_W : bytes_remaining_reg[OFFSET_W:0];

    assign word_data   = word_data_reg;
    assign word_strb   = word_strb_reg;
    assign word_valid  = word_valid_reg;
    assign pixel_ready = task_active_reg && !word_valid_reg && (bytes_in_word_reg != 0);
    assign pixel_fire  = pixel_valid && pixel_ready;
    assign word_fire   = word_valid_reg && word_ready;

    // 时序主过程：
    // 1. 管理一帧打包任务的生命周期
    // 2. 接收像素并写入当前数据字
    // 3. 在数据字填满或任务结束时输出一个 word
    always_ff @(posedge clk) begin
        if (sys_rst) begin
            task_active_reg     <= 1'b0;
            bytes_remaining_reg <= '0;
            bytes_in_word_reg   <= '0;
            byte_idx_reg        <= '0;
            word_data_reg       <= '0;
            word_strb_reg       <= '0;
            word_valid_reg      <= 1'b0;
        end else begin
            if (task_start) begin
                task_active_reg     <= 1'b1;
                bytes_remaining_reg <= task_byte_count;
                bytes_in_word_reg   <= (first_word_bytes_calc > task_byte_count) ? task_byte_count[OFFSET_W:0] : first_word_bytes_calc;
                byte_idx_reg        <= task_addr[OFFSET_W-1:0];
                word_data_reg       <= '0;
                word_strb_reg       <= '0;
                word_valid_reg      <= 1'b0;
            end else begin
                if (pixel_fire) begin
                    word_data_reg[byte_idx_reg*8 +: PIXEL_W] <= pixel_data;
                    word_strb_reg[byte_idx_reg] <= 1'b1;
                    bytes_remaining_reg <= bytes_remaining_reg - 1'b1;
                    bytes_in_word_reg   <= bytes_in_word_reg - 1'b1;

                    if ((bytes_in_word_reg == 1) || (bytes_remaining_reg == 1)) begin
                        word_valid_reg <= 1'b1;
                    end else begin
                        byte_idx_reg <= byte_idx_reg + 1'b1;
                    end
                end

                if (word_fire) begin
                    word_valid_reg <= 1'b0;
                    word_data_reg  <= '0;
                    word_strb_reg  <= '0;

                    if (bytes_remaining_reg == 0) begin
                        task_active_reg   <= 1'b0;
                        bytes_in_word_reg <= '0;
                        byte_idx_reg      <= '0;
                    end else begin
                        bytes_in_word_reg <= next_word_bytes_calc;
                        byte_idx_reg      <= '0;
                    end
                end
            end
        end
    end

endmodule
