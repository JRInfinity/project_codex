`timescale 1ns/1ps

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
    input  logic              axi_clk,
    input  logic              sys_rst,
    input  logic              task_valid,
    output logic              task_ready,
    input  logic [ADDR_W-1:0] task_addr,
    input  logic [31:0]       task_byte_count,
    output logic              word_valid,
    output logic [DATA_W-1:0] word_data,
    input  logic              word_ready,
    input  logic              word_almost_full,
    input  logic [$clog2(FIFO_DEPTH_WORDS+1)-1:0] word_count,
    output logic              result_valid,
    output logic              result_done,
    output logic              result_error,
    input  logic              result_ready,
    taxi_axi_if.rd_mst        m_axi_rd
);

    localparam int BYTE_W           = DATA_W / 8;
    localparam int AXI_SIZE_W       = (BYTE_W > 1) ? $clog2(BYTE_W) : 1;
    localparam int COUNT_W          = 33;
    localparam int BEAT_COUNT_W     = (MAX_OUTSTANDING_BEATS > 1) ? $clog2(MAX_OUTSTANDING_BEATS + 1) : 1;
    localparam int BURSTS_COUNT_W   = (MAX_OUTSTANDING_BURSTS > 1) ? $clog2(MAX_OUTSTANDING_BURSTS + 1) : 1;
    localparam int BURST_COUNT_W    = (BURST_MAX_LEN > 1) ? $clog2(BURST_MAX_LEN + 1) : 1;
    localparam int BURST_FIFO_PTR_W = (MAX_OUTSTANDING_BURSTS > 1) ? $clog2(MAX_OUTSTANDING_BURSTS) : 1;
    localparam int WORDS_PER_4KB    = 4096 / BYTE_W;
    localparam logic [2:0] AXI_SIZE = $clog2(BYTE_W);

    typedef enum logic [2:0] {
        S_IDLE,
        S_ACTIVE,
        S_DRAIN,
        S_ERROR,
        S_DONE
    } state_t;

    (* fsm_encoding = "sequential" *) state_t state_reg;

    logic [ADDR_W-1:0] aligned_start_addr_reg;
    logic [COUNT_W-1:0] words_total_to_fetch_reg;
    logic [COUNT_W-1:0] words_requested_reg;
    logic [ADDR_W-1:0] next_issue_addr_reg;
    logic [COUNT_W-1:0] words_request_remaining_reg;
    logic [COUNT_W-1:0] next_issue_words_to_4kb_reg;
    logic [COUNT_W-1:0] words_received_reg;
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
            beats_credit_calc = MAX_OUTSTANDING_BEATS - beats_inflight_reg;
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
            request_remaining_nonzero_reg &&
            !word_almost_full &&
            (bursts_inflight_reg < MAX_OUTSTANDING_BURSTS) &&
            (beats_credit_reg != 0)) begin
            can_issue_ar_calc = 1'b1;
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

            if (m_axi_rd.arvalid && m_axi_rd.arready) begin
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
                    aligned_start_addr_reg   <= align_addr(task_addr, AXI_SIZE_W);
                    words_total_to_fetch_reg <= task_words_total_calc;
                    words_requested_reg      <= '0;
                    next_issue_addr_reg      <= align_addr(task_addr, AXI_SIZE_W);
                    words_request_remaining_reg <= task_words_total_calc;
                    next_issue_words_to_4kb_reg <= calc_words_to_4kb(align_addr(task_addr, AXI_SIZE_W), BYTE_W);
                    request_remaining_nonzero_reg <= (task_words_total_calc != 0);
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
                if (issue_commit_valid_reg) begin
                    logic [COUNT_W-1:0] words_request_remaining_after_commit;
                    burst_beats_q[burst_tail_reg] <= issue_commit_beats_reg;
                    burst_tail_next               = ptr_inc(burst_tail_reg);
                    burst_count_next              = burst_count_next + 1'b1;
                    words_requested_next          = words_requested_next + issue_commit_beats_reg;
                    next_issue_addr_reg           <= next_issue_addr_reg + (issue_commit_beats_reg << AXI_SIZE_W);
                    words_request_remaining_after_commit = words_request_remaining_reg - issue_commit_beats_reg;
                    words_request_remaining_reg   <= words_request_remaining_after_commit;
                    request_remaining_nonzero_reg <= (words_request_remaining_after_commit != 0);
                    if (issue_commit_beats_reg == next_issue_words_to_4kb_reg) begin
                        next_issue_words_to_4kb_reg <= WORDS_PER_4KB;
                    end else begin
                        next_issue_words_to_4kb_reg <= next_issue_words_to_4kb_reg - issue_commit_beats_reg;
                    end
                    beats_inflight_next           = beats_inflight_next + issue_commit_beats_reg;
                    bursts_inflight_next          = bursts_inflight_next + 1'b1;
                    issue_commit_valid_reg        <= 1'b0;
                end

                if (can_issue_ar_calc) begin
                    issue_seed_valid_reg           <= 1'b1;
                end

                if (issue_seed_valid_reg && !issue_gate_valid_reg && !issue_plan_valid_reg && !issue_calc_valid_reg && !issue_prep_valid_reg) begin
                    issue_seed_valid_reg           <= 1'b0;
                    issue_gate_valid_reg           <= 1'b1;
                    issue_gate_addr_reg            <= next_issue_addr_reg;
                    issue_gate_words_remaining_reg <= limit_burst_words(words_request_remaining_reg);
                end

                if (issue_gate_valid_reg && !issue_plan_valid_reg && !issue_calc_valid_reg && !issue_prep_valid_reg) begin
                    issue_gate_valid_reg           <= 1'b0;
                    issue_plan_valid_reg           <= 1'b1;
                    issue_plan_addr_reg            <= issue_gate_addr_reg;
                    issue_plan_words_remaining_reg <= issue_gate_words_remaining_reg;
                end

                if (issue_plan_valid_reg && !issue_calc_valid_reg && !issue_prep_valid_reg) begin
                    issue_plan_valid_reg           <= 1'b0;
                    issue_calc_valid_reg           <= 1'b1;
                    issue_calc_addr_reg            <= issue_plan_addr_reg;
                    issue_calc_words_remaining_reg <= issue_plan_words_remaining_reg;
                    issue_calc_words_to_4kb_reg    <= limit_burst_words(next_issue_words_to_4kb_reg);
                end

                if (issue_calc_valid_reg && !issue_prep_valid_reg) begin
                    issue_calc_valid_reg <= 1'b0;
                    issue_prep_valid_reg <= 1'b1;
                    issue_prep_addr_reg  <= issue_calc_addr_reg;
                    issue_prep_beats_reg <= BURST_COUNT_W'(calc_burst_words(
                        issue_calc_words_remaining_reg,
                        issue_calc_words_to_4kb_reg,
                        BURST_MAX_LEN,
                        beats_credit_reg
                    ));
                end

                if (issue_prep_valid_reg && !m_axi_rd.arvalid) begin
                    m_axi_rd.arid     <= '0;
                    m_axi_rd.araddr   <= issue_prep_addr_reg;
                    m_axi_rd.arlen    <= issue_prep_beats_reg - 1'b1;
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
                        end else if ((words_request_remaining_reg == 0) && (beats_inflight_next == 0)) begin
                            state_reg <= S_DONE;
                        end else if (words_request_remaining_reg == 0) begin
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

endmodule
