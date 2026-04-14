`timescale 1ns/1ps

module row_advance_unit #(
    parameter int COORD_W = 36,
    parameter int FRAC_W  = 16
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     start,
    input  logic signed [COORD_W-1:0] base_x,
    input  logic signed [COORD_W-1:0] base_y,
    input  logic signed [COORD_W-1:0] step_x,
    input  logic signed [COORD_W-1:0] step_y,
    output logic                     busy,
    output logic                     done,
    output logic signed [COORD_W-1:0] next_x,
    output logic signed [COORD_W-1:0] next_y
);
    localparam int ROW_SEG_NUM = 6;
    localparam int ROW_SEG_W  = COORD_W / ROW_SEG_NUM;
    localparam int ROW_SEG1_L = ROW_SEG_W;
    localparam int ROW_SEG2_L = ROW_SEG_W * 2;
    localparam int ROW_SEG3_L = ROW_SEG_W * 3;
    localparam int ROW_SEG4_L = ROW_SEG_W * 4;
    localparam int ROW_SEG5_L = ROW_SEG_W * 5;
    localparam int ROW_TOP_W  = COORD_W - ROW_SEG5_L;

    logic signed [COORD_W-1:0] base_x_hold_reg;
    logic signed [COORD_W-1:0] base_y_hold_reg;
    logic signed [COORD_W-1:0] step_x_hold_reg;
    logic signed [COORD_W-1:0] step_y_hold_reg;
    logic                      axis_reg;
    logic [2:0]                seg_idx_reg;
    logic [ROW_SEG_W:0]        carry_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            busy            <= 1'b0;
            done            <= 1'b0;
            next_x          <= '0;
            next_y          <= '0;
            base_x_hold_reg <= '0;
            base_y_hold_reg <= '0;
            step_x_hold_reg <= '0;
            step_y_hold_reg <= '0;
            axis_reg        <= 1'b0;
            seg_idx_reg     <= '0;
            carry_reg       <= '0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                busy            <= 1'b1;
                base_x_hold_reg <= base_x;
                base_y_hold_reg <= base_y;
                step_x_hold_reg <= step_x;
                step_y_hold_reg <= step_y;
                axis_reg        <= 1'b0;
                seg_idx_reg     <= '0;
                carry_reg       <= '0;
            end else if (busy) begin
                if (!axis_reg) begin
                    case (seg_idx_reg)
                        3'd0: begin
                            carry_reg   <= {1'b0, base_x_hold_reg[ROW_SEG_W-1:0]} +
                                           {1'b0, step_x_hold_reg[ROW_SEG_W-1:0]};
                            seg_idx_reg <= 3'd1;
                        end
                        3'd1: begin
                            next_x[ROW_SEG_W-1:0] <= carry_reg[ROW_SEG_W-1:0];
                            carry_reg <=
                                {1'b0, base_x_hold_reg[ROW_SEG2_L-1:ROW_SEG1_L]} +
                                {1'b0, step_x_hold_reg[ROW_SEG2_L-1:ROW_SEG1_L]} +
                                carry_reg[ROW_SEG_W];
                            seg_idx_reg <= 3'd2;
                        end
                        3'd2: begin
                            next_x[ROW_SEG2_L-1:ROW_SEG1_L] <= carry_reg[ROW_SEG_W-1:0];
                            carry_reg <=
                                {1'b0, base_x_hold_reg[ROW_SEG3_L-1:ROW_SEG2_L]} +
                                {1'b0, step_x_hold_reg[ROW_SEG3_L-1:ROW_SEG2_L]} +
                                carry_reg[ROW_SEG_W];
                            seg_idx_reg <= 3'd3;
                        end
                        3'd3: begin
                            next_x[ROW_SEG3_L-1:ROW_SEG2_L] <= carry_reg[ROW_SEG_W-1:0];
                            carry_reg <=
                                {1'b0, base_x_hold_reg[ROW_SEG4_L-1:ROW_SEG3_L]} +
                                {1'b0, step_x_hold_reg[ROW_SEG4_L-1:ROW_SEG3_L]} +
                                carry_reg[ROW_SEG_W];
                            seg_idx_reg <= 3'd4;
                        end
                        3'd4: begin
                            next_x[ROW_SEG4_L-1:ROW_SEG3_L] <= carry_reg[ROW_SEG_W-1:0];
                            carry_reg <=
                                {1'b0, base_x_hold_reg[ROW_SEG5_L-1:ROW_SEG4_L]} +
                                {1'b0, step_x_hold_reg[ROW_SEG5_L-1:ROW_SEG4_L]} +
                                carry_reg[ROW_SEG_W];
                            seg_idx_reg <= 3'd5;
                        end
                        default: begin
                            next_x[ROW_SEG5_L-1:ROW_SEG4_L] <= carry_reg[ROW_SEG_W-1:0];
                            next_x[COORD_W-1:ROW_SEG5_L] <=
                                $signed({base_x_hold_reg[COORD_W-1], base_x_hold_reg[COORD_W-1:ROW_SEG5_L]}) +
                                $signed({step_x_hold_reg[COORD_W-1], step_x_hold_reg[COORD_W-1:ROW_SEG5_L]}) +
                                $signed({{ROW_TOP_W{1'b0}}, carry_reg[ROW_SEG_W]});
                            axis_reg    <= 1'b1;
                            seg_idx_reg <= '0;
                            carry_reg   <= '0;
                        end
                    endcase
                end else begin
                    case (seg_idx_reg)
                        3'd0: begin
                            carry_reg   <= {1'b0, base_y_hold_reg[ROW_SEG_W-1:0]} +
                                           {1'b0, step_y_hold_reg[ROW_SEG_W-1:0]};
                            seg_idx_reg <= 3'd1;
                        end
                        3'd1: begin
                            next_y[ROW_SEG_W-1:0] <= carry_reg[ROW_SEG_W-1:0];
                            carry_reg <=
                                {1'b0, base_y_hold_reg[ROW_SEG2_L-1:ROW_SEG1_L]} +
                                {1'b0, step_y_hold_reg[ROW_SEG2_L-1:ROW_SEG1_L]} +
                                carry_reg[ROW_SEG_W];
                            seg_idx_reg <= 3'd2;
                        end
                        3'd2: begin
                            next_y[ROW_SEG2_L-1:ROW_SEG1_L] <= carry_reg[ROW_SEG_W-1:0];
                            carry_reg <=
                                {1'b0, base_y_hold_reg[ROW_SEG3_L-1:ROW_SEG2_L]} +
                                {1'b0, step_y_hold_reg[ROW_SEG3_L-1:ROW_SEG2_L]} +
                                carry_reg[ROW_SEG_W];
                            seg_idx_reg <= 3'd3;
                        end
                        3'd3: begin
                            next_y[ROW_SEG3_L-1:ROW_SEG2_L] <= carry_reg[ROW_SEG_W-1:0];
                            carry_reg <=
                                {1'b0, base_y_hold_reg[ROW_SEG4_L-1:ROW_SEG3_L]} +
                                {1'b0, step_y_hold_reg[ROW_SEG4_L-1:ROW_SEG3_L]} +
                                carry_reg[ROW_SEG_W];
                            seg_idx_reg <= 3'd4;
                        end
                        3'd4: begin
                            next_y[ROW_SEG4_L-1:ROW_SEG3_L] <= carry_reg[ROW_SEG_W-1:0];
                            carry_reg <=
                                {1'b0, base_y_hold_reg[ROW_SEG5_L-1:ROW_SEG4_L]} +
                                {1'b0, step_y_hold_reg[ROW_SEG5_L-1:ROW_SEG4_L]} +
                                carry_reg[ROW_SEG_W];
                            seg_idx_reg <= 3'd5;
                        end
                        default: begin
                            next_y[ROW_SEG5_L-1:ROW_SEG4_L] <= carry_reg[ROW_SEG_W-1:0];
                            next_y[COORD_W-1:ROW_SEG5_L] <=
                                $signed({base_y_hold_reg[COORD_W-1], base_y_hold_reg[COORD_W-1:ROW_SEG5_L]}) +
                                $signed({step_y_hold_reg[COORD_W-1], step_y_hold_reg[COORD_W-1:ROW_SEG5_L]}) +
                                $signed({{ROW_TOP_W{1'b0}}, carry_reg[ROW_SEG_W]});
                            busy        <= 1'b0;
                            done        <= 1'b1;
                            axis_reg    <= 1'b0;
                            seg_idx_reg <= '0;
                            carry_reg   <= '0;
                        end
                    endcase
                end
            end
        end
    end

endmodule
