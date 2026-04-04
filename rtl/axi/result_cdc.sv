// 模块职责：
// 1. 将一次任务结果事件从 src_clk 域传到 dst_clk 域
// 2. 在目标时钟域输出单周期 done/error 脉冲
// 3. 使用 req/ack toggle 握手机制保证跨时钟域稳定传输
// 4. 结果载荷与 toggle 捆绑，约束上需保证 bundled-data 路径时序
module result_cdc (
    input  logic src_clk,
    input  logic sys_rst,
    input  logic result_valid_src,
    input  logic result_done_src,
    input  logic result_error_src,
    output logic result_ready_src,
    input  logic dst_clk,
    output logic result_valid_dst,
    output logic result_done_dst,
    output logic result_error_dst
);

    logic req_toggle_src_reg;
    logic ack_toggle_dst_reg;
    logic src_busy_reg;
    logic result_done_hold_reg;
    logic result_error_hold_reg;
    (* ASYNC_REG = "TRUE" *) logic ack_toggle_src_sync1_reg;
    (* ASYNC_REG = "TRUE" *) logic ack_toggle_src_sync2_reg;
    (* ASYNC_REG = "TRUE" *) logic req_toggle_dst_sync1_reg;
    (* ASYNC_REG = "TRUE" *) logic req_toggle_dst_sync2_reg;
    logic req_toggle_dst_seen_reg;

    assign result_ready_src = !src_busy_reg;

    always_ff @(posedge src_clk) begin
        if (sys_rst) begin
            req_toggle_src_reg       <= 1'b0;
            src_busy_reg             <= 1'b0;
            result_done_hold_reg     <= 1'b0;
            result_error_hold_reg    <= 1'b0;
            ack_toggle_src_sync1_reg <= 1'b0;
            ack_toggle_src_sync2_reg <= 1'b0;
        end else begin
            ack_toggle_src_sync1_reg <= ack_toggle_dst_reg;
            ack_toggle_src_sync2_reg <= ack_toggle_src_sync1_reg;

            // A toggle transfer is complete once the synchronized ack catches
            // up to the current req value.
            if (src_busy_reg && (ack_toggle_src_sync2_reg == req_toggle_src_reg)) begin
                src_busy_reg <= 1'b0;
            end

            if (result_valid_src && !src_busy_reg) begin
                result_done_hold_reg  <= result_done_src;
                result_error_hold_reg <= result_error_src;
                req_toggle_src_reg    <= ~req_toggle_src_reg;
                src_busy_reg          <= 1'b1;
            end
        end
    end

    always_ff @(posedge dst_clk) begin
        if (sys_rst) begin
            req_toggle_dst_sync1_reg <= 1'b0;
            req_toggle_dst_sync2_reg <= 1'b0;
            req_toggle_dst_seen_reg  <= 1'b0;
            ack_toggle_dst_reg       <= 1'b0;
            result_valid_dst         <= 1'b0;
            result_done_dst          <= 1'b0;
            result_error_dst         <= 1'b0;
        end else begin
            req_toggle_dst_sync1_reg <= req_toggle_src_reg;
            req_toggle_dst_sync2_reg <= req_toggle_dst_sync1_reg;

            result_valid_dst <= 1'b0;
            result_done_dst  <= 1'b0;
            result_error_dst <= 1'b0;

            if (req_toggle_dst_sync2_reg != req_toggle_dst_seen_reg) begin
                result_valid_dst        <= 1'b1;
                result_done_dst         <= result_done_hold_reg;
                result_error_dst        <= result_error_hold_reg;
                req_toggle_dst_seen_reg <= req_toggle_dst_sync2_reg;
                ack_toggle_dst_reg      <= ~ack_toggle_dst_reg;
            end
        end
    end

endmodule
