`timescale 1ns/1ps

// 模块职责：
// 1. 保存若干条源图像行缓存，供缩放 core 随机读取。
// 2. 支持串行装载单条源行像素。
// 3. 同时提供两个独立读端口，方便 bilinear 等算法并行取样。
module src_line_buffer #(
    parameter int PIXEL_W   = 8,
    parameter int MAX_SRC_W = 7200,
    parameter int LINE_NUM  = 2
) (
    input  logic clk,
    input  logic sys_rst,

    input  logic                                               load_start,
    input  logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0]   load_line_sel,
    input  logic [$clog2(MAX_SRC_W+1)-1:0]                     load_pixel_count,
    output logic                                               load_busy,
    output logic                                               load_done,
    output logic                                               load_error,

    input  logic [PIXEL_W-1:0]                                 in_data,
    input  logic                                               in_valid,
    output logic                                               in_ready,

    input  logic                                               rd0_req_valid,
    input  logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0]   rd0_line_sel,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] rd0_x,
    output logic [PIXEL_W-1:0]                                 rd0_data,
    output logic                                               rd0_data_valid,

    input  logic                                               rd1_req_valid,
    input  logic [(LINE_NUM > 1 ? $clog2(LINE_NUM) : 1)-1:0]   rd1_line_sel,
    input  logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] rd1_x,
    output logic [PIXEL_W-1:0]                                 rd1_data,
    output logic                                               rd1_data_valid
);

    localparam int LINE_SEL_W = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;
    localparam int COUNT_W    = $clog2(MAX_SRC_W+1);

    typedef enum logic [1:0] {
        S_IDLE,
        S_LOAD,
        S_DONE
    } state_t;

    state_t state_reg;
    state_t state_next;

    logic [PIXEL_W-1:0] mem_reg [0:LINE_NUM-1][0:MAX_SRC_W-1];
    logic [LINE_SEL_W-1:0] load_line_sel_reg;
    logic [COUNT_W-1:0]    load_pixel_count_reg;
    logic [COUNT_W-1:0]    load_wr_ptr_reg;

    logic [PIXEL_W-1:0] rd0_data_reg;
    logic [PIXEL_W-1:0] rd1_data_reg;
    logic               rd0_data_valid_reg;
    logic               rd1_data_valid_reg;
    logic               load_fire;

    // 装载状态转移：
    // 空闲时等待 load_start，装载完当前整行后打一拍 load_done。
    always_comb begin
        state_next = state_reg;

        case (state_reg)
            S_IDLE: begin
                if (load_start && (load_pixel_count != 0)) begin
                    state_next = S_LOAD;
                end
            end

            S_LOAD: begin
                if (load_error) begin
                    state_next = S_DONE;
                end else if ((load_wr_ptr_reg == load_pixel_count_reg) && (load_pixel_count_reg != 0)) begin
                    state_next = S_DONE;
                end
            end

            S_DONE: begin
                state_next = S_IDLE;
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    assign load_fire = in_valid && in_ready;

    assign load_busy = (state_reg != S_IDLE);
    assign in_ready  = (state_reg == S_LOAD) &&
        (load_wr_ptr_reg < load_pixel_count_reg) &&
        !load_error;

    assign rd0_data       = rd0_data_reg;
    assign rd0_data_valid = rd0_data_valid_reg;
    assign rd1_data       = rd1_data_reg;
    assign rd1_data_valid = rd1_data_valid_reg;

    // 时序过程：
    // 1. 处理单条源行装载。
    // 2. 按请求从两个读端口返回缓存像素。
    always_ff @(posedge clk) begin
        if (sys_rst) begin
            state_reg            <= S_IDLE;
            load_line_sel_reg    <= '0;
            load_pixel_count_reg <= '0;
            load_wr_ptr_reg      <= '0;
            load_done            <= 1'b0;
            load_error           <= 1'b0;
            rd0_data_reg         <= '0;
            rd1_data_reg         <= '0;
            rd0_data_valid_reg   <= 1'b0;
            rd1_data_valid_reg   <= 1'b0;
        end else begin
            state_reg          <= state_next;
            load_done          <= 1'b0;
            rd0_data_valid_reg <= 1'b0;
            rd1_data_valid_reg <= 1'b0;

            if (rd0_req_valid) begin
                rd0_data_reg       <= mem_reg[rd0_line_sel][rd0_x];
                rd0_data_valid_reg <= 1'b1;
            end

            if (rd1_req_valid) begin
                rd1_data_reg       <= mem_reg[rd1_line_sel][rd1_x];
                rd1_data_valid_reg <= 1'b1;
            end

            case (state_reg)
                S_IDLE: begin
                    load_error <= 1'b0;

                    if (load_start) begin
                        load_line_sel_reg    <= load_line_sel;
                        load_pixel_count_reg <= load_pixel_count;
                        load_wr_ptr_reg      <= '0;

                        if (load_pixel_count > MAX_SRC_W) begin
                            load_error <= 1'b1;
                        end
                    end
                end

                S_LOAD: begin
                    if (load_fire) begin
                        mem_reg[load_line_sel_reg][load_wr_ptr_reg] <= in_data;
                        load_wr_ptr_reg <= load_wr_ptr_reg + 1'b1;
                    end
                end

                S_DONE: begin
                    load_done <= !load_error;
                end

                default: begin
                    state_reg <= S_IDLE;
                end
            endcase
        end
    end

endmodule
