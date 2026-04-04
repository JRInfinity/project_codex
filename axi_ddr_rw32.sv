// 模块说明：
// 1. 对外提供一个简化版的突发读写命令接口，方便在上层逻辑里直接发起 DDR 访问。
// 2. 对内把简化命令翻译成单次 AXI4 INCR 突发，不支持多命令并发和跨事务重排序。
// 3. 读写通路共用同一个仲裁约束：任一时刻只允许读或写其中一类操作处于活动状态。
module axi_ddr_rw32 #(
    parameter int ADDR_WIDTH = 32,
    parameter int ID_WIDTH   = 4
) (
    input  logic                  aclk,           // AXI 主接口时钟
    input  logic                  aresetn,        // AXI 低有效复位

    // Simple write command interface
    input  logic                  wr_start,       // 写任务启动脉冲
    input  logic [ADDR_WIDTH-1:0] wr_addr,        // 写突发起始地址
    input  logic [7:0]            wr_beats,       // 写突发 beat 数
    output logic                  wr_busy,        // 写通路忙标志
    output logic                  wr_done,        // 写任务完成脉冲
    output logic                  wr_error,       // 写响应错误标志
    input  logic [31:0]           wr_data,        // 上游提供的写数据
    input  logic                  wr_data_valid,  // 写数据有效
    output logic                  wr_data_ready,  // 当前拍可接受写数据

    // Simple read command interface
    input  logic                  rd_start,       // 读任务启动脉冲
    input  logic [ADDR_WIDTH-1:0] rd_addr,        // 读突发起始地址
    input  logic [7:0]            rd_beats,       // 读突发 beat 数
    output logic                  rd_busy,        // 读通路忙标志
    output logic                  rd_done,        // 读任务完成脉冲
    output logic                  rd_error,       // 读响应错误标志
    output logic [31:0]           rd_data,        // 返回给上游的读数据
    output logic                  rd_data_valid,  // 读数据有效
    input  logic                  rd_data_ready,  // 上游准备好接收读数据

    // AXI4 master write address channel
    output logic [ID_WIDTH-1:0]   m_axi_awid,     // AXI 写地址 ID
    output logic [ADDR_WIDTH-1:0] m_axi_awaddr,   // AXI 写地址
    output logic [7:0]            m_axi_awlen,    // AXI 写突发长度减 1
    output logic [2:0]            m_axi_awsize,   // AXI 单个 beat 大小编码
    output logic [1:0]            m_axi_awburst,  // AXI 突发类型
    output logic                  m_axi_awlock,   // AXI 锁访问标志
    output logic [3:0]            m_axi_awcache,  // AXI cache 属性
    output logic [2:0]            m_axi_awprot,   // AXI 保护属性
    output logic                  m_axi_awvalid,  // 写地址有效
    input  logic                  m_axi_awready,  // 从端接受写地址

    // AXI4 master write data channel
    output logic [31:0]           m_axi_wdata,    // AXI 写数据
    output logic [3:0]            m_axi_wstrb,    // AXI 写字节使能
    output logic                  m_axi_wlast,    // 最后一个写 beat
    output logic                  m_axi_wvalid,   // 写数据有效
    input  logic                  m_axi_wready,   // 从端准备好接收写数据

    // AXI4 master write response channel
    input  logic [ID_WIDTH-1:0]   m_axi_bid,      // 写响应 ID
    input  logic [1:0]            m_axi_bresp,    // 写响应状态
    input  logic                  m_axi_bvalid,   // 写响应有效
    output logic                  m_axi_bready,   // 准备好接收写响应

    // AXI4 master read address channel
    output logic [ID_WIDTH-1:0]   m_axi_arid,     // AXI 读地址 ID
    output logic [ADDR_WIDTH-1:0] m_axi_araddr,   // AXI 读地址
    output logic [7:0]            m_axi_arlen,    // AXI 读突发长度减 1
    output logic [2:0]            m_axi_arsize,   // AXI 单个读 beat 大小编码
    output logic [1:0]            m_axi_arburst,  // AXI 读突发类型
    output logic                  m_axi_arlock,   // AXI 锁访问标志
    output logic [3:0]            m_axi_arcache,  // AXI cache 属性
    output logic [2:0]            m_axi_arprot,   // AXI 保护属性
    output logic                  m_axi_arvalid,  // 读地址有效
    input  logic                  m_axi_arready,  // 从端接受读地址

    // AXI4 master read data channel
    input  logic [ID_WIDTH-1:0]   m_axi_rid,      // 读返回 ID
    input  logic [31:0]           m_axi_rdata,    // 读返回数据
    input  logic [1:0]            m_axi_rresp,    // 读返回状态
    input  logic                  m_axi_rlast,    // 最后一个读 beat
    input  logic                  m_axi_rvalid,   // 读返回有效
    output logic                  m_axi_rready    // 准备好接收读数据
);

    // 写状态机：先发 AW，再持续送 W，最后等待 B 响应。
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_SEND_DATA,
        WR_WAIT_RESP
    } wr_state_t;

    // 读状态机：先发 AR，再持续接收 R 数据直到最后一个 beat。
    typedef enum logic [0:0] {
        RD_IDLE,
        RD_WAIT_DATA
    } rd_state_t;

    wr_state_t wr_state;            // 写状态机当前状态
    rd_state_t rd_state;            // 读状态机当前状态

    logic [7:0] wr_total_beats;     // 当前写任务总 beat 数
    logic [7:0] wr_sent_beats;      // 当前已发送写 beat 数
    logic [7:0] rd_total_beats;     // 当前读任务总 beat 数
    logic [7:0] rd_recv_beats;      // 当前已接收读 beat 数

    logic       wr_start_accept;    // 写启动命令被本模块接受
    logic       rd_start_accept;    // 读启动命令被本模块接受
    logic       wr_fire;            // AW 通道握手成功
    logic       rd_fire;            // AR 通道握手成功
    logic       w_fire;             // W 通道握手成功
    logic       r_fire;             // R 通道握手成功

    // 简化接口只接受非零长度命令，且读写互斥，避免内部需要再做复杂调度。
    assign wr_start_accept = wr_start && !wr_busy && !rd_busy && (wr_beats != 8'd0);
    assign rd_start_accept = rd_start && !rd_busy && !wr_busy && (rd_beats != 8'd0);

    assign wr_fire = m_axi_awvalid && m_axi_awready;
    assign w_fire  = m_axi_wvalid  && m_axi_wready;
    assign rd_fire = m_axi_arvalid && m_axi_arready;
    assign r_fire  = m_axi_rvalid  && m_axi_rready;

    assign m_axi_awid    = '0;
    assign m_axi_awsize  = 3'd2;   // 4 bytes per beat
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;

    assign m_axi_arid    = '0;
    assign m_axi_arsize  = 3'd2;   // 4 bytes per beat
    assign m_axi_arburst = 2'b01;  // INCR
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;

    assign m_axi_wstrb = 4'hF;

    assign wr_busy = (wr_state != WR_IDLE);
    assign rd_busy = (rd_state != RD_IDLE);

    // 上层看到的 wr_data_ready 直接跟随 AXI W 通道 ready，表示当前 beat 可以被消费。
    assign wr_data_ready = (wr_state == WR_SEND_DATA) && m_axi_wready;
    assign m_axi_wvalid  = (wr_state == WR_SEND_DATA) && wr_data_valid;
    assign m_axi_wdata   = wr_data;
    assign m_axi_wlast   = (wr_state == WR_SEND_DATA) && (wr_sent_beats == wr_total_beats - 1);

    assign rd_data       = m_axi_rdata;
    assign rd_data_valid = (rd_state == RD_WAIT_DATA) && m_axi_rvalid;
    assign m_axi_rready  = (rd_state == RD_WAIT_DATA) && rd_data_ready;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_state       <= WR_IDLE;
            rd_state       <= RD_IDLE;

            wr_total_beats <= 8'd0;
            wr_sent_beats  <= 8'd0;
            rd_total_beats <= 8'd0;
            rd_recv_beats  <= 8'd0;

            wr_done        <= 1'b0;
            wr_error       <= 1'b0;
            rd_done        <= 1'b0;
            rd_error       <= 1'b0;

            m_axi_awaddr   <= '0;
            m_axi_awlen    <= '0;
            m_axi_awvalid  <= 1'b0;

            m_axi_araddr   <= '0;
            m_axi_arlen    <= '0;
            m_axi_arvalid  <= 1'b0;

            m_axi_bready   <= 1'b0;
        end else begin
            wr_done <= 1'b0;
            rd_done <= 1'b0;

            // 写状态机：
            // - WR_IDLE 接收写命令并发起 AW
            // - WR_SEND_DATA 逐 beat 发送 W
            // - WR_WAIT_RESP 等待 B 响应给出结果
            case (wr_state)
                WR_IDLE: begin
                    wr_error <= 1'b0;
                    m_axi_bready <= 1'b0;

                    if (wr_start_accept) begin
                        wr_total_beats <= wr_beats;
                        wr_sent_beats  <= 8'd0;
                        m_axi_awaddr   <= wr_addr;
                        m_axi_awlen    <= wr_beats - 1'b1;
                        m_axi_awvalid  <= 1'b1;
                        wr_state       <= WR_SEND_DATA;
                    end
                end

                WR_SEND_DATA: begin
                    if (wr_fire) begin
                        m_axi_awvalid <= 1'b0;
                    end

                    if (w_fire) begin
                        wr_sent_beats <= wr_sent_beats + 1'b1;
                        if (wr_sent_beats == wr_total_beats - 1) begin
                            m_axi_bready <= 1'b1;
                            wr_state     <= WR_WAIT_RESP;
                        end
                    end
                end

                WR_WAIT_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        wr_error     <= (m_axi_bresp != 2'b00);
                        wr_done      <= 1'b1;
                        m_axi_bready <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase

            // 读状态机：
            // - RD_IDLE 接收读命令并发起 AR
            // - RD_WAIT_DATA 按 ready/valid 节拍接收返回数据
            case (rd_state)
                RD_IDLE: begin
                    rd_error <= 1'b0;

                    if (rd_start_accept) begin
                        rd_total_beats <= rd_beats;
                        rd_recv_beats  <= 8'd0;
                        m_axi_araddr   <= rd_addr;
                        m_axi_arlen    <= rd_beats - 1'b1;
                        m_axi_arvalid  <= 1'b1;
                        rd_state       <= RD_WAIT_DATA;
                    end
                end

                RD_WAIT_DATA: begin
                    if (rd_fire) begin
                        m_axi_arvalid <= 1'b0;
                    end

                    if (r_fire) begin
                        rd_recv_beats <= rd_recv_beats + 1'b1;

                        if (m_axi_rresp != 2'b00) begin
                            rd_error <= 1'b1;
                        end

                        if (m_axi_rlast) begin
                            rd_done  <= 1'b1;
                            rd_state <= RD_IDLE;
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
