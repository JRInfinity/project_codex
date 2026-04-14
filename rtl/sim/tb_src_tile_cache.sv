`timescale 1ns/1ps
// Keep module-level docs in sync if this testbench changes materially.
module tb_src_tile_cache;

    localparam int PIXEL_W   = 8;
    localparam int ADDR_W    = 32;
    localparam int MAX_SRC_W = 32;
    localparam int MAX_SRC_H = 32;
    localparam int TILE_W    = 16;
    localparam int TILE_H    = 16;
    localparam int TILE_NUM  = 2;
    localparam int MEM_BYTES = 4096;

    logic clk;
    logic sys_rst;

    logic                           start;
    logic [ADDR_W-1:0]              src_base_addr;
    logic [ADDR_W-1:0]              src_stride;
    logic [$clog2(MAX_SRC_W+1)-1:0] src_w;
    logic [$clog2(MAX_SRC_H+1)-1:0] src_h;
    logic                           busy;
    logic                           error;

    logic              read_start;
    logic [ADDR_W-1:0] read_addr;
    logic [31:0]       read_byte_count;
    logic              read_busy;
    logic              read_done;
    logic              read_error;
    logic [PIXEL_W-1:0] in_data;
    logic               in_valid;
    logic               in_ready;

    logic                                              sample_req_valid;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x0;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y0;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x1;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y1;
    logic                                              sample_req_ready;
    logic [PIXEL_W-1:0]                                sample_p00;
    logic [PIXEL_W-1:0]                                sample_p01;
    logic [PIXEL_W-1:0]                                sample_p10;
    logic [PIXEL_W-1:0]                                sample_p11;
    logic                                              sample_rsp_valid;
    logic [31:0]                                       stat_read_starts;
    logic [31:0]                                       stat_misses;
    logic [31:0]                                       stat_prefetch_starts;
    logic [31:0]                                       stat_prefetch_hits;

    byte src_mem [0:MEM_BYTES-1];

    logic [ADDR_W-1:0] rd_addr_reg;
    int                rd_remaining_reg;
    int                rd_index_reg;
    int                read_start_count;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    src_tile_cache #(
        .PIXEL_W(PIXEL_W),
        .ADDR_W(ADDR_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .TILE_NUM(TILE_NUM)
    ) dut (
        .clk(clk),
        .sys_rst(sys_rst),
        .start(start),
        .src_base_addr(src_base_addr),
        .src_stride(src_stride),
        .src_w(src_w),
        .src_h(src_h),
        .prefetch_enable(1'b0),
        .busy(busy),
        .error(error),
        .read_start(read_start),
        .read_addr(read_addr),
        .read_byte_count(read_byte_count),
        .read_busy(read_busy),
        .read_done(read_done),
        .read_error(read_error),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .sample_req_valid(sample_req_valid),
        .sample_x0(sample_x0),
        .sample_y0(sample_y0),
        .sample_x1(sample_x1),
        .sample_y1(sample_y1),
        .sample_req_ready(sample_req_ready),
        .sample_p00(sample_p00),
        .sample_p01(sample_p01),
        .sample_p10(sample_p10),
        .sample_p11(sample_p11),
        .sample_rsp_valid(sample_rsp_valid),
        .stat_read_starts(stat_read_starts),
        .stat_misses(stat_misses),
        .stat_prefetch_starts(stat_prefetch_starts),
        .stat_prefetch_hits(stat_prefetch_hits)
    );

    task automatic init_memory;
        int x;
        int y;
        begin
            for (x = 0; x < MEM_BYTES; x = x + 1) begin
                src_mem[x] = 8'h00;
            end

            for (y = 0; y < 20; y = y + 1) begin
                for (x = 0; x < 20; x = x + 1) begin
                    src_mem[32'h0000_0100 + y*20 + x] = byte'(((y * 29) + (x * 9) + 5) & 8'hFF);
                end
            end
        end
    endtask

    task automatic reset_dut;
        begin
            sys_rst           = 1'b1;
            start             = 1'b0;
            src_base_addr     = 32'h0000_0100;
            src_stride        = 32'd20;
            src_w             = 20;
            src_h             = 20;
            sample_req_valid  = 1'b0;
            sample_x0         = '0;
            sample_y0         = '0;
            sample_x1         = '0;
            sample_y1         = '0;
            read_busy         = 1'b0;
            read_done         = 1'b0;
            read_error        = 1'b0;
            in_valid          = 1'b0;
            rd_addr_reg       = '0;
            rd_remaining_reg  = 0;
            rd_index_reg      = 0;
            read_start_count  = 0;
            init_memory();
            repeat (5) @(posedge clk);
            sys_rst = 1'b0;
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    task automatic expect_sample(
        input int x0,
        input int y0,
        input int x1,
        input int y1
    );
        byte exp00;
        byte exp01;
        byte exp10;
        byte exp11;
        begin
            exp00 = src_mem[src_base_addr + y0*src_stride + x0];
            exp01 = src_mem[src_base_addr + y0*src_stride + x1];
            exp10 = src_mem[src_base_addr + y1*src_stride + x0];
            exp11 = src_mem[src_base_addr + y1*src_stride + x1];

            @(posedge clk);
            sample_x0        <= x0;
            sample_y0        <= y0;
            sample_x1        <= x1;
            sample_y1        <= y1;
            sample_req_valid <= 1'b1;

            while (!sample_req_ready) begin
                @(posedge clk);
                if (error) begin
                    $fatal(1, "src_tile_cache raised error while waiting sample (%0d,%0d)-(%0d,%0d)", x0, y0, x1, y1);
                end
            end

            sample_req_valid <= 1'b0;

            while (!sample_rsp_valid) begin
                @(posedge clk);
            end

            if ((sample_p00 !== exp00) || (sample_p01 !== exp01) ||
                (sample_p10 !== exp10) || (sample_p11 !== exp11)) begin
                $fatal(1, "Sample mismatch req=(%0d,%0d)-(%0d,%0d) got={%0d,%0d,%0d,%0d} exp={%0d,%0d,%0d,%0d}",
                    x0, y0, x1, y1, sample_p00, sample_p01, sample_p10, sample_p11, exp00, exp01, exp10, exp11);
            end

            @(posedge clk);
        end
    endtask

    always_ff @(posedge clk) begin
        if (sys_rst) begin
            read_busy        <= 1'b0;
            read_done        <= 1'b0;
            read_error       <= 1'b0;
            in_valid         <= 1'b0;
            rd_addr_reg      <= '0;
            rd_remaining_reg <= 0;
            rd_index_reg     <= 0;
        end else begin
            read_done  <= 1'b0;
            read_error <= 1'b0;

            if (!read_busy && read_start) begin
                read_busy        <= 1'b1;
                rd_addr_reg      <= read_addr;
                rd_remaining_reg <= read_byte_count;
                rd_index_reg     <= 0;
                read_start_count <= read_start_count + 1;
            end

            if (read_busy) begin
                in_valid <= (rd_remaining_reg > 0);
                if (in_valid && in_ready) begin
                    rd_index_reg     <= rd_index_reg + 1;
                    rd_remaining_reg <= rd_remaining_reg - 1;
                    if (rd_remaining_reg == 1) begin
                        read_busy <= 1'b0;
                        read_done <= 1'b1;
                        in_valid  <= 1'b0;
                    end
                end
            end else begin
                in_valid <= 1'b0;
            end
        end
    end

    always_comb begin
        if (read_busy && (rd_remaining_reg > 0)) begin
            in_data = src_mem[rd_addr_reg + rd_index_reg];
        end else begin
            in_data = '0;
        end
    end

    initial begin
        reset_dut();

        expect_sample(2, 3, 3, 4);
        if (read_start_count != 16) begin
            $fatal(1, "First tile fill should issue 16 row reads, got %0d", read_start_count);
        end

        expect_sample(10, 10, 11, 11);
        if (read_start_count != 16) begin
            $fatal(1, "Cache hit should not add row reads, got %0d", read_start_count);
        end

        expect_sample(15, 6, 16, 7);
        if (read_start_count != 32) begin
            $fatal(1, "Crossing into second horizontal tile should add 16 row reads, got %0d", read_start_count);
        end

        expect_sample(3, 15, 4, 16);
        if (read_start_count != 36) begin
            $fatal(1, "Vertical cross should only add the 4-row bottom-edge tile when protected-slot replacement works, got %0d", read_start_count);
        end

        expect_sample(1, 1, 2, 2);
        if (read_start_count != 36) begin
            $fatal(1, "Top-left tile should already be resident after vertical cross recovery, got %0d", read_start_count);
        end

        expect_sample(17, 6, 18, 7);
        if (read_start_count != 52) begin
            $fatal(1, "Revisiting the displaced horizontal tile should add 16 row reads, got %0d", read_start_count);
        end

        if (error) begin
            $fatal(1, "src_tile_cache error flag should remain low");
        end

        $display("tb_src_tile_cache completed");
        $finish;
    end

endmodule
