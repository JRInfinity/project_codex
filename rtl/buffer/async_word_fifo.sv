// 模块职责：
// 1. 在写时钟域和读时钟域之间搬运完整数据字
// 2. 综合时优先实例化 Xilinx `xpm_fifo_async`
// 3. 仿真时提供基于 queue 的行为级回退实现
// 4. 对外暴露满、近满、空、溢出和下溢状态
module async_word_fifo #(
    parameter int DATA_W             = 32,
    parameter int DEPTH              = 64,
    parameter int ALMOST_FULL_MARGIN = 4
) (
    input  logic wr_clk,                          // 写时钟
    input  logic sys_rst,                         // 共享高有效复位
    input  logic wr_en,                           // 写使能
    input  logic [DATA_W-1:0] wr_data,            // 写入 FIFO 的整 word 数据
    output logic full,                            // FIFO 已满
    output logic almost_full,                     // FIFO 接近满，用于上游回压
    output logic [$clog2(DEPTH+1)-1:0] wr_count,  // 写侧看到的当前占用
    output logic overflow,                        // 满时继续写导致的溢出
    input  logic rd_clk,                          // 读时钟
    input  logic rd_en,                           // 读使能
    output logic [DATA_W-1:0] rd_data,            // 读出的整 word 数据
    output logic empty,                           // FIFO 为空
    output logic [$clog2(DEPTH+1)-1:0] rd_count,  // 读侧看到的当前占用
    output logic underflow                        // 空时继续读导致的下溢
);

    // UG1485 对当前这组 async FIFO 配置给出的 prog_full 下限。
    localparam int XPM_PROG_FULL_THRESH_MIN = 7;

    // 对应配置下的 prog_full 上限，超过后会落入 XPM 非法范围。
    localparam int XPM_PROG_FULL_THRESH_MAX = DEPTH - 5;

    // 工程语义里的“提前满”阈值：距离真正 full 还剩 ALMOST_FULL_MARGIN 个 word。
    localparam int XPM_PROG_FULL_THRESH_REQ = DEPTH - ALMOST_FULL_MARGIN;

    // 真正送给 XPM 的阈值需要裁剪到合法区间。
    localparam int XPM_PROG_FULL_THRESH =
        (XPM_PROG_FULL_THRESH_REQ < XPM_PROG_FULL_THRESH_MIN) ? XPM_PROG_FULL_THRESH_MIN :
        (XPM_PROG_FULL_THRESH_REQ > XPM_PROG_FULL_THRESH_MAX) ? XPM_PROG_FULL_THRESH_MAX :
        XPM_PROG_FULL_THRESH_REQ;

`ifdef SYNTHESIS
    // 复位期间 XPM 内部的忙信号，仅保留用于调试观察。
    logic wr_rst_busy_int;
    logic rd_rst_busy_int;

    xpm_fifo_async #(
        // 当前取 2 级同步，优先降低资源和延迟；如未来时钟更高可再评估调大。
        .CDC_SYNC_STAGES(2),

        // 复位后 dout 默认输出 0，便于启动阶段观察。
        .DOUT_RESET_VALUE("0"),

        // 当前关闭 ECC，优先保持结构简单。
        .ECC_MODE("no_ecc"),

        // 让 Vivado 自动选择分布式 RAM / BRAM / URAM 资源类型。
        .FIFO_MEMORY_TYPE("auto"),

        // 采用 FWFT 模式时，读延迟必须为 0。
        .FIFO_READ_LATENCY(0),

        // FIFO 深度直接由封装参数 DEPTH 决定。
        .FIFO_WRITE_DEPTH(DEPTH),

        // 复位后 full/prog_full 默认拉低。
        .FULL_RESET_VALUE(0),

        // 用 prog_full 承担工程里的 almost_full 语义。
        .PROG_FULL_THRESH(XPM_PROG_FULL_THRESH),

        // 读计数位宽满足 log2(DEPTH)+1。
        .RD_DATA_COUNT_WIDTH($clog2(DEPTH+1)),

        // 读口宽度与写口宽度保持一致，本封装不做宽度转换。
        .READ_DATA_WIDTH(DATA_W),

        // 采用首字直出模式，读侧无需额外打一拍即可看到队头数据。
        .READ_MODE("fwft"),

        // 写读两侧时钟视为真正异步。
        .RELATED_CLOCKS(0),

        // 默认关闭仿真断言，避免日常日志噪声过多。
        .SIM_ASSERT_CHK(0),

        // 当前启用的高级特性包括 overflow/prog_full/data_count/underflow。
        .USE_ADV_FEATURES("0507"),

        // 不使用休眠/唤醒低功耗特性。
        .WAKEUP_TIME(0),

        .WRITE_DATA_WIDTH(DATA_W),
        .WR_DATA_COUNT_WIDTH($clog2(DEPTH+1))
    ) xpm_fifo_async_inst (
        // 不使用 sleep 接口，FIFO 始终处于工作态。
        .sleep(1'b0),

        // 启动期统一复位。
        .rst(sys_rst),

        // 写侧接口。
        .wr_clk(wr_clk),
        .wr_en(wr_en),
        .din(wr_data),
        .full(full),
        .overflow(overflow),
        .prog_full(almost_full),
        .wr_data_count(wr_count),

        // 读侧接口。
        .rd_clk(rd_clk),
        .rd_en(rd_en),
        .dout(rd_data),
        .empty(empty),
        .underflow(underflow),
        .rd_data_count(rd_count),

        // 当前设计未用到的辅助端口全部留空或固定。
        .almost_empty(),
        .almost_full(),
        .data_valid(),
        .dbiterr(),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .prog_empty(),
        .rd_rst_busy(rd_rst_busy_int),
        .sbiterr(),
        .wr_ack(),
        .wr_rst_busy(wr_rst_busy_int)
    );
`else
    // 行为级 fallback：
    // 1. 用 queue 表示 FIFO 内容。
    // 2. 保持 `rd_data = fifo_q[0]` 的 FWFT 语义。
    // 3. 重点是快速验证功能，不追求逐门级拟合 XPM 内部实现。
    logic [DATA_W-1:0] fifo_q[$];

    always_comb begin
        full        = (fifo_q.size() >= DEPTH);
        empty       = (fifo_q.size() == 0);
        almost_full = (fifo_q.size() >= (DEPTH - ALMOST_FULL_MARGIN));
        wr_count    = fifo_q.size();
        rd_count    = fifo_q.size();
        rd_data     = empty ? '0 : fifo_q[0];
    end

    always_ff @(posedge wr_clk or posedge sys_rst) begin
        if (sys_rst) begin
            fifo_q.delete();
            overflow <= 1'b0;
        end else begin
            overflow <= wr_en && full;

            if (wr_en && !full) begin
                fifo_q.push_back(wr_data);
            end
        end
    end

    always_ff @(posedge rd_clk or posedge sys_rst) begin
        if (sys_rst) begin
            fifo_q.delete();
            underflow <= 1'b0;
        end else begin
            underflow <= rd_en && empty;

            if (rd_en && !empty) begin
                void'(fifo_q.pop_front());
            end
        end
    end
`endif

endmodule
