`timescale 1ns/1ps

module frame_config_cdc #(
    parameter int ADDR_W = 32
) (
    input  logic              src_clk,
    input  logic              sys_rst,
    input  logic              cfg_valid_src,
    input  logic [ADDR_W-1:0] src_base_addr_src,
    input  logic [ADDR_W-1:0] dst_base_addr_src,
    input  logic [ADDR_W-1:0] src_stride_src,
    input  logic [ADDR_W-1:0] dst_stride_src,
    input  logic [15:0]       src_w_src,
    input  logic [15:0]       src_h_src,
    input  logic [15:0]       dst_w_src,
    input  logic [15:0]       dst_h_src,
    input  logic signed [31:0] rot_sin_q16_src,
    input  logic signed [31:0] rot_cos_q16_src,
    input  logic              cache_prefetch_en_src,
    output logic              cfg_ready_src,

    input  logic              dst_clk,
    output logic              cfg_valid_dst, // core域的启动信号：cdc已完成（一个pulse）
    output logic [ADDR_W-1:0] src_base_addr_dst,
    output logic [ADDR_W-1:0] dst_base_addr_dst,
    output logic [ADDR_W-1:0] src_stride_dst,
    output logic [ADDR_W-1:0] dst_stride_dst,
    output logic [15:0]       src_w_dst,
    output logic [15:0]       src_h_dst,
    output logic [15:0]       dst_w_dst,
    output logic [15:0]       dst_h_dst,
    output logic signed [31:0] rot_sin_q16_dst,
    output logic signed [31:0] rot_cos_q16_dst,
    output logic              cache_prefetch_en_dst,
    input  logic              cfg_ready_dst
);

    logic req_toggle_src_reg;
    logic ack_toggle_dst_reg;
    logic src_busy_reg;
    logic [ADDR_W-1:0] src_base_addr_hold_reg;
    logic [ADDR_W-1:0] dst_base_addr_hold_reg;
    logic [ADDR_W-1:0] src_stride_hold_reg;
    logic [ADDR_W-1:0] dst_stride_hold_reg;
    logic [15:0]       src_w_hold_reg;
    logic [15:0]       src_h_hold_reg;
    logic [15:0]       dst_w_hold_reg;
    logic [15:0]       dst_h_hold_reg;
    logic signed [31:0] rot_sin_q16_hold_reg;
    logic signed [31:0] rot_cos_q16_hold_reg;
    logic              cache_prefetch_en_hold_reg;
    (* ASYNC_REG = "TRUE" *) logic ack_toggle_src_sync1_reg;
    (* ASYNC_REG = "TRUE" *) logic ack_toggle_src_sync2_reg;
    (* ASYNC_REG = "TRUE" *) logic req_toggle_dst_sync1_reg;
    (* ASYNC_REG = "TRUE" *) logic req_toggle_dst_sync2_reg;
    logic req_toggle_dst_seen_reg;

    assign cfg_ready_src = !src_busy_reg;

    always_ff @(posedge src_clk) begin
        if (sys_rst) begin
            req_toggle_src_reg          <= 1'b0;
            src_busy_reg                <= 1'b0;
            src_base_addr_hold_reg      <= '0;
            dst_base_addr_hold_reg      <= '0;
            src_stride_hold_reg         <= '0;
            dst_stride_hold_reg         <= '0;
            src_w_hold_reg              <= '0;
            src_h_hold_reg              <= '0;
            dst_w_hold_reg              <= '0;
            dst_h_hold_reg              <= '0;
            rot_sin_q16_hold_reg        <= '0;
            rot_cos_q16_hold_reg        <= 32'sh0001_0000;
            cache_prefetch_en_hold_reg  <= 1'b1;
            ack_toggle_src_sync1_reg    <= 1'b0;
            ack_toggle_src_sync2_reg    <= 1'b0;
        end else begin
            ack_toggle_src_sync1_reg <= ack_toggle_dst_reg;
            ack_toggle_src_sync2_reg <= ack_toggle_src_sync1_reg;

            if (src_busy_reg && (ack_toggle_src_sync2_reg == req_toggle_src_reg)) begin
                src_busy_reg <= 1'b0;
            end

            if (cfg_valid_src && !src_busy_reg) begin
                src_base_addr_hold_reg     <= src_base_addr_src;
                dst_base_addr_hold_reg     <= dst_base_addr_src;
                src_stride_hold_reg        <= src_stride_src;
                dst_stride_hold_reg        <= dst_stride_src;
                src_w_hold_reg             <= src_w_src;
                src_h_hold_reg             <= src_h_src;
                dst_w_hold_reg             <= dst_w_src;
                dst_h_hold_reg             <= dst_h_src;
                rot_sin_q16_hold_reg       <= rot_sin_q16_src;
                rot_cos_q16_hold_reg       <= rot_cos_q16_src;
                cache_prefetch_en_hold_reg <= cache_prefetch_en_src;
                req_toggle_src_reg         <= ~req_toggle_src_reg;
                src_busy_reg               <= 1'b1;
            end
        end
    end

    always_ff @(posedge dst_clk) begin
        if (sys_rst) begin
            req_toggle_dst_sync1_reg <= 1'b0;
            req_toggle_dst_sync2_reg <= 1'b0;
            req_toggle_dst_seen_reg  <= 1'b0;
            cfg_valid_dst            <= 1'b0;
            src_base_addr_dst        <= '0;
            dst_base_addr_dst        <= '0;
            src_stride_dst           <= '0;
            dst_stride_dst           <= '0;
            src_w_dst                <= '0;
            src_h_dst                <= '0;
            dst_w_dst                <= '0;
            dst_h_dst                <= '0;
            rot_sin_q16_dst          <= '0;
            rot_cos_q16_dst          <= 32'sh0001_0000;
            cache_prefetch_en_dst    <= 1'b1;
            ack_toggle_dst_reg       <= 1'b0;
        end else begin
            req_toggle_dst_sync1_reg <= req_toggle_src_reg;
            req_toggle_dst_sync2_reg <= req_toggle_dst_sync1_reg;

            if (!cfg_valid_dst && (req_toggle_dst_sync2_reg != req_toggle_dst_seen_reg)) begin
                src_base_addr_dst     <= src_base_addr_hold_reg;
                dst_base_addr_dst     <= dst_base_addr_hold_reg;
                src_stride_dst        <= src_stride_hold_reg;
                dst_stride_dst        <= dst_stride_hold_reg;
                src_w_dst             <= src_w_hold_reg;
                src_h_dst             <= src_h_hold_reg;
                dst_w_dst             <= dst_w_hold_reg;
                dst_h_dst             <= dst_h_hold_reg;
                rot_sin_q16_dst       <= rot_sin_q16_hold_reg;
                rot_cos_q16_dst       <= rot_cos_q16_hold_reg;
                cache_prefetch_en_dst <= cache_prefetch_en_hold_reg;
                cfg_valid_dst         <= 1'b1;
                req_toggle_dst_seen_reg <= req_toggle_dst_sync2_reg;
            end

            if (cfg_valid_dst && cfg_ready_dst) begin
                cfg_valid_dst      <= 1'b0;
                ack_toggle_dst_reg <= ~ack_toggle_dst_reg;
            end
        end
    end

endmodule
