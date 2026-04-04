// 模块职责：
// 1. 在 axi_clk 域接收一次 DDR 读任务
// 2. 按 AXI 约束将请求拆分为不跨 4KB 边界的 INCR 突发
// 3. 一边发起 AR/R 传输，一边把完整 DATA_W 数据字写入下游 FIFO
// 4. 汇总完成、响应错误和 FIFO 溢出状态并上报结果
import ddr_axi_pkg::*;
module axi_burst_reader #(
    parameter int DATA_W                  = 32,
    parameter int ADDR_W                  = 32,
    parameter int BURST_MAX_LEN           = 256,
    parameter int AXI_ID_W                = 8,
    parameter int FIFO_DEPTH_WORDS        = 64,
    parameter int MAX_OUTSTANDING_BURSTS  = 4,
    parameter int MAX_OUTSTANDING_BEATS   = 32
) (
    input  logic              axi_clk,          // AXI 读时钟
    input  logic              sys_rst,          // 高有效复位
    input  logic              task_valid,       // 新读任务有效
    output logic              task_ready,       // 当前可接受新读任务
    input  logic [ADDR_W-1:0] task_addr,        // 读任务起始地址
    input  logic [31:0]       task_byte_count,  // 读任务总字节数
    output logic              word_valid,       // 返回 word 有效
    output logic [DATA_W-1:0] word_data,        // 返回的整 word 数据
    input  logic              word_ready,       // 下游准备好接收一个 word
    input  logic              word_almost_full, // 下游缓冲接近满
    input  logic [$clog2(FIFO_DEPTH_WORDS+1)-1:0] word_count, // 下游当前缓存的 word 数
    output logic              result_valid,     // 任务结果有效
    output logic              result_done,      // 任务结果为成功完成
    output logic              result_error,     // 任务结果为错误结束
    input  logic              result_ready,     // 上层接受当前结果
    taxi_axi_if.rd_mst        m_axi_rd          // AXI 读主接口
);

    localparam int BYTE_W           = DATA_W / 8;
    localparam int AXI_SIZE_W       = (BYTE_W > 1) ? $clog2(BYTE_W) : 1;
    localparam int COUNT_W          = 33;
    localparam int BURST_COUNT_W    = (BURST_MAX_LEN > 1) ? $clog2(BURST_MAX_LEN + 1) : 1;
    localparam int BURST_FIFO_PTR_W = (MAX_OUTSTANDING_BURSTS > 1) ? $clog2(MAX_OUTSTANDING_BURSTS) : 1;
    localparam logic [2:0] AXI_SIZE = $clog2(BYTE_W);

    // 主状态机：
    // - S_IDLE 等待命令
    // - S_ACTIVE 允许持续发 AR 并接 R
    // - S_DRAIN 已发完所有 AR，仅等待余下返回数据
    // - S_ERROR 出错后排空已在途数据
    // - S_DONE 等待状态被上层取走
    typedef enum logic [2:0] {
        S_IDLE,
        S_ACTIVE,
        S_DRAIN,
        S_ERROR,
        S_DONE
    } state_t;

    state_t state_reg; // 当前状态

    logic [ADDR_W-1:0] aligned_start_addr_reg; // 对齐后的任务起始地址

    // 计数器统一扩成 33 位，确保 ceil((offset + byte_count) / BYTE_W) 可表示。
    logic [COUNT_W-1:0] words_total_to_fetch_reg; // 本任务总共要抓取多少个 word
    logic [COUNT_W-1:0] words_requested_reg;      // 已经通过 AR 请求出去多少个 word
    logic [COUNT_W-1:0] words_received_reg;       // 已经从 R 通道收到多少个 word
    logic [COUNT_W-1:0] beats_inflight_reg;       // 当前仍在途的 beat 数
    logic [COUNT_W-1:0] bursts_inflight_reg;      // 当前仍在途的 burst 数

    logic               error_latched_reg;   // 已经检测到致命错误并锁存
    logic               result_pending_reg;  // 有一笔结果等待上层取走
    logic               result_done_reg;     // 等待上层取走的结果为完成
    logic               result_error_reg;    // 等待上层取走的结果为错误

    logic [BURST_COUNT_W-1:0] burst_beats_q [0:MAX_OUTSTANDING_BURSTS-1];
    logic [BURST_FIFO_PTR_W-1:0] burst_head_reg;
    logic [BURST_FIFO_PTR_W-1:0] burst_tail_reg;
    logic [BURST_FIFO_PTR_W:0]   burst_count_reg;

    logic [ADDR_W-1:0] next_burst_addr_calc;
    logic [COUNT_W-1:0] task_addr_offset_calc;
    logic [COUNT_W-1:0] task_words_total_calc;
    logic [COUNT_W-1:0] words_remaining_calc;
    logic [COUNT_W-1:0] bytes_to_4kb_calc;
    logic [COUNT_W-1:0] words_to_4kb_calc;
    logic [COUNT_W-1:0] word_count_ext;
    logic [COUNT_W-1:0] fifo_reserved_words_calc;
    logic [COUNT_W-1:0] fifo_space_calc;
    logic [COUNT_W-1:0] next_burst_beats_calc;
    logic [COUNT_W-1:0] next_burst_beats_ext_calc;
    logic               can_issue_ar_calc;
    logic               expected_rlast;
    logic               ar_fire;
    logic               r_fire;

    // 环形队列指针自增，用来记录每个在途 burst 还剩多少 beat。
    function automatic logic [BURST_FIFO_PTR_W-1:0] ptr_inc(
        input logic [BURST_FIFO_PTR_W-1:0] ptr
    );
        if (ptr == MAX_OUTSTANDING_BURSTS-1) begin
            ptr_inc = '0;
        end else begin
            ptr_inc = ptr + 1'b1;
        end
    endfunction

    initial begin
        if (DATA_W % 8 != 0) $error("axi_burst_reader requires DATA_W to be byte aligned.");
        if (BURST_MAX_LEN < 1 || BURST_MAX_LEN > 256) $error("BURST_MAX_LEN must be in the range 1..256.");
        if (MAX_OUTSTANDING_BEATS < BURST_MAX_LEN) $error("MAX_OUTSTANDING_BEATS must cover one full burst.");
        if (FIFO_DEPTH_WORDS <= MAX_OUTSTANDING_BEATS) $error("FIFO_DEPTH_WORDS should exceed MAX_OUTSTANDING_BEATS.");
    end

    assign ar_fire         = m_axi_rd.arvalid && m_axi_rd.arready;
    assign r_fire          = m_axi_rd.rvalid && m_axi_rd.rready;
    assign task_ready      = (state_reg == S_IDLE) && !result_pending_reg;
    assign word_valid      = r_fire && !error_latched_reg && (m_axi_rd.rresp == 2'b00) && word_ready;
    assign word_data       = m_axi_rd.rdata;
    assign result_valid    = result_pending_reg;
    assign result_done     = result_done_reg;
    assign result_error    = result_error_reg;
    assign word_count_ext = word_count;
    assign expected_rlast  = (burst_count_reg != 0) && (burst_beats_q[burst_head_reg] == 1);

    // 组合预计算：
    // - 下一次突发地址/长度
    // - FIFO 剩余空间
    // - 当前是否允许继续发 AR
    always_comb begin
        task_addr_offset_calc = '0;
        task_addr_offset_calc[AXI_SIZE_W-1:0] = task_addr[AXI_SIZE_W-1:0];
        task_words_total_calc = calc_total_words(task_byte_count, task_addr_offset_calc, BYTE_W);

        next_burst_addr_calc = aligned_start_addr_reg + (words_requested_reg << AXI_SIZE_W);
        words_remaining_calc = words_total_to_fetch_reg - words_requested_reg;

        bytes_to_4kb_calc = 13'd4096 - {1'b0, next_burst_addr_calc[11:0]};
        words_to_4kb_calc = calc_words_to_4kb(next_burst_addr_calc, BYTE_W);

        fifo_reserved_words_calc = word_count_ext + beats_inflight_reg;
        if (fifo_reserved_words_calc >= FIFO_DEPTH_WORDS) begin
            fifo_space_calc = '0;
        end else begin
            fifo_space_calc = FIFO_DEPTH_WORDS - fifo_reserved_words_calc;
        end

        next_burst_beats_calc = calc_burst_words(
            words_remaining_calc,
            words_to_4kb_calc,
            BURST_MAX_LEN,
            fifo_space_calc
        );

        can_issue_ar_calc = 1'b0;
        if ((state_reg == S_ACTIVE) &&
            !m_axi_rd.arvalid &&
            !error_latched_reg &&
            (words_requested_reg < words_total_to_fetch_reg) &&
            !word_almost_full &&
            (bursts_inflight_reg < MAX_OUTSTANDING_BURSTS) &&
            ((beats_inflight_reg + next_burst_beats_calc) <= MAX_OUTSTANDING_BEATS) &&
            (next_burst_beats_calc != 0)) begin
            can_issue_ar_calc = 1'b1;
        end
    end

    // 时序主过程：
    // - 维护在途 burst 队列
    // - 根据 AR/R 握手更新剩余计数
    // - 在 done/error 条件满足时对外发状态
    always_ff @(posedge axi_clk) begin
        logic [BURST_FIFO_PTR_W-1:0] burst_head_next;
        logic [BURST_FIFO_PTR_W-1:0] burst_tail_next;
        logic [BURST_FIFO_PTR_W:0]   burst_count_next;
        logic [COUNT_W-1:0]          words_requested_next;
        logic [COUNT_W-1:0]          words_received_next;
        logic [COUNT_W-1:0]          beats_inflight_next;
        logic [COUNT_W-1:0]          bursts_inflight_next;
        logic                        rresp_error_now;
        logic                        rlast_error_now;
        logic                        fifo_overflow_now;
        logic                        fatal_now;

        if (sys_rst) begin
            state_reg                <= S_IDLE;
            aligned_start_addr_reg   <= '0;
            words_total_to_fetch_reg <= '0;
            words_requested_reg      <= '0;
            words_received_reg       <= '0;
            beats_inflight_reg       <= '0;
            bursts_inflight_reg      <= '0;
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
            rresp_error_now  = r_fire && (m_axi_rd.rresp != 2'b00);
            rlast_error_now  = r_fire && (m_axi_rd.rlast != expected_rlast);
            fifo_overflow_now = r_fire && !error_latched_reg && !word_ready;
            fatal_now        = rresp_error_now || rlast_error_now || fifo_overflow_now;

            burst_head_next  = burst_head_reg;
            burst_tail_next  = burst_tail_reg;
            burst_count_next = burst_count_reg;
            words_requested_next = words_requested_reg;
            words_received_next  = words_received_reg;
            beats_inflight_next  = beats_inflight_reg;
            bursts_inflight_next = bursts_inflight_reg;

            m_axi_rd.rready <= 1'b0;
            case (state_reg)
                S_ACTIVE, S_DRAIN: begin
                    m_axi_rd.rready <= (beats_inflight_reg != 0) && !error_latched_reg && word_ready && !word_almost_full;
                end
                S_ERROR: begin
                    // 出错后仍把已经发出去的 burst 收完，避免总线协议残留。
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

            if (m_axi_rd.arvalid && m_axi_rd.arready) begin
                m_axi_rd.arvalid <= 1'b0;
            end

            if (state_reg == S_IDLE) begin
                error_latched_reg <= 1'b0;
                m_axi_rd.arvalid  <= 1'b0;
                m_axi_rd.rready   <= 1'b0;

                if (task_valid && task_ready) begin
                    aligned_start_addr_reg   <= align_addr(task_addr, AXI_SIZE_W);
                    words_total_to_fetch_reg <= task_words_total_calc;
                    words_requested_reg      <= '0;
                    words_received_reg       <= '0;
                    beats_inflight_reg       <= '0;
                    bursts_inflight_reg      <= '0;
                    burst_head_reg           <= '0;
                    burst_tail_reg           <= '0;
                    burst_count_reg          <= '0;
                    state_reg                <= S_ACTIVE;
                end
            end else begin
                if (can_issue_ar_calc) begin
                    m_axi_rd.arid     <= '0;
                    m_axi_rd.araddr   <= next_burst_addr_calc;
                    m_axi_rd.arlen    <= next_burst_beats_calc[7:0] - 1'b1;
                    m_axi_rd.arsize   <= AXI_SIZE;
                    m_axi_rd.arburst  <= 2'b01;
                    m_axi_rd.arlock   <= 1'b0;
                    m_axi_rd.arcache  <= 4'b0011;
                    m_axi_rd.arprot   <= 3'b000;
                    m_axi_rd.arqos    <= 4'd0;
                    m_axi_rd.arregion <= 4'd0;
                    m_axi_rd.aruser   <= '0;
                    m_axi_rd.arvalid  <= 1'b1;
                end

                next_burst_beats_ext_calc = next_burst_beats_calc;

                if (ar_fire) begin
                    burst_beats_q[burst_tail_reg] <= next_burst_beats_calc[BURST_COUNT_W-1:0];
                    burst_tail_next               = ptr_inc(burst_tail_reg);
                    burst_count_next              = burst_count_next + 1'b1;
                    words_requested_next          = words_requested_next + next_burst_beats_ext_calc;
                    beats_inflight_next           = beats_inflight_next + next_burst_beats_ext_calc;
                    bursts_inflight_next          = bursts_inflight_next + 1'b1;
                end

                if (r_fire) begin
                    words_received_next = words_received_next + 1'b1;
                    if (beats_inflight_next != 0) beats_inflight_next = beats_inflight_next - 1'b1;

                    if (burst_count_reg == 0) begin
                        error_latched_reg <= 1'b1;
                    end else if (expected_rlast) begin
                        burst_head_next = ptr_inc(burst_head_reg);
                        burst_count_next = burst_count_next - 1'b1;
                        if (bursts_inflight_next != 0) bursts_inflight_next = bursts_inflight_next - 1'b1;
                    end else begin
                        burst_beats_q[burst_head_reg] <= burst_beats_q[burst_head_reg] - 1'b1;
                    end

                    if (fatal_now) error_latched_reg <= 1'b1;
                end

                burst_head_reg  <= burst_head_next;
                burst_tail_reg  <= burst_tail_next;
                burst_count_reg <= burst_count_next;
                words_requested_reg <= words_requested_next;
                words_received_reg  <= words_received_next;
                beats_inflight_reg  <= beats_inflight_next;
                bursts_inflight_reg <= bursts_inflight_next;

                case (state_reg)
                    S_ACTIVE: begin
                        if (fatal_now || error_latched_reg) begin
                            m_axi_rd.arvalid <= 1'b0;
                            state_reg        <= S_ERROR;
                        end else if ((words_requested_next == words_total_to_fetch_reg) && (beats_inflight_next == 0)) begin
                            state_reg <= S_DONE;
                        end else if (words_requested_next == words_total_to_fetch_reg) begin
                            state_reg <= S_DRAIN;
                        end
                    end

                    S_DRAIN: begin
                        if (fatal_now || error_latched_reg) begin
                            m_axi_rd.arvalid <= 1'b0;
                            state_reg        <= S_ERROR;
                        end else if (beats_inflight_next == 0) begin
                            state_reg <= S_DONE;
                        end
                    end

                    S_ERROR: begin
                        m_axi_rd.arvalid <= 1'b0;
                        if ((beats_inflight_next == 0) && !result_pending_reg) begin
                            result_pending_reg <= 1'b1;
                            result_done_reg    <= 1'b0;
                            result_error_reg   <= 1'b1;
                        end
                    end

                    S_DONE: begin
                        m_axi_rd.arvalid <= 1'b0;
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

endmodule

