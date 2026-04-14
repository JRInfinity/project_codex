`timescale 1ns/1ps

// 模块职责：
// 1. 使用可配置数量的行槽位缓存完整目标行，默认两个槽位实现 ping-pong。
// 2. 先把 core 输出的像素流收成整行，再按 out_start 请求顺序重放给写回模块。
// 3. 通过一个小型 ready 队列维护“哪些槽已装满且等待写回”的先后顺序。
module row_out_buffer #(
    parameter int PIXEL_W   = 8,
    parameter int MAX_DST_W = 600,
    parameter int BUF_NUM   = 2
) (
    input  logic clk,
    input  logic sys_rst,

    input  logic                           row_start,
    input  logic [$clog2(MAX_DST_W+1)-1:0] row_pixel_count,
    output logic                           row_busy,
    output logic                           row_done,
    output logic                           row_error,

    input  logic [PIXEL_W-1:0]             in_data,
    input  logic                           in_valid,
    output logic                           in_ready,

    input  logic                           out_start,
    output logic [PIXEL_W-1:0]             out_data,
    output logic                           out_valid,
    input  logic                           out_ready,
    output logic                           out_done
);

    localparam int COUNT_W     = $clog2(MAX_DST_W+1);
    localparam int ADDR_W      = (MAX_DST_W > 1) ? $clog2(MAX_DST_W) : 1;
    localparam int BUF_SEL_W   = (BUF_NUM > 1) ? $clog2(BUF_NUM) : 1;
    localparam int READY_CNT_W = $clog2(BUF_NUM + 1);

    logic [PIXEL_W-1:0] mem_reg [0:BUF_NUM-1][0:MAX_DST_W-1];

    logic [BUF_NUM-1:0] slot_occupied_reg;
    logic [BUF_NUM-1:0] slot_ready_reg;
    logic [COUNT_W-1:0] slot_pixel_count_reg [0:BUF_NUM-1];

    logic                 fill_active_reg;
    logic [BUF_SEL_W-1:0] fill_sel_reg;
    logic [COUNT_W-1:0]   fill_pixel_count_reg;
    logic [COUNT_W-1:0]   wr_ptr_reg;

    logic                 drain_active_reg;
    logic [BUF_SEL_W-1:0] drain_sel_reg;
    logic [COUNT_W-1:0]   rd_ptr_reg;
    logic [COUNT_W-1:0]   drain_pixel_count_reg;
    logic [PIXEL_W-1:0]   out_data_reg;
    logic                 out_valid_reg;

    logic [BUF_SEL_W-1:0]   ready_queue_reg [0:BUF_NUM-1];
    logic [READY_CNT_W-1:0] ready_count_reg;

    logic                 have_free_slot;
    logic [BUF_SEL_W-1:0] free_slot_sel;
    logic                 in_fire;
    logic                 out_fire;
    logic                 fill_done_fire;
    logic                 drain_done_fire;
    logic [BUF_SEL_W-1:0] drain_sel_next;

    always_comb begin
        have_free_slot = 1'b0;
        free_slot_sel  = '0;
        drain_sel_next = ready_queue_reg[0];

        for (int slot_idx_comb = 0; slot_idx_comb < BUF_NUM; slot_idx_comb++) begin
            if (!have_free_slot && !slot_occupied_reg[slot_idx_comb]) begin
                have_free_slot = 1'b1;
                free_slot_sel  = BUF_SEL_W'(slot_idx_comb);
            end
        end
    end

    assign in_fire         = in_valid && in_ready;
    assign out_fire        = out_valid_reg && out_ready;
    assign fill_done_fire  = in_fire && (wr_ptr_reg == fill_pixel_count_reg - 1'b1);
    assign drain_done_fire = out_fire && (rd_ptr_reg == drain_pixel_count_reg - 1'b1);

    assign row_busy  = !have_free_slot;
    assign in_ready  = fill_active_reg && (wr_ptr_reg < fill_pixel_count_reg);
    assign out_data  = out_data_reg;
    assign out_valid = out_valid_reg;

    always_ff @(posedge clk) begin
        if (sys_rst) begin
            slot_occupied_reg     <= '0;
            slot_ready_reg        <= '0;
            fill_active_reg       <= 1'b0;
            fill_sel_reg          <= '0;
            fill_pixel_count_reg  <= '0;
            wr_ptr_reg            <= '0;
            drain_active_reg      <= 1'b0;
            drain_sel_reg         <= '0;
            rd_ptr_reg            <= '0;
            drain_pixel_count_reg <= '0;
            out_data_reg          <= '0;
            out_valid_reg         <= 1'b0;
            ready_count_reg       <= '0;
            row_done              <= 1'b0;
            row_error             <= 1'b0;
            out_done              <= 1'b0;

            for (int slot_idx_ff = 0; slot_idx_ff < BUF_NUM; slot_idx_ff++) begin
                slot_pixel_count_reg[slot_idx_ff] <= '0;
                ready_queue_reg[slot_idx_ff]      <= '0;
            end
        end else begin
            row_done  <= 1'b0;
            row_error <= 1'b0;
            out_done  <= 1'b0;

            if (row_start) begin
                if ((row_pixel_count == 0) || (row_pixel_count > MAX_DST_W) || fill_active_reg || !have_free_slot) begin
                    row_error <= 1'b1;
                end else begin
                    fill_active_reg                    <= 1'b1;
                    fill_sel_reg                       <= free_slot_sel;
                    fill_pixel_count_reg               <= row_pixel_count;
                    wr_ptr_reg                         <= '0;
                    slot_occupied_reg[free_slot_sel]   <= 1'b1;
                    slot_ready_reg[free_slot_sel]      <= 1'b0;
                    slot_pixel_count_reg[free_slot_sel] <= row_pixel_count;
                end
            end

            if (fill_active_reg && in_fire) begin
                mem_reg[fill_sel_reg][wr_ptr_reg[ADDR_W-1:0]] <= in_data;
                wr_ptr_reg <= wr_ptr_reg + 1'b1;

                if (fill_done_fire) begin
                    if (ready_count_reg == BUF_NUM) begin
                        row_error <= 1'b1;
                    end else begin
                        fill_active_reg                  <= 1'b0;
                        slot_ready_reg[fill_sel_reg]     <= 1'b1;
                        ready_queue_reg[ready_count_reg] <= fill_sel_reg;
                        ready_count_reg                  <= ready_count_reg + 1'b1;
                        row_done                         <= 1'b1;
                    end
                end
            end

            if (out_start && !drain_active_reg) begin
                if (ready_count_reg == 0) begin
                    row_error <= 1'b1;
                end else begin
                    drain_active_reg               <= 1'b1;
                    drain_sel_reg                  <= drain_sel_next;
                    drain_pixel_count_reg          <= slot_pixel_count_reg[drain_sel_next];
                    rd_ptr_reg                     <= '0;
                    out_data_reg                   <= mem_reg[drain_sel_next][0];
                    out_valid_reg                  <= 1'b1;
                    slot_ready_reg[drain_sel_next] <= 1'b0;

                    for (int queue_idx_ff = 0; queue_idx_ff < BUF_NUM-1; queue_idx_ff++) begin
                        ready_queue_reg[queue_idx_ff] <= ready_queue_reg[queue_idx_ff+1];
                    end
                    ready_queue_reg[BUF_NUM-1] <= '0;
                    ready_count_reg            <= ready_count_reg - 1'b1;
                end
            end

            if (drain_active_reg && out_fire) begin
                if (drain_done_fire) begin
                    drain_active_reg                 <= 1'b0;
                    out_valid_reg                    <= 1'b0;
                    out_done                         <= 1'b1;
                    slot_occupied_reg[drain_sel_reg] <= 1'b0;
                    slot_pixel_count_reg[drain_sel_reg] <= '0;
                end else begin
                    rd_ptr_reg    <= rd_ptr_reg + 1'b1;
                    out_data_reg  <= mem_reg[drain_sel_reg][rd_ptr_reg[ADDR_W-1:0] + 1'b1];
                    out_valid_reg <= 1'b1;
                end
            end
        end
    end

endmodule
