`timescale 1ns/1ps

// 模块职责：
// 1. 将一次任务请求从 src_clk 域传到 dst_clk 域
// 2. 使用 req/ack toggle 握手保证多比特载荷跨时钟域稳定
// 3. 地址和长度载荷与 toggle 捆绑，约束上需保证 bundled-data 路径时序
module task_cdc #(
    parameter int ADDR_W = 32
) (
    input  logic              src_clk,
    input  logic              sys_rst,
    input  logic              task_valid_src,
    input  logic [ADDR_W-1:0] task_addr_src,
    input  logic [31:0]       task_byte_count_src,
    output logic              task_ready_src,
    input  logic              dst_clk,
    output logic              task_valid_dst,
    output logic [ADDR_W-1:0] task_addr_dst,
    output logic [31:0]       task_byte_count_dst,
    input  logic              task_ready_dst
);

    logic              req_toggle_src_reg; // 源时钟域的请求 toggle 寄存器
    logic              ack_toggle_dst_reg; // 目标时钟域的应答 toggle 寄存器
    logic              src_busy_reg;       // 源时钟域的忙标志
    logic [ADDR_W-1:0] task_addr_hold_reg; // 源时钟域的任务地址保持寄存器
    logic [31:0]       task_byte_count_hold_reg; // 源时钟域的任务字节计数保持寄存器
    (* ASYNC_REG = "TRUE" *) logic ack_toggle_src_sync1_reg; // 同步到源时钟域的应答 toggle 寄存器 1
    (* ASYNC_REG = "TRUE" *) logic ack_toggle_src_sync2_reg; // 同步到源时钟域的应答 toggle 寄存器 2
    (* ASYNC_REG = "TRUE" *) logic req_toggle_dst_sync1_reg; // 同步到目标时钟域的请求 toggle 寄存器 1
    (* ASYNC_REG = "TRUE" *) logic req_toggle_dst_sync2_reg; // 同步到目标时钟域的请求 toggle 寄存器 2
    logic req_toggle_dst_seen_reg; // 目标时钟域已看到的请求 toggle 值

    assign task_ready_src = !src_busy_reg;

    always_ff @(posedge src_clk) begin
        if (sys_rst) begin
            req_toggle_src_reg       <= 1'b0;
            src_busy_reg             <= 1'b0;
            task_addr_hold_reg       <= '0;
            task_byte_count_hold_reg <= '0;
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

            if (task_valid_src && !src_busy_reg) begin
                task_addr_hold_reg       <= task_addr_src;
                task_byte_count_hold_reg <= task_byte_count_src;
                req_toggle_src_reg       <= ~req_toggle_src_reg;
                src_busy_reg             <= 1'b1;
            end
        end
    end

    always_ff @(posedge dst_clk) begin
        if (sys_rst) begin
            req_toggle_dst_sync1_reg <= 1'b0;
            req_toggle_dst_sync2_reg <= 1'b0;
            req_toggle_dst_seen_reg  <= 1'b0;
            task_valid_dst           <= 1'b0;
            task_addr_dst            <= '0;
            task_byte_count_dst      <= '0;
            ack_toggle_dst_reg       <= 1'b0;
        end else begin
            req_toggle_dst_sync1_reg <= req_toggle_src_reg;
            req_toggle_dst_sync2_reg <= req_toggle_dst_sync1_reg;

            if (!task_valid_dst && (req_toggle_dst_sync2_reg != req_toggle_dst_seen_reg)) begin
                task_addr_dst           <= task_addr_hold_reg;
                task_byte_count_dst     <= task_byte_count_hold_reg;
                task_valid_dst          <= 1'b1;
                req_toggle_dst_seen_reg <= req_toggle_dst_sync2_reg;
            end

            if (task_valid_dst && task_ready_dst) begin
                task_valid_dst     <= 1'b0;
                ack_toggle_dst_reg <= ~ack_toggle_dst_reg;
            end
        end
    end

endmodule
