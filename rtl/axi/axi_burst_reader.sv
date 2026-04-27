`timescale 1ns/1ps

import ddr_axi_pkg::*;

module axi_burst_reader #(
    parameter int DATA_W                  = 32,
    parameter int ADDR_W                  = 32,
    parameter int BURST_MAX_LEN           = 256, // 一个burst的最大beat数，AXI规范限制为256
    parameter int AXI_ID_W                = 8,
    parameter int FIFO_DEPTH_WORDS        = 64,
    parameter int MAX_OUTSTANDING_BURSTS  = 4, // 最多允许多少个burst同时挂在AXI上
    parameter int MAX_OUTSTANDING_BEATS   = 32 // 为了避免过度占用FIFO资源，限制同时在飞的beat数，应该覆盖一个完整burst即可
) (
    input  logic              axi_clk,
    input  logic              sys_rst,

    // task_cdc送来的任务
    input  logic              task_valid,
    input  logic [ADDR_W-1:0] task_addr,
    input  logic [31:0]       task_byte_count,

    output logic              task_ready,
    output logic              word_valid,
    output logic [DATA_W-1:0] word_data,
    input  logic              word_ready, // 下游是否准备好接收数据
    input  logic              word_almost_full,
    input  logic [$clog2(FIFO_DEPTH_WORDS+1)-1:0] word_count,
    output logic              result_valid,
    output logic              result_done,
    output logic              result_error,
    input  logic              result_ready,
    taxi_axi_if.rd_mst        m_axi_rd
);

    localparam int BYTE_W           = DATA_W / 8; // 每个数据字包含多少字节
    localparam int AXI_SIZE_W       = (BYTE_W > 1) ? $clog2(BYTE_W) : 1; // AXI的SIZE字段编码位宽，如4byte则SIZE=2，8byte则SIZE=3
    localparam int COUNT_W          = 33; 
    localparam int BEAT_COUNT_W     = (MAX_OUTSTANDING_BEATS > 1) ? $clog2(MAX_OUTSTANDING_BEATS + 1) : 1; // inflight beat计数位宽
    localparam int BURSTS_COUNT_W   = (MAX_OUTSTANDING_BURSTS > 1) ? $clog2(MAX_OUTSTANDING_BURSTS + 1) : 1; // inflight burst数量计数位宽
    localparam int BURST_COUNT_W    = (BURST_MAX_LEN > 1) ? $clog2(BURST_MAX_LEN + 1) : 1; // burst长度需要多少位
    localparam int BURST_FIFO_PTR_W = (MAX_OUTSTANDING_BURSTS > 1) ? $clog2(MAX_OUTSTANDING_BURSTS) : 1; // burst_beats_q队列指针位宽
    localparam int WORDS_PER_4KB    = 4096 / BYTE_W; // 每4KB区间内能放多少个word
    localparam logic [2:0] AXI_SIZE = $clog2(BYTE_W); // 实际写进AXI的ARSIZE信号的值

    typedef enum logic [2:0] {
        S_IDLE,
        S_ACTIVE,
        S_DRAIN,
        S_ERROR,
        S_DONE
    } state_t;

    (* fsm_encoding = "sequential" *) state_t state_reg;

    logic [ADDR_W-1:0] aligned_start_addr_reg;
    logic [COUNT_W-1:0] words_total_to_fetch_reg; // 这次任务总共需要读的word数
    logic [COUNT_W-1:0] words_requested_reg; // 已经发出AR请求的word数（不含正在发出的）
    logic [ADDR_W-1:0] next_issue_addr_reg; // 下一拍要发出AR请求burst的起始地址
    logic [COUNT_W-1:0] words_request_remaining_reg; // 还剩多少word没有发出AR请求
    logic [COUNT_W-1:0] next_issue_words_to_4kb_reg;
    logic [COUNT_W-1:0] words_received_reg; // 已经从R通道收回来的word数
    logic [BEAT_COUNT_W-1:0] beats_inflight_reg;
    logic [BURSTS_COUNT_W-1:0] bursts_inflight_reg;
    logic               issue_seed_valid_reg;
    logic               issue_gate_valid_reg;
    logic [ADDR_W-1:0]  issue_gate_addr_reg;
    logic [BURST_COUNT_W-1:0] issue_gate_words_remaining_reg;
    logic               issue_plan_valid_reg;
    logic [ADDR_W-1:0]  issue_plan_addr_reg;
    logic [BURST_COUNT_W-1:0] issue_plan_words_remaining_reg;
    logic               issue_calc_valid_reg;
    logic [ADDR_W-1:0]  issue_calc_addr_reg;
    logic [BURST_COUNT_W-1:0] issue_calc_words_remaining_reg;
    logic [BURST_COUNT_W-1:0] issue_calc_words_to_4kb_reg;
    logic               issue_prep_valid_reg;
    logic [ADDR_W-1:0]  issue_prep_addr_reg;
    logic [BURST_COUNT_W-1:0] issue_prep_beats_reg;
    logic               issue_commit_valid_reg;
    logic [BURST_COUNT_W-1:0] issue_commit_beats_reg;
    logic               error_latched_reg;
    logic               result_pending_reg;
    logic               result_done_reg;
    logic               result_error_reg;

    logic [BURST_COUNT_W-1:0] burst_beats_q [0:MAX_OUTSTANDING_BURSTS-1];
    logic [BURST_FIFO_PTR_W-1:0] burst_head_reg;
    logic [BURST_FIFO_PTR_W-1:0] burst_tail_reg;
    logic [BURST_FIFO_PTR_W:0]   burst_count_reg;

    logic [COUNT_W-1:0] task_addr_offset_calc;
    logic [COUNT_W-1:0] task_words_total_calc;
    logic               request_remaining_nonzero_reg;
    logic [BEAT_COUNT_W-1:0] beats_credit_reg;
    logic [BEAT_COUNT_W-1:0] beats_credit_calc;
    logic               can_issue_ar_calc;
    logic               expected_rlast;
    logic               ar_fire;
    logic               r_fire;

    function automatic logic [BURST_FIFO_PTR_W-1:0] ptr_inc(
        input logic [BURST_FIFO_PTR_W-1:0] ptr
    );
        if (ptr == MAX_OUTSTANDING_BURSTS-1) begin
            ptr_inc = '0;
        end else begin
            ptr_inc = ptr + 1'b1;
        end
    endfunction

    function automatic logic [BURST_COUNT_W-1:0] limit_burst_words(
        input logic [COUNT_W-1:0] words
    );
        if (words >= BURST_MAX_LEN) begin
            limit_burst_words = BURST_COUNT_W'(BURST_MAX_LEN);
        end else begin
            limit_burst_words = BURST_COUNT_W'(words);
        end
    endfunction

    initial begin
        if (DATA_W % 8 != 0) $error("axi_burst_reader requires DATA_W to be byte aligned.");
        if (BURST_MAX_LEN < 1 || BURST_MAX_LEN > 256) $error("BURST_MAX_LEN must be in the range 1..256.");
        if (MAX_OUTSTANDING_BEATS < BURST_MAX_LEN) $error("MAX_OUTSTANDING_BEATS must cover one full burst.");
        if (FIFO_DEPTH_WORDS <= MAX_OUTSTANDING_BEATS) $error("FIFO_DEPTH_WORDS should exceed MAX_OUTSTANDING_BEATS.");
    end

    assign ar_fire      = m_axi_rd.arvalid && m_axi_rd.arready;
    assign r_fire       = m_axi_rd.rvalid && m_axi_rd.rready;
    assign task_ready   = (state_reg == S_IDLE) && !result_pending_reg;
    assign word_valid   = r_fire && !error_latched_reg && (m_axi_rd.rresp == 2'b00) && word_ready;
    assign word_data    = m_axi_rd.rdata;
    assign result_valid = result_pending_reg;
    assign result_done  = result_done_reg;
    assign result_error = result_error_reg;
    assign expected_rlast = (burst_count_reg != 0) && (burst_beats_q[burst_head_reg] == 1);

    always_comb begin
        task_addr_offset_calc = '0;
        task_addr_offset_calc[AXI_SIZE_W-1:0] = task_addr[AXI_SIZE_W-1:0];
        task_words_total_calc = calc_total_words(task_byte_count, task_addr_offset_calc, BYTE_W);

        if (beats_inflight_reg >= MAX_OUTSTANDING_BEATS) begin
            beats_credit_calc = '0;
        end else begin
            beats_credit_calc = MAX_OUTSTANDING_BEATS - beats_inflight_reg; // 
        end

        can_issue_ar_calc = 1'b0;
        if ((state_reg == S_ACTIVE) &&
            !issue_seed_valid_reg &&
            !issue_gate_valid_reg &&
            !issue_plan_valid_reg &&
            !issue_calc_valid_reg &&
            !issue_prep_valid_reg &&
            !issue_commit_valid_reg &&
            !m_axi_rd.arvalid &&
            !error_latched_reg &&
            request_remaining_nonzero_reg && // 第一次burst发出前，这个信号是task_words_total_calc != 0，后续每发出一个burst这个信号就根据剩余请求是否为0来更新。这个信号为1说明还有请求没发完。
            !word_almost_full &&
            (bursts_inflight_reg < MAX_OUTSTANDING_BURSTS) && // 正在进行的burst数量未超过限制
            (beats_credit_reg != 0)) begin
            can_issue_ar_calc = 1'b1; // 能够发出AR请求的条件：当前在ACTIVE状态，没有正在进行的AR发出流程，AXI接口空闲，没有错误，仍有请求要发，下游不满，未超过burst和beat的限制
        end
    end

    always_ff @(posedge axi_clk) begin
        logic [BURST_FIFO_PTR_W-1:0] burst_head_next;
        logic [BURST_FIFO_PTR_W-1:0] burst_tail_next;
        logic [BURST_FIFO_PTR_W:0]   burst_count_next;
        logic [COUNT_W-1:0]          words_requested_next;
        logic [COUNT_W-1:0]          words_received_next;
        logic [BEAT_COUNT_W-1:0]     beats_inflight_next;
        logic [BURSTS_COUNT_W-1:0]   bursts_inflight_next;
        logic                        rresp_error_now;
        logic                        rlast_error_now;
        logic                        fifo_overflow_now;
        logic                        fatal_now;

        if (sys_rst) begin
            state_reg                <= S_IDLE;
            aligned_start_addr_reg   <= '0;
            words_total_to_fetch_reg <= '0;
            words_requested_reg      <= '0;
            next_issue_addr_reg      <= '0;
            words_request_remaining_reg <= '0;
            next_issue_words_to_4kb_reg <= '0;
            words_received_reg       <= '0;
            beats_inflight_reg       <= '0;
            bursts_inflight_reg      <= '0;
            beats_credit_reg         <= BEAT_COUNT_W'(MAX_OUTSTANDING_BEATS);
            issue_seed_valid_reg     <= 1'b0;
            issue_gate_valid_reg     <= 1'b0;
            issue_gate_addr_reg      <= '0;
            issue_gate_words_remaining_reg <= '0;
            issue_plan_valid_reg     <= 1'b0;
            issue_plan_addr_reg      <= '0;
            issue_plan_words_remaining_reg <= '0;
            issue_calc_valid_reg     <= 1'b0;
            issue_calc_addr_reg      <= '0;
            issue_calc_words_remaining_reg <= '0;
            issue_calc_words_to_4kb_reg <= '0;
            issue_prep_valid_reg     <= 1'b0;
            issue_prep_addr_reg      <= '0;
            issue_prep_beats_reg     <= '0;
            issue_commit_valid_reg   <= 1'b0;
            issue_commit_beats_reg   <= '0;
            request_remaining_nonzero_reg <= 1'b0;
            error_latched_reg        <= 1'b0;
            result_pending_reg       <= 1'b0;
            result_done_reg          <= 1'b0;
            result_error_reg         <= 1'b0;
            burst_head_reg           <= '0;
            burst_tail_reg           <= '0;
            burst_count_reg          <= '0;

            m_axi_rd.arid            <= '0;
            m_axi_rd.araddr          <= '0;
            m_axi_rd.arlen           <= '0;
            m_axi_rd.arsize          <= AXI_SIZE;
            m_axi_rd.arburst         <= 2'b01;
            m_axi_rd.arlock          <= 1'b0;
            m_axi_rd.arcache         <= 4'b0011;
            m_axi_rd.arprot          <= 3'b000;
            m_axi_rd.arqos           <= 4'd0;
            m_axi_rd.arregion        <= 4'd0;
            m_axi_rd.aruser          <= '0;
            m_axi_rd.arvalid         <= 1'b0;
            m_axi_rd.rready          <= 1'b0;
        end else begin
            rresp_error_now   = r_fire && (m_axi_rd.rresp != 2'b00);
            rlast_error_now   = r_fire && (m_axi_rd.rlast != expected_rlast);
            fifo_overflow_now = r_fire && !error_latched_reg && !word_ready;
            fatal_now         = rresp_error_now || rlast_error_now || fifo_overflow_now;

            burst_head_next      = burst_head_reg;
            burst_tail_next      = burst_tail_reg;
            burst_count_next     = burst_count_reg;
            words_requested_next = words_requested_reg;
            words_received_next  = words_received_reg;
            beats_inflight_next  = beats_inflight_reg;
            bursts_inflight_next = bursts_inflight_reg;
            beats_credit_reg <= beats_credit_calc;

            m_axi_rd.rready <= 1'b0;
            case (state_reg)
                S_ACTIVE, S_DRAIN: begin
                    m_axi_rd.rready <= (beats_inflight_reg != 0) && !error_latched_reg && word_ready && !word_almost_full;
                end
                S_ERROR: begin
                    m_axi_rd.rready <= (beats_inflight_reg != 0);
                end
                default: begin
                    m_axi_rd.rready <= 1'b0;
                end
            endcase

            if (result_pending_reg && result_ready) begin
                result_pending_reg <= 1'b0;
                result_done_reg    <= 1'b0;
                result_error_reg   <= 1'b0;
                if (state_reg == S_DONE) begin
                    state_reg <= S_IDLE;
                end else if ((state_reg == S_ERROR) && (beats_inflight_reg == 0)) begin
                    state_reg <= S_IDLE;
                end
            end

            if (ar_fire) begin
                m_axi_rd.arvalid       <= 1'b0;
                issue_prep_valid_reg   <= 1'b0;
                issue_commit_valid_reg <= 1'b1;
                issue_commit_beats_reg <= issue_prep_beats_reg;
            end

            if (state_reg == S_IDLE) begin
                error_latched_reg   <= 1'b0;
                issue_seed_valid_reg <= 1'b0;
                issue_gate_valid_reg <= 1'b0;
                issue_plan_valid_reg <= 1'b0;
                issue_calc_valid_reg <= 1'b0;
                issue_prep_valid_reg <= 1'b0;
                issue_commit_valid_reg <= 1'b0;
                beats_credit_reg    <= beats_credit_calc;
                m_axi_rd.arvalid    <= 1'b0;
                m_axi_rd.rready     <= 1'b0;

                if (task_valid && task_ready) begin
                    aligned_start_addr_reg   <= align_addr(task_addr, AXI_SIZE_W); // 初始化向下对齐好的初始地址
                    words_total_to_fetch_reg <= task_words_total_calc; // 总共需要读的word数
                    words_requested_reg      <= '0;
                    next_issue_addr_reg      <= align_addr(task_addr, AXI_SIZE_W);
                    words_request_remaining_reg <= task_words_total_calc;
                    next_issue_words_to_4kb_reg <= calc_words_to_4kb(align_addr(task_addr, AXI_SIZE_W), BYTE_W);
                    // ddr_read_engine only issues non-empty row tasks; avoid pulling
                    // task_byte_count through calc_total_words onto this timing path.
                    request_remaining_nonzero_reg <= 1'b1;
                    words_received_reg       <= '0;
                    beats_inflight_reg       <= '0;
                    bursts_inflight_reg      <= '0;
                    beats_credit_reg         <= BEAT_COUNT_W'(MAX_OUTSTANDING_BEATS);

                    issue_seed_valid_reg     <= 1'b0;
                    issue_gate_valid_reg     <= 1'b0;
                    issue_plan_valid_reg     <= 1'b0;
                    issue_calc_valid_reg     <= 1'b0;
                    issue_commit_valid_reg   <= 1'b0;

                    burst_head_reg           <= '0;
                    burst_tail_reg           <= '0;
                    burst_count_reg          <= '0;
                    state_reg                <= S_ACTIVE;
                end
            end else begin

                if (can_issue_ar_calc) begin
                    issue_seed_valid_reg           <= 1'b1;
                end

                // seed阶段
                if (issue_seed_valid_reg && !issue_gate_valid_reg && !issue_plan_valid_reg && !issue_calc_valid_reg && !issue_prep_valid_reg) begin
                    issue_seed_valid_reg           <= 1'b0;
                    issue_gate_valid_reg           <= 1'b1;
                    issue_gate_addr_reg            <= next_issue_addr_reg;
                    issue_gate_words_remaining_reg <= limit_burst_words(words_request_remaining_reg); // 一个burst最多发256个beat，高位截位
                end

                // gate阶段
                if (issue_gate_valid_reg && !issue_plan_valid_reg && !issue_calc_valid_reg && !issue_prep_valid_reg) begin
                    issue_gate_valid_reg           <= 1'b0;
                    issue_plan_valid_reg           <= 1'b1;
                    issue_plan_addr_reg            <= issue_gate_addr_reg;
                    issue_plan_words_remaining_reg <= issue_gate_words_remaining_reg;
                end

                // plan阶段
                if (issue_plan_valid_reg && !issue_calc_valid_reg && !issue_prep_valid_reg) begin
                    issue_plan_valid_reg           <= 1'b0;
                    issue_calc_valid_reg           <= 1'b1;
                    issue_calc_addr_reg            <= issue_plan_addr_reg;
                    issue_calc_words_remaining_reg <= issue_plan_words_remaining_reg;
                    issue_calc_words_to_4kb_reg    <= limit_burst_words(next_issue_words_to_4kb_reg);
                end

                // calc阶段
                if (issue_calc_valid_reg && !issue_prep_valid_reg) begin
                    issue_calc_valid_reg <= 1'b0;
                    issue_prep_valid_reg <= 1'b1;
                    issue_prep_addr_reg  <= issue_calc_addr_reg;
                    issue_prep_beats_reg <= BURST_COUNT_W'(calc_burst_words(
                        issue_calc_words_remaining_reg,
                        issue_calc_words_to_4kb_reg,
                        BURST_MAX_LEN,
                        beats_credit_reg
                    )); // 根据剩余数据量、4KB边界、最大突发长度和beat credit计算本次burst的beat数
                end

                // 把计算好的信息送上AR通道
                if (issue_prep_valid_reg && !m_axi_rd.arvalid) begin
                    m_axi_rd.arid     <= '0;
                    m_axi_rd.araddr   <= issue_prep_addr_reg; // 计算好的本次burst的起始地址
                    m_axi_rd.arlen    <= issue_prep_beats_reg - 1'b1; // AXI ARLEN是实际beat数减1
                    m_axi_rd.arsize   <= AXI_SIZE; // 固定为AXI_SIZE，表示每个beat的字节数，
                    m_axi_rd.arburst  <= 2'b01;
                    m_axi_rd.arlock   <= 1'b0;
                    m_axi_rd.arcache  <= 4'b0011;
                    m_axi_rd.arprot   <= 3'b000;
                    m_axi_rd.arqos    <= 4'd0;
                    m_axi_rd.arregion <= 4'd0;
                    m_axi_rd.aruser   <= '0;
                    m_axi_rd.arvalid  <= 1'b1; // 准备好开始启动AR
                end

                // AR发出后更新状态
                if (issue_commit_valid_reg) begin
                    logic [COUNT_W-1:0] words_request_remaining_after_commit; // 记录这条burst提交后还有多少word没发
                    burst_beats_q[burst_tail_reg] <= issue_commit_beats_reg; // 这一次burst的beat数写入队列
                    burst_tail_next               = ptr_inc(burst_tail_reg); // 推进队尾指针（环形队列），下一个新发出去burst要登记的位置
                    burst_count_next              = burst_count_next + 1'b1; // 队列中burst数量加1，后面r_fire收数时，如果某条burst收到最后一拍，它会再减回去
                    words_requested_next          = words_requested_next + issue_commit_beats_reg; // 已经通过AR发出去的总word数
                    next_issue_addr_reg           <= next_issue_addr_reg + (issue_commit_beats_reg << AXI_SIZE_W); // 下一条burst的起始地址推进，这里根据本次burst的beat数和每个beat的字节数（2^AXI_SIZE_W）计算地址增量
                    words_request_remaining_after_commit = words_request_remaining_reg - issue_commit_beats_reg; // 记录这条burst提交后还有多少word没发
                    words_request_remaining_reg   <= words_request_remaining_after_commit;
                    request_remaining_nonzero_reg <= (words_request_remaining_after_commit != 0); // 提交完这条burst之后，是否还剩请求没发完。
                    // next_issue_words_to_4kb_reg这次burst提交后，下一条burst最多还能有多少beat而不跨4KB边界。正常情况下应该是减去本次burst的beat数，但如果正好打满4KB边界了，那么下一条burst就完全不受4KB边界限制了，可以直接恢复到最大值。
                    if (issue_commit_beats_reg == next_issue_words_to_4kb_reg) begin
                        next_issue_words_to_4kb_reg <= WORDS_PER_4KB;
                    end else begin
                        next_issue_words_to_4kb_reg <= next_issue_words_to_4kb_reg - issue_commit_beats_reg;
                    end
                    beats_inflight_next           = beats_inflight_next + issue_commit_beats_reg; // 这次burst提交后正在飞的beat
                    bursts_inflight_next          = bursts_inflight_next + 1'b1; // 这次burst提交后正在飞的burst
                    issue_commit_valid_reg        <= 1'b0;
                end

                if (r_fire) begin
                    words_received_next = words_received_next + 1'b1;
                    if (beats_inflight_next != 0) beats_inflight_next = beats_inflight_next - 1'b1;

                    if (burst_count_reg == 0) begin
                        error_latched_reg <= 1'b1;
                    end else if (expected_rlast) begin
                        burst_head_next  = ptr_inc(burst_head_reg);
                        burst_count_next = burst_count_next - 1'b1;
                        if (bursts_inflight_next != 0) bursts_inflight_next = bursts_inflight_next - 1'b1;
                    end else begin
                        burst_beats_q[burst_head_reg] <= burst_beats_q[burst_head_reg] - 1'b1;
                    end

                    if (fatal_now) error_latched_reg <= 1'b1;
                end

                burst_head_reg      <= burst_head_next;
                burst_tail_reg      <= burst_tail_next;
                burst_count_reg     <= burst_count_next;
                words_requested_reg <= words_requested_next;
                words_received_reg  <= words_received_next;
                beats_inflight_reg  <= beats_inflight_next;
                bursts_inflight_reg <= bursts_inflight_next;

                case (state_reg)
                    S_ACTIVE: begin
                        if (fatal_now || error_latched_reg) begin
                            m_axi_rd.arvalid      <= 1'b0;
                            issue_seed_valid_reg  <= 1'b0;
                            issue_gate_valid_reg  <= 1'b0;
                            issue_plan_valid_reg  <= 1'b0;
                            issue_calc_valid_reg  <= 1'b0;
                            issue_prep_valid_reg  <= 1'b0;
                            issue_commit_valid_reg <= 1'b0;
                            state_reg             <= S_ERROR;
                        end else if (!request_remaining_nonzero_reg && (beats_inflight_next == 0)) begin
                            state_reg <= S_DONE;
                        end else if (!request_remaining_nonzero_reg) begin
                            state_reg <= S_DRAIN;
                        end
                    end

                    S_DRAIN: begin
                        if (fatal_now || error_latched_reg) begin
                            m_axi_rd.arvalid      <= 1'b0;
                            issue_seed_valid_reg  <= 1'b0;
                            issue_gate_valid_reg  <= 1'b0;
                            issue_plan_valid_reg  <= 1'b0;
                            issue_calc_valid_reg  <= 1'b0;
                            issue_prep_valid_reg  <= 1'b0;
                            issue_commit_valid_reg <= 1'b0;
                            state_reg             <= S_ERROR;
                        end else if (beats_inflight_next == 0) begin
                            state_reg <= S_DONE;
                        end
                    end

                    S_ERROR: begin
                        m_axi_rd.arvalid     <= 1'b0;
                        issue_seed_valid_reg <= 1'b0;
                        issue_gate_valid_reg <= 1'b0;
                        issue_plan_valid_reg <= 1'b0;
                        issue_calc_valid_reg <= 1'b0;
                        issue_prep_valid_reg <= 1'b0;
                        issue_commit_valid_reg <= 1'b0;
                        if ((beats_inflight_next == 0) && !result_pending_reg) begin
                            result_pending_reg <= 1'b1;
                            result_done_reg    <= 1'b0;
                            result_error_reg   <= 1'b1;
                        end
                    end

                    S_DONE: begin
                        m_axi_rd.arvalid     <= 1'b0;
                        issue_seed_valid_reg <= 1'b0;
                        issue_gate_valid_reg <= 1'b0;
                        issue_plan_valid_reg <= 1'b0;
                        issue_calc_valid_reg <= 1'b0;
                        issue_prep_valid_reg <= 1'b0;
                        issue_commit_valid_reg <= 1'b0;
                        if (!result_pending_reg) begin
                            result_pending_reg <= 1'b1;
                            result_done_reg    <= 1'b1;
                            result_error_reg   <= 1'b0;
                        end
                    end

                    default: begin
                        state_reg <= S_IDLE;
                    end
                endcase
            end
        end
    end
`ifndef SYNTHESIS
    logic [ADDR_W-1:0] araddr_hold_assert_reg;
    logic [7:0]        arlen_hold_assert_reg;
    logic [2:0]        arsize_hold_assert_reg;
    logic [1:0]        arburst_hold_assert_reg;
    logic              ar_stall_assert_reg;
    int unsigned       ar_burst_bytes_assert;

    always_ff @(posedge axi_clk) begin
        if (sys_rst) begin
            araddr_hold_assert_reg  <= '0;
            arlen_hold_assert_reg   <= '0;
            arsize_hold_assert_reg  <= '0;
            arburst_hold_assert_reg <= '0;
            ar_stall_assert_reg     <= 1'b0;
        end else begin
            if (m_axi_rd.arvalid) begin
                ar_burst_bytes_assert = (int'(m_axi_rd.arlen) + 1) * BYTE_W;
                if (m_axi_rd.arlen > 8'd255) begin
                    $error("axi_burst_reader ARLEN exceeded AXI4 limit");
                end
                if ((m_axi_rd.araddr[11:0] + ar_burst_bytes_assert) > 4096) begin
                    $error("axi_burst_reader issued burst crossing 4KB boundary");
                end
            end

            if (m_axi_rd.arvalid && !m_axi_rd.arready) begin
                if (ar_stall_assert_reg &&
                    ((m_axi_rd.araddr != araddr_hold_assert_reg) ||
                     (m_axi_rd.arlen != arlen_hold_assert_reg) ||
                     (m_axi_rd.arsize != arsize_hold_assert_reg) ||
                     (m_axi_rd.arburst != arburst_hold_assert_reg))) begin
                    $error("axi_burst_reader AR channel changed while ARVALID waited for ARREADY");
                end
                araddr_hold_assert_reg  <= m_axi_rd.araddr;
                arlen_hold_assert_reg   <= m_axi_rd.arlen;
                arsize_hold_assert_reg  <= m_axi_rd.arsize;
                arburst_hold_assert_reg <= m_axi_rd.arburst;
                ar_stall_assert_reg     <= 1'b1;
            end else begin
                ar_stall_assert_reg <= 1'b0;
            end

            if (beats_inflight_reg > MAX_OUTSTANDING_BEATS) begin
                $error("axi_burst_reader outstanding beat counter overflow");
            end
            if (burst_count_reg > MAX_OUTSTANDING_BURSTS) begin
                $error("axi_burst_reader outstanding burst counter overflow");
            end
        end
    end
`endif

endmodule
