`timescale 1ns/1ps

module cache_stats_cdc (
    input  logic        src_clk,
    input  logic        sys_rst,
    input  logic        stats_valid_src,
    input  logic [31:0] read_starts_src,
    input  logic [31:0] misses_src,
    input  logic [31:0] prefetch_starts_src,
    input  logic [31:0] prefetch_hits_src,
    output logic        stats_ready_src,

    input  logic        dst_clk,
    output logic [31:0] read_starts_dst,
    output logic [31:0] misses_dst,
    output logic [31:0] prefetch_starts_dst,
    output logic [31:0] prefetch_hits_dst
);

    logic req_toggle_src_reg;
    logic ack_toggle_dst_reg;
    logic src_busy_reg;
    logic [31:0] read_starts_hold_reg;
    logic [31:0] misses_hold_reg;
    logic [31:0] prefetch_starts_hold_reg;
    logic [31:0] prefetch_hits_hold_reg;
    (* ASYNC_REG = "TRUE" *) logic ack_toggle_src_sync1_reg;
    (* ASYNC_REG = "TRUE" *) logic ack_toggle_src_sync2_reg;
    (* ASYNC_REG = "TRUE" *) logic req_toggle_dst_sync1_reg;
    (* ASYNC_REG = "TRUE" *) logic req_toggle_dst_sync2_reg;
    logic req_toggle_dst_seen_reg;

    assign stats_ready_src = !src_busy_reg;

    always_ff @(posedge src_clk) begin
        if (sys_rst) begin
            req_toggle_src_reg        <= 1'b0;
            src_busy_reg              <= 1'b0;
            read_starts_hold_reg      <= '0;
            misses_hold_reg           <= '0;
            prefetch_starts_hold_reg  <= '0;
            prefetch_hits_hold_reg    <= '0;
            ack_toggle_src_sync1_reg  <= 1'b0;
            ack_toggle_src_sync2_reg  <= 1'b0;
        end else begin
            ack_toggle_src_sync1_reg <= ack_toggle_dst_reg;
            ack_toggle_src_sync2_reg <= ack_toggle_src_sync1_reg;

            if (src_busy_reg && (ack_toggle_src_sync2_reg == req_toggle_src_reg)) begin
                src_busy_reg <= 1'b0;
            end

            if (stats_valid_src && !src_busy_reg) begin
                read_starts_hold_reg     <= read_starts_src;
                misses_hold_reg          <= misses_src;
                prefetch_starts_hold_reg <= prefetch_starts_src;
                prefetch_hits_hold_reg   <= prefetch_hits_src;
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
            read_starts_dst          <= '0;
            misses_dst               <= '0;
            prefetch_starts_dst      <= '0;
            prefetch_hits_dst        <= '0;
            ack_toggle_dst_reg       <= 1'b0;
        end else begin
            req_toggle_dst_sync1_reg <= req_toggle_src_reg;
            req_toggle_dst_sync2_reg <= req_toggle_dst_sync1_reg;

            if (req_toggle_dst_sync2_reg != req_toggle_dst_seen_reg) begin
                read_starts_dst      <= read_starts_hold_reg;
                misses_dst           <= misses_hold_reg;
                prefetch_starts_dst  <= prefetch_starts_hold_reg;
                prefetch_hits_dst    <= prefetch_hits_hold_reg;
                req_toggle_dst_seen_reg <= req_toggle_dst_sync2_reg;
                ack_toggle_dst_reg   <= ~ack_toggle_dst_reg;
            end
        end
    end

endmodule
