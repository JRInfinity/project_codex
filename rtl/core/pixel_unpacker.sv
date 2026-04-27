`timescale 1ns/1ps

module pixel_unpacker #(
    parameter int DATA_W  = 32,
    parameter int ADDR_W  = 32,
    parameter int PIXEL_W = 8
) (
    input  logic               core_clk,
    input  logic               sys_rst,
    input  logic               task_start,
    input  logic [ADDR_W-1:0]  task_addr,
    input  logic [31:0]        task_byte_count,
    input  logic [31:0]        task_row_byte_count,
    input  logic               reader_status_valid,
    input  logic               reader_done_evt,
    input  logic               reader_error_evt,
    output logic               fifo_rd_en,
    input  logic [DATA_W-1:0]  fifo_rd_data,
    input  logic               fifo_empty,
    input  logic               fifo_underflow,
    output logic [PIXEL_W-1:0] pixel_data,
    output logic               pixel_valid,
    output logic               pixel_row_last,
    input  logic               pixel_ready,
    output logic               task_done_level,
    output logic               task_error_level,
    output logic               task_done_pulse,
    output logic               task_error_pulse,
    output logic               task_error_flag
);

    localparam int BYTE_W   = DATA_W / 8;
    localparam int OFFSET_W = (BYTE_W > 1) ? $clog2(BYTE_W) : 1;
    localparam int COUNT_W  = 33;

    logic               task_active_reg;
    logic [COUNT_W-1:0] bytes_remaining_reg;
    logic [31:0]        row_bytes_remaining_reg;
    logic [OFFSET_W-1:0] first_offset_reg;
    logic               first_word_reg;
    logic               reader_done_seen_reg;
    logic [DATA_W-1:0]  current_word_reg;
    logic               current_word_valid_reg;
    logic [OFFSET_W-1:0] current_byte_idx_reg;
    logic [OFFSET_W:0]  current_valid_bytes_reg;
    logic               load_new_word;
    logic               pixel_fire;
    logic [OFFSET_W-1:0] next_word_offset_calc;
    logic [COUNT_W-1:0] next_word_valid_bytes_calc;
    logic               terminal_done_calc;
    logic               terminal_error_calc;

    initial begin
        if (DATA_W % 8 != 0) $error("pixel_unpacker requires DATA_W to be byte aligned.");
        if (PIXEL_W != 8) $error("Current pixel_unpacker implementation expects PIXEL_W == 8.");
    end

    assign load_new_word = task_active_reg && !current_word_valid_reg &&
                           (bytes_remaining_reg != 0) && !fifo_empty;
    assign fifo_rd_en    = load_new_word;
    assign pixel_valid   = current_word_valid_reg;
    assign pixel_data    = current_word_reg[current_byte_idx_reg*8 +: PIXEL_W];
    assign pixel_row_last = pixel_valid && (row_bytes_remaining_reg == 32'd1);
    assign pixel_fire    = pixel_valid && pixel_ready;
    assign task_done_level  = terminal_done_calc;
    assign task_error_level = terminal_error_calc;

    always_comb begin
        next_word_offset_calc      = first_word_reg ? first_offset_reg : '0;
        next_word_valid_bytes_calc = BYTE_W - next_word_offset_calc;
        if (next_word_valid_bytes_calc > bytes_remaining_reg) next_word_valid_bytes_calc = bytes_remaining_reg;

        terminal_done_calc = task_active_reg && reader_done_seen_reg &&
                             (bytes_remaining_reg == 0) && !current_word_valid_reg;
        terminal_error_calc = task_active_reg && task_error_flag && !current_word_valid_reg &&
                              ((bytes_remaining_reg == 0) || fifo_empty);
    end

    always_ff @(posedge core_clk) begin
        if (sys_rst) begin
            task_active_reg         <= 1'b0;
            bytes_remaining_reg     <= '0;
            row_bytes_remaining_reg <= '0;
            first_offset_reg        <= '0;
            first_word_reg          <= 1'b0;
            reader_done_seen_reg    <= 1'b0;
            current_word_reg        <= '0;
            current_word_valid_reg  <= 1'b0;
            current_byte_idx_reg    <= '0;
            current_valid_bytes_reg <= '0;
            task_done_pulse         <= 1'b0;
            task_error_pulse        <= 1'b0;
            task_error_flag         <= 1'b0;
        end else begin
            task_done_pulse  <= 1'b0;
            task_error_pulse <= 1'b0;

            if (task_start) begin
                task_active_reg         <= 1'b1;
                bytes_remaining_reg     <= task_byte_count;
                row_bytes_remaining_reg <= task_row_byte_count;
                first_offset_reg        <= task_addr[OFFSET_W-1:0];
                first_word_reg          <= 1'b1;
                reader_done_seen_reg    <= 1'b0;
                current_word_reg        <= '0;
                current_word_valid_reg  <= 1'b0;
                current_byte_idx_reg    <= '0;
                current_valid_bytes_reg <= '0;
                task_error_flag         <= 1'b0;
            end else if (task_active_reg && reader_done_seen_reg &&
                         (bytes_remaining_reg == 0) && !current_word_valid_reg) begin
                task_done_pulse <= 1'b1;
                task_active_reg <= 1'b0;
                task_error_flag <= 1'b0;
            end else if (task_active_reg && task_error_flag && !current_word_valid_reg &&
                         ((bytes_remaining_reg == 0) || fifo_empty)) begin
                task_error_pulse <= 1'b1;
                task_active_reg  <= 1'b0;
            end else begin
                if (reader_status_valid && reader_done_evt) reader_done_seen_reg <= 1'b1;
                if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;
                if (fifo_underflow) task_error_flag <= 1'b1;

                if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&
                    !current_word_valid_reg && fifo_empty) begin
                    task_error_flag <= 1'b1;
                end

                if (load_new_word) begin
                    current_word_reg        <= fifo_rd_data;
                    current_word_valid_reg  <= (next_word_valid_bytes_calc != 0);
                    current_byte_idx_reg    <= next_word_offset_calc;
                    current_valid_bytes_reg <= next_word_valid_bytes_calc[OFFSET_W:0];
                    first_word_reg          <= 1'b0;
                end

                if (pixel_fire) begin
                    bytes_remaining_reg <= bytes_remaining_reg - 1'b1;
                    if (row_bytes_remaining_reg <= 32'd1) begin
                        row_bytes_remaining_reg <= task_row_byte_count;
                    end else begin
                        row_bytes_remaining_reg <= row_bytes_remaining_reg - 1'b1;
                    end

                    if (current_valid_bytes_reg == 1) begin
                        current_word_valid_reg  <= 1'b0;
                        current_valid_bytes_reg <= '0;
                    end else begin
                        current_byte_idx_reg    <= current_byte_idx_reg + 1'b1;
                        current_valid_bytes_reg <= current_valid_bytes_reg - 1'b1;
                    end
                end
            end
        end
    end

endmodule
