`timescale 1ns/1ps

module reset_sync #(
    parameter int STAGES = 2
) (
    input  logic clk,
    input  logic async_rst,
    output logic sync_rst
);

    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] rst_pipe_reg;

    initial begin
        if (STAGES < 2) begin
            $error("reset_sync STAGES must be >= 2");
        end
    end

    always_ff @(posedge clk or posedge async_rst) begin
        if (async_rst) begin
            rst_pipe_reg <= '1;
        end else begin
            rst_pipe_reg <= {rst_pipe_reg[STAGES-2:0], 1'b0};
        end
    end

    assign sync_rst = rst_pipe_reg[STAGES-1];

endmodule
