// 模块职责：
// 1. 在 clk 域接收一次 DDR 写任务
// 2. 按 AXI 约束将请求拆分为不跨 4KB 边界的 INCR 写突发
// 3. 消费上游已打包的数据字并驱动 AW/W/B 通道
// 4. 汇总写响应状态并上报完成或错误结果
`timescale 1ns/1ps

import ddr_axi_pkg::*;
module axi_burst_writer #(
    parameter int DATA_W        = 32,
    parameter int ADDR_W        = 32,
    parameter int BURST_MAX_LEN = 256,
    parameter int AXI_ID_W      = 8
) (
    input  logic                  clk,
    input  logic                  sys_rst,
    input  logic                  task_valid,
    output logic                  task_ready,
    input  logic [ADDR_W-1:0]     task_addr,
    input  logic [31:0]           task_byte_count,
    input  logic [DATA_W-1:0]     word_data,
    input  logic [(DATA_W/8)-1:0] word_strb,
    input  logic                  word_valid,
    output logic                  word_ready,
    output logic                  task_busy,
    output logic                  result_valid,
    input  logic                  result_ready,
    output logic                  result_done,
    output logic                  result_error,
    taxi_axi_if.wr_mst            m_axi_wr
);

    localparam int BYTE_W       = DATA_W / 8;
    localparam int AXI_SIZE_W   = (BYTE_W > 1) ? $clog2(BYTE_W) : 1;
    localparam int COUNT_W      = 33;
    localparam logic [2:0] AXI_SIZE = $clog2(BYTE_W);

    typedef enum logic [2:0] {
        S_IDLE,
        S_PREP,
        S_AWCFG,
        S_AW,
        S_WDATA,
        S_BRESP,
        S_DONE
    } state_t;

    state_t state_reg;

    logic [ADDR_W-1:0] aligned_start_addr_reg;
    logic [COUNT_W-1:0] words_total_reg;
    logic [COUNT_W-1:0] words_sent_total_reg;
    logic [ADDR_W-1:0]  next_write_addr_reg;
    logic [COUNT_W-1:0] words_write_remaining_reg;
    logic [COUNT_W-1:0] next_write_words_to_4kb_reg;
    logic [COUNT_W-1:0] burst_words_reg;
    logic [COUNT_W-1:0] burst_sent_words_reg;
    logic [ADDR_W-1:0]  aw_prep_addr_reg;
    logic [7:0]         aw_prep_len_reg;

    logic [DATA_W-1:0]  word_buf_data_reg;
    logic [BYTE_W-1:0]  word_buf_strb_reg;
    logic               word_buf_valid_reg;
    logic               error_latched_reg;
    logic               result_pending_reg;
    logic               result_done_reg;
    logic               result_error_reg;

    logic [ADDR_W-1:0] current_burst_addr_calc;
    logic [COUNT_W-1:0] words_remaining_calc;
    logic [COUNT_W-1:0] burst_words_calc;
    logic aw_fire;
    logic w_fire;
    logic b_fire;
    logic burst_last_word;

    initial begin
        if (DATA_W % 8 != 0) $error("axi_burst_writer requires DATA_W to be byte aligned.");
        if (BURST_MAX_LEN < 1 || BURST_MAX_LEN > 256) $error("BURST_MAX_LEN must be in the range 1..256.");
    end

    assign aw_fire = m_axi_wr.awvalid && m_axi_wr.awready;
    assign w_fire  = m_axi_wr.wvalid && m_axi_wr.wready;
    assign b_fire  = m_axi_wr.bvalid && m_axi_wr.bready;

    assign current_burst_addr_calc = next_write_addr_reg;
    assign words_remaining_calc    = words_write_remaining_reg;
    assign burst_words_calc        = calc_burst_words(words_remaining_calc, next_write_words_to_4kb_reg, BURST_MAX_LEN, words_remaining_calc);
    assign burst_last_word         = (burst_sent_words_reg == burst_words_reg - 1'b1);

    assign word_ready   = (state_reg == S_WDATA) && !word_buf_valid_reg;
    assign task_ready   = (state_reg == S_IDLE) && !result_pending_reg;
    assign task_busy    = (state_reg != S_IDLE);
    assign result_valid = result_pending_reg;
    assign result_done  = result_done_reg;
    assign result_error = result_error_reg;

    always_ff @(posedge clk) begin
        if (sys_rst) begin
            state_reg             <= S_IDLE;
            aligned_start_addr_reg <= '0;
            words_total_reg       <= '0;
            words_sent_total_reg  <= '0;
            next_write_addr_reg   <= '0;
            words_write_remaining_reg <= '0;
            next_write_words_to_4kb_reg <= '0;
            burst_words_reg       <= '0;
            burst_sent_words_reg  <= '0;
            aw_prep_addr_reg      <= '0;
            aw_prep_len_reg       <= '0;
            word_buf_data_reg     <= '0;
            word_buf_strb_reg     <= '0;
            word_buf_valid_reg    <= 1'b0;
            error_latched_reg     <= 1'b0;
            result_pending_reg    <= 1'b0;
            result_done_reg       <= 1'b0;
            result_error_reg      <= 1'b0;

            m_axi_wr.awid         <= '0;
            m_axi_wr.awaddr       <= '0;
            m_axi_wr.awlen        <= '0;
            m_axi_wr.awsize       <= AXI_SIZE;
            m_axi_wr.awburst      <= 2'b01;
            m_axi_wr.awlock       <= 1'b0;
            m_axi_wr.awcache      <= 4'b0011;
            m_axi_wr.awprot       <= 3'b000;
            m_axi_wr.awqos        <= 4'd0;
            m_axi_wr.awregion     <= 4'd0;
            m_axi_wr.awuser       <= '0;
            m_axi_wr.awvalid      <= 1'b0;

            m_axi_wr.wdata        <= '0;
            m_axi_wr.wstrb        <= '0;
            m_axi_wr.wlast        <= 1'b0;
            m_axi_wr.wuser        <= '0;
            m_axi_wr.wvalid       <= 1'b0;
            m_axi_wr.bready       <= 1'b0;
        end else begin
            if (result_pending_reg && result_ready) begin
                result_pending_reg <= 1'b0;
                result_done_reg    <= 1'b0;
                result_error_reg   <= 1'b0;
                if (state_reg == S_DONE) begin
                    state_reg <= S_IDLE;
                end
            end

            if (word_ready && word_valid) begin
                word_buf_data_reg  <= word_data;
                word_buf_strb_reg  <= word_strb;
                word_buf_valid_reg <= 1'b1;
            end

            if (aw_fire) begin
                m_axi_wr.awvalid <= 1'b0;
            end

            case (state_reg)
                S_IDLE: begin
                    error_latched_reg  <= 1'b0;
                    word_buf_valid_reg <= 1'b0;
                    m_axi_wr.wvalid    <= 1'b0;
                    m_axi_wr.wlast     <= 1'b0;
                    m_axi_wr.bready    <= 1'b0;

                    if (task_valid && task_ready) begin // 
                        aligned_start_addr_reg <= align_addr(task_addr, AXI_SIZE_W);
                        words_total_reg       <= calc_total_words(task_byte_count, task_addr[AXI_SIZE_W-1:0], BYTE_W);
                        words_sent_total_reg  <= '0;
                        next_write_addr_reg   <= align_addr(task_addr, AXI_SIZE_W);
                        words_write_remaining_reg <= calc_total_words(task_byte_count, task_addr[AXI_SIZE_W-1:0], BYTE_W);
                        next_write_words_to_4kb_reg <= calc_words_to_4kb(align_addr(task_addr, AXI_SIZE_W), BYTE_W);
                        burst_sent_words_reg  <= '0;
                        state_reg             <= S_PREP;
                    end
                end

                S_PREP: begin
                    if (words_remaining_calc == 0) begin
                        error_latched_reg <= 1'b1;
                        state_reg   <= S_DONE;
                    end else begin
                        burst_words_reg      <= burst_words_calc;
                        burst_sent_words_reg <= '0;
                        aw_prep_addr_reg     <= current_burst_addr_calc;
                        aw_prep_len_reg      <= burst_words_calc[7:0] - 1'b1;
                        state_reg            <= S_AWCFG;
                    end
                end

                S_AWCFG: begin
                        m_axi_wr.awid        <= '0;
                        m_axi_wr.awaddr      <= aw_prep_addr_reg;
                        m_axi_wr.awlen       <= aw_prep_len_reg;
                        m_axi_wr.awsize      <= AXI_SIZE;
                        m_axi_wr.awburst     <= 2'b01;
                        m_axi_wr.awlock      <= 1'b0;
                        m_axi_wr.awcache     <= 4'b0011;
                        m_axi_wr.awprot      <= 3'b000;
                        m_axi_wr.awqos       <= 4'd0;
                        m_axi_wr.awregion    <= 4'd0;
                        m_axi_wr.awuser      <= '0;
                        m_axi_wr.awvalid     <= 1'b1;
                        state_reg            <= S_AW;
                end

                S_AW: begin
                    if (aw_fire) begin
                        state_reg <= S_WDATA;
                    end
                end

                S_WDATA: begin
                    if (!m_axi_wr.wvalid && word_buf_valid_reg) begin
                        m_axi_wr.wdata     <= word_buf_data_reg;
                        m_axi_wr.wstrb     <= word_buf_strb_reg;
                        m_axi_wr.wlast     <= burst_last_word;
                        m_axi_wr.wvalid    <= 1'b1;
                        word_buf_valid_reg <= 1'b0;
                    end

                    if (w_fire) begin
                        m_axi_wr.wvalid       <= 1'b0;
                        burst_sent_words_reg  <= burst_sent_words_reg + 1'b1;
                        words_sent_total_reg  <= words_sent_total_reg + 1'b1;
                        next_write_addr_reg   <= next_write_addr_reg + (1'b1 << AXI_SIZE_W);
                        words_write_remaining_reg <= words_write_remaining_reg - 1'b1;
                        if (next_write_words_to_4kb_reg == 1) begin
                            next_write_words_to_4kb_reg <= 4096 / BYTE_W;
                        end else begin
                            next_write_words_to_4kb_reg <= next_write_words_to_4kb_reg - 1'b1;
                        end

                        if (burst_last_word) begin
                            m_axi_wr.bready <= 1'b1;
                            state_reg       <= S_BRESP;
                        end
                    end
                end

                S_BRESP: begin
                    if (b_fire) begin
                        m_axi_wr.bready <= 1'b0;
                        if (m_axi_wr.bresp != 2'b00) begin
                            error_latched_reg <= 1'b1;
                        end

                        if ((m_axi_wr.bresp != 2'b00) || (words_write_remaining_reg == 0)) begin
                            state_reg <= S_DONE;
                        end else begin
                            state_reg <= S_PREP;
                        end
                    end
                end

                S_DONE: begin
                    m_axi_wr.awvalid <= 1'b0;
                    m_axi_wr.wvalid  <= 1'b0;
                    m_axi_wr.wlast   <= 1'b0;
                    m_axi_wr.bready  <= 1'b0;
                    word_buf_valid_reg <= 1'b0;
                    if (!result_pending_reg) begin
                        result_pending_reg <= 1'b1;
                        result_done_reg    <= !error_latched_reg;
                        result_error_reg   <= error_latched_reg;
                    end
                end

                default: begin
                    state_reg <= S_IDLE;
                end
            endcase
        end
    end

endmodule
