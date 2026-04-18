`timescale 1ns/1ps

// 顶层职责：
// 1. 提供 AXI-Lite 寄存器接口，用于配置源图和目标图的地址、尺寸、步长以及启动控制。
// 2. 串接 DDR 读写、源行缓存、bilinear core 和结果写回，形成完整的缩放数据通路。
// 3. 汇总完成和错误状态，并通过中断与状态寄存器对外反馈当前任务进度。
module image_geo_top #(
    parameter int AXIL_ADDR_W = 12,
    parameter int AXIL_DATA_W = 32,
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32,
    parameter int AXI_ID_W    = 4,
    parameter int PIXEL_W     = 8,
    parameter int MAX_SRC_W   = 7200,
    parameter int MAX_SRC_H   = 7200,
    parameter int MAX_DST_W   = 600,
    parameter int MAX_DST_H   = 600,
    parameter int LINE_NUM    = 2
) (
    input  logic                         axi_clk,
    input  logic                         axi_rstn,
    input  logic                         core_clk,
    input  logic                         core_rstn,

    output logic                         irq,

    input  logic [AXIL_ADDR_W-1:0]       s_axi_ctrl_awaddr,
    input  logic [2:0]                   s_axi_ctrl_awprot,
    input  logic                         s_axi_ctrl_awvalid,
    output logic                         s_axi_ctrl_awready,
    input  logic [AXIL_DATA_W-1:0]       s_axi_ctrl_wdata,
    input  logic [(AXIL_DATA_W/8)-1:0]   s_axi_ctrl_wstrb,
    input  logic                         s_axi_ctrl_wvalid,
    output logic                         s_axi_ctrl_wready,
    output logic [1:0]                   s_axi_ctrl_bresp,
    output logic                         s_axi_ctrl_bvalid,
    input  logic                         s_axi_ctrl_bready,
    input  logic [AXIL_ADDR_W-1:0]       s_axi_ctrl_araddr,
    input  logic [2:0]                   s_axi_ctrl_arprot,
    input  logic                         s_axi_ctrl_arvalid,
    output logic                         s_axi_ctrl_arready,
    output logic [AXIL_DATA_W-1:0]       s_axi_ctrl_rdata,
    output logic [1:0]                   s_axi_ctrl_rresp,
    output logic                         s_axi_ctrl_rvalid,
    input  logic                         s_axi_ctrl_rready,

    // DDR读口
    output logic [AXI_ID_W-1:0]          m_axi_rd_arid,
    output logic [AXI_ADDR_W-1:0]        m_axi_rd_araddr,
    output logic [7:0]                   m_axi_rd_arlen,
    output logic [2:0]                   m_axi_rd_arsize,
    output logic [1:0]                   m_axi_rd_arburst,
    output logic                         m_axi_rd_arlock,
    output logic [3:0]                   m_axi_rd_arcache,
    output logic [2:0]                   m_axi_rd_arprot,
    output logic [3:0]                   m_axi_rd_arqos,
    output logic [3:0]                   m_axi_rd_arregion,
    output logic                         m_axi_rd_arvalid,
    input  logic                         m_axi_rd_arready,
    input  logic [AXI_ID_W-1:0]          m_axi_rd_rid,
    input  logic [AXI_DATA_W-1:0]        m_axi_rd_rdata,
    input  logic [1:0]                   m_axi_rd_rresp,
    input  logic                         m_axi_rd_rlast,
    input  logic                         m_axi_rd_rvalid,
    output logic                         m_axi_rd_rready,

    // DDR写口
    output logic [AXI_ID_W-1:0]          m_axi_wr_awid,
    output logic [AXI_ADDR_W-1:0]        m_axi_wr_awaddr,
    output logic [7:0]                   m_axi_wr_awlen,
    output logic [2:0]                   m_axi_wr_awsize,
    output logic [1:0]                   m_axi_wr_awburst,
    output logic                         m_axi_wr_awlock,
    output logic [3:0]                   m_axi_wr_awcache,
    output logic [2:0]                   m_axi_wr_awprot,
    output logic [3:0]                   m_axi_wr_awqos,
    output logic [3:0]                   m_axi_wr_awregion,
    output logic                         m_axi_wr_awvalid,
    input  logic                         m_axi_wr_awready,
    output logic [AXI_DATA_W-1:0]        m_axi_wr_wdata,
    output logic [(AXI_DATA_W/8)-1:0]    m_axi_wr_wstrb,
    output logic                         m_axi_wr_wlast,
    output logic                         m_axi_wr_wvalid,
    input  logic                         m_axi_wr_wready,
    input  logic [AXI_ID_W-1:0]          m_axi_wr_bid,
    input  logic [1:0]                   m_axi_wr_bresp,
    input  logic                         m_axi_wr_bvalid,
    output logic                         m_axi_wr_bready
);

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    localparam logic [AXIL_ADDR_W-1:0] REG_CTRL_ADDR       = 12'h000;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_BASE_ADDR   = 12'h004;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_BASE_ADDR   = 12'h008;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_STRIDE_ADDR = 12'h00C;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_STRIDE_ADDR = 12'h010;
    localparam logic [AXIL_ADDR_W-1:0] REG_SRC_SIZE_ADDR   = 12'h014;
    localparam logic [AXIL_ADDR_W-1:0] REG_DST_SIZE_ADDR   = 12'h018;
    localparam logic [AXIL_ADDR_W-1:0] REG_STATUS_ADDR     = 12'h01C;
    localparam logic [AXIL_ADDR_W-1:0] REG_ROT_SIN_ADDR    = 12'h020; // 旋转角度的正弦值，采用 Q16 定点格式表示，范围 [-1, 1) 映射到 [-65536, 65535] 之间。
    localparam logic [AXIL_ADDR_W-1:0] REG_ROT_COS_ADDR    = 12'h024; // 旋转角度的余弦值，采用 Q16 定点格式表示，范围 [-1, 1) 映射到 [-65536, 65535] 之间。
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_READS_ADDR = 12'h028;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_MISSES_ADDR = 12'h02C;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_PREFETCH_ADDR = 12'h030;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_PREFETCH_HIT_ADDR = 12'h034;
    localparam logic [AXIL_ADDR_W-1:0] REG_CACHE_CTRL_ADDR = 12'h038;

    localparam int LINE_SEL_W   = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;
    localparam int SRC_X_W      = $clog2(MAX_SRC_W+1);
    localparam int SRC_Y_W      = $clog2(MAX_SRC_H+1);
    localparam int DST_X_W      = $clog2(MAX_DST_W+1);
    localparam int DST_Y_W      = $clog2(MAX_DST_H+1);
    localparam int CORE_SRC_Y_W = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;

    logic sys_rst;
    logic axi_sys_rst;
    logic core_sys_rst;

    logic axil_aw_hold_valid_reg;
    logic axil_w_hold_valid_reg;
    logic axil_ar_hold_valid_reg;
    logic [AXIL_ADDR_W-1:0] axil_awaddr_reg;
    logic [AXIL_DATA_W-1:0] axil_wdata_reg;
    logic [(AXIL_DATA_W/8)-1:0] axil_wstrb_reg;
    logic [AXIL_ADDR_W-1:0] axil_araddr_reg;
    logic [AXIL_DATA_W-1:0] axil_rdata_next;
    logic                   axil_read_addr_hit;

    logic [AXI_ADDR_W-1:0] reg_src_base_addr;
    logic [AXI_ADDR_W-1:0] reg_dst_base_addr;
    logic [AXI_ADDR_W-1:0] reg_src_stride;
    logic [AXI_ADDR_W-1:0] reg_dst_stride;
    logic [15:0]           reg_src_w;
    logic [15:0]           reg_src_h;
    logic [15:0]           reg_dst_w;
    logic [15:0]           reg_dst_h;
    logic signed [31:0]    reg_rot_sin_q16;
    logic signed [31:0]    reg_rot_cos_q16;
    logic                  reg_cache_prefetch_en;
    logic                  reg_irq_en;
    logic                  start_pulse_reg;
    logic                  done_sticky_reg;
    logic                  error_sticky_reg;
    logic [AXI_ADDR_W-1:0] core_src_base_addr;
    logic [AXI_ADDR_W-1:0] core_dst_base_addr;
    logic [AXI_ADDR_W-1:0] core_src_stride;
    logic [AXI_ADDR_W-1:0] core_dst_stride;
    logic [15:0]           core_src_w_cfg;
    logic [15:0]           core_src_h_cfg;
    logic [15:0]           core_dst_w_cfg;
    logic [15:0]           core_dst_h_cfg;
    logic signed [31:0]    core_rot_sin_q16;
    logic signed [31:0]    core_rot_cos_q16;
    logic                  core_cache_prefetch_en;
    logic                  core_cfg_valid;
    logic                  core_cfg_ready;
    logic                  cfg_ready_axi;
    logic                  ctrl_busy_core;
    logic                  ctrl_done_core;
    logic                  ctrl_error_core;
    logic                  ctrl_busy_axi_reg;
    logic                  ctrl_result_valid_axi;
    logic                  ctrl_result_done_axi;
    logic                  ctrl_result_error_axi;

    logic                  read_busy_core;
    logic                  read_done_core;
    logic                  read_error_core;
    logic [PIXEL_W-1:0]    read_out_data;
    logic                  read_out_valid;
    logic                  read_out_ready;

    logic                  core_start;
    logic                  core_busy;
    logic                  core_done;
    logic                  core_error;
    logic                  src_cache_error;
    logic                  cache_read_start;
    logic [AXI_ADDR_W-1:0] cache_read_addr;
    logic [31:0]           cache_read_byte_count;
    logic                  cache_read_busy;
    logic                  cache_read_done;
    logic                  cache_read_error;
    logic                  sample_req_valid;
    logic                  sample_req_ready;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x0;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y0;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x1;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y1;
    logic [PIXEL_W-1:0]    cache_sample_p00;
    logic [PIXEL_W-1:0]    cache_sample_p01;
    logic [PIXEL_W-1:0]    cache_sample_p10;
    logic [PIXEL_W-1:0]    cache_sample_p11;
    logic                  cache_sample_rsp_valid;
    logic [PIXEL_W-1:0]    sample_p00;
    logic [PIXEL_W-1:0]    sample_p01;
    logic [PIXEL_W-1:0]    sample_p10;
    logic [PIXEL_W-1:0]    sample_p11;
    logic                  sample_rsp_valid;
    logic signed [1:0]     sample_scan_dir_x;
    logic signed [1:0]     sample_scan_dir_y;
    logic                  sample_scan_dir_valid;
    logic [31:0]           src_cache_stat_read_starts;
    logic [31:0]           src_cache_stat_misses;
    logic [31:0]           src_cache_stat_prefetch_starts;
    logic [31:0]           src_cache_stat_prefetch_hits;
    logic [31:0]           src_cache_stat_read_starts_axi;
    logic [31:0]           src_cache_stat_misses_axi;
    logic [31:0]           src_cache_stat_prefetch_starts_axi;
    logic [31:0]           src_cache_stat_prefetch_hits_axi;
    logic                  core_pix_valid;
    logic                  core_pix_ready;
    logic [PIXEL_W-1:0]    core_pix_data;
    logic                  core_pix_pipe_valid_reg;
    logic [PIXEL_W-1:0]    core_pix_pipe_data_reg;
    logic                  row_in_valid;
    logic [PIXEL_W-1:0]    row_in_data;
    logic                  row_in_ready;
    logic                  core_row_done;

    logic                           row_start;
    logic [DST_X_W-1:0]             row_pixel_count;
    logic                           row_busy;
    logic                           row_done_fill;
    logic                           row_error;
    logic                           row_out_start;
    logic [PIXEL_W-1:0]             row_out_data;
    logic                           row_out_valid;
    logic                           row_out_ready;
    logic                           row_out_done;

    logic                  write_start;
    logic [AXI_ADDR_W-1:0] write_addr;
    logic [31:0]           write_byte_count;
    logic                  write_busy;
    logic                  write_done;
    logic                  write_error;
    logic                    unused_signals;

    taxi_axi_if #(
        .DATA_W(AXI_DATA_W),
        .ADDR_W(AXI_ADDR_W),
        .ID_W(AXI_ID_W)
    ) m_axi_rd_if ();

    taxi_axi_if #(
        .DATA_W(AXI_DATA_W),
        .ADDR_W(AXI_ADDR_W),
        .ID_W(AXI_ID_W)
    ) m_axi_wr_if ();

    initial begin
        if (AXIL_DATA_W != 32) $error("image_geo_top currently expects AXI-Lite data width = 32.");
        if (AXI_DATA_W != 32)  $error("image_geo_top currently expects AXI data width = 32.");
        if (PIXEL_W != 8)      $error("image_geo_top currently expects PIXEL_W = 8.");
    end

    // 系统复位由 AXI 侧低有效复位翻转得到，控制寄存器与主数据链路共用该时钟域。
    assign axi_sys_rst = ~axi_rstn;
    assign core_sys_rst = ~core_rstn;
    assign sys_rst = axi_sys_rst || core_sys_rst;

    assign s_axi_ctrl_awready = !axil_aw_hold_valid_reg && !s_axi_ctrl_bvalid;
    assign s_axi_ctrl_wready  = !axil_w_hold_valid_reg && !s_axi_ctrl_bvalid;
    assign s_axi_ctrl_arready = !axil_ar_hold_valid_reg && !s_axi_ctrl_rvalid;

    // AXI-Lite 读通路：根据寄存器地址返回当前配置、状态以及统计信息。
    always_comb begin
        axil_rdata_next    = '0;
        axil_read_addr_hit = 1'b1;

        case (axil_araddr_reg)
            REG_CTRL_ADDR: begin
                axil_rdata_next[0] = 1'b0;
                axil_rdata_next[1] = reg_irq_en;
            end
            REG_SRC_BASE_ADDR: begin
                axil_rdata_next = reg_src_base_addr;
            end
            REG_DST_BASE_ADDR: begin
                axil_rdata_next = reg_dst_base_addr;
            end
            REG_SRC_STRIDE_ADDR: begin
                axil_rdata_next = reg_src_stride;
            end
            REG_DST_STRIDE_ADDR: begin
                axil_rdata_next = reg_dst_stride;
            end
            REG_SRC_SIZE_ADDR: begin
                axil_rdata_next[15:0]  = reg_src_w;
                axil_rdata_next[31:16] = reg_src_h;
            end
            REG_DST_SIZE_ADDR: begin
                axil_rdata_next[15:0]  = reg_dst_w;
                axil_rdata_next[31:16] = reg_dst_h;
            end
            REG_STATUS_ADDR: begin
                axil_rdata_next[0] = ctrl_busy_axi_reg;
                axil_rdata_next[1] = done_sticky_reg;
                axil_rdata_next[2] = error_sticky_reg;
                axil_rdata_next[8] = 1'b0;
                axil_rdata_next[9] = 1'b0;
            end
            REG_ROT_SIN_ADDR: begin
                axil_rdata_next = reg_rot_sin_q16;
            end
            REG_ROT_COS_ADDR: begin
                axil_rdata_next = reg_rot_cos_q16;
            end
            REG_CACHE_READS_ADDR: begin
                axil_rdata_next = src_cache_stat_read_starts_axi;
            end
            REG_CACHE_MISSES_ADDR: begin
                axil_rdata_next = src_cache_stat_misses_axi;
            end
            REG_CACHE_PREFETCH_ADDR: begin
                axil_rdata_next = src_cache_stat_prefetch_starts_axi;
            end
            REG_CACHE_PREFETCH_HIT_ADDR: begin
                axil_rdata_next = src_cache_stat_prefetch_hits_axi;
            end
            REG_CACHE_CTRL_ADDR: begin
                axil_rdata_next[0] = reg_cache_prefetch_en;
            end
            default: begin
                axil_read_addr_hit = 1'b0;
            end
        endcase
    end

    logic write_fire;
    logic read_fire;

    // AXI-Lite 写通路：缓存 AW/W 通道后统一提交寄存器写入，并维护读写响应握手。
    always_ff @(posedge axi_clk) begin
        if (axi_sys_rst) begin
            axil_aw_hold_valid_reg <= 1'b0;
            axil_w_hold_valid_reg  <= 1'b0;
            axil_ar_hold_valid_reg <= 1'b0;
            axil_awaddr_reg        <= '0;
            axil_wdata_reg         <= '0;
            axil_wstrb_reg         <= '0;
            axil_araddr_reg        <= '0;
            s_axi_ctrl_bvalid      <= 1'b0;
            s_axi_ctrl_bresp       <= AXI_RESP_OKAY;
            s_axi_ctrl_rvalid      <= 1'b0;
            s_axi_ctrl_rresp       <= AXI_RESP_OKAY;
            s_axi_ctrl_rdata       <= '0;

            reg_src_base_addr      <= '0;
            reg_dst_base_addr      <= '0;
            reg_src_stride         <= '0;
            reg_dst_stride         <= '0;
            reg_src_w              <= '0;
            reg_src_h              <= '0;
            reg_dst_w              <= '0;
            reg_dst_h              <= '0;
            reg_rot_sin_q16        <= '0;
            reg_rot_cos_q16        <= 32'sh0001_0000;
            reg_cache_prefetch_en  <= 1'b1;
            reg_irq_en             <= 1'b0;
            start_pulse_reg        <= 1'b0;
            done_sticky_reg        <= 1'b0;
            error_sticky_reg       <= 1'b0;
            ctrl_busy_axi_reg      <= 1'b0;
        end else begin
            write_fire = axil_aw_hold_valid_reg && axil_w_hold_valid_reg && !s_axi_ctrl_bvalid;
            read_fire  = axil_ar_hold_valid_reg && !s_axi_ctrl_rvalid;
            start_pulse_reg <= 1'b0;

            if (ctrl_result_done_axi) begin
                done_sticky_reg <= 1'b1;
            end
            if (ctrl_result_error_axi) begin
                error_sticky_reg <= 1'b1;
            end
            if (ctrl_result_valid_axi) begin
                ctrl_busy_axi_reg <= 1'b0;
            end

            if (s_axi_ctrl_awready && s_axi_ctrl_awvalid) begin
                axil_aw_hold_valid_reg <= 1'b1;
                axil_awaddr_reg        <= s_axi_ctrl_awaddr;
            end

            if (s_axi_ctrl_wready && s_axi_ctrl_wvalid) begin
                axil_w_hold_valid_reg <= 1'b1;
                axil_wdata_reg        <= s_axi_ctrl_wdata;
                axil_wstrb_reg        <= s_axi_ctrl_wstrb;
            end

            if (s_axi_ctrl_arready && s_axi_ctrl_arvalid) begin
                axil_ar_hold_valid_reg <= 1'b1;
                axil_araddr_reg        <= s_axi_ctrl_araddr;
            end

            if (write_fire) begin
                s_axi_ctrl_bvalid      <= 1'b1;
                s_axi_ctrl_bresp       <= AXI_RESP_OKAY;
                axil_aw_hold_valid_reg <= 1'b0;
                axil_w_hold_valid_reg  <= 1'b0;

                case (axil_awaddr_reg)
                    REG_CTRL_ADDR: begin
                        if (axil_wstrb_reg[0]) begin
                            reg_irq_en <= axil_wdata_reg[1];
                            if (axil_wdata_reg[0] && !ctrl_busy_axi_reg && cfg_ready_axi) begin
                                start_pulse_reg  <= 1'b1;
                                done_sticky_reg  <= 1'b0;
                                error_sticky_reg <= 1'b0;
                                ctrl_busy_axi_reg <= 1'b1;
                            end
                        end
                    end
                    REG_SRC_BASE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_src_base_addr[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_src_base_addr[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_src_base_addr[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_src_base_addr[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_DST_BASE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_dst_base_addr[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_dst_base_addr[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_dst_base_addr[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_dst_base_addr[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_SRC_STRIDE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_src_stride[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_src_stride[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_src_stride[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_src_stride[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_DST_STRIDE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_dst_stride[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_dst_stride[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_dst_stride[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_dst_stride[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_SRC_SIZE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_src_w[7:0]  <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_src_w[15:8] <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_src_h[7:0]  <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_src_h[15:8] <= axil_wdata_reg[31:24];
                    end
                    REG_DST_SIZE_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_dst_w[7:0]  <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_dst_w[15:8] <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_dst_h[7:0]  <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_dst_h[15:8] <= axil_wdata_reg[31:24];
                    end
                    REG_STATUS_ADDR: begin
                        if (axil_wstrb_reg[0]) begin
                            if (axil_wdata_reg[1]) done_sticky_reg  <= 1'b0;
                            if (axil_wdata_reg[2]) error_sticky_reg <= 1'b0;
                        end
                    end
                    REG_ROT_SIN_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_rot_sin_q16[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_rot_sin_q16[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_rot_sin_q16[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_rot_sin_q16[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_ROT_COS_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_rot_cos_q16[7:0]   <= axil_wdata_reg[7:0];
                        if (axil_wstrb_reg[1]) reg_rot_cos_q16[15:8]  <= axil_wdata_reg[15:8];
                        if (axil_wstrb_reg[2]) reg_rot_cos_q16[23:16] <= axil_wdata_reg[23:16];
                        if (axil_wstrb_reg[3]) reg_rot_cos_q16[31:24] <= axil_wdata_reg[31:24];
                    end
                    REG_CACHE_CTRL_ADDR: begin
                        if (axil_wstrb_reg[0]) reg_cache_prefetch_en <= axil_wdata_reg[0];
                    end
                    default: begin
                        s_axi_ctrl_bresp <= AXI_RESP_SLVERR;
                    end
                endcase
            end

            if (s_axi_ctrl_bvalid && s_axi_ctrl_bready) begin
                s_axi_ctrl_bvalid <= 1'b0;
            end

            if (read_fire) begin
                s_axi_ctrl_rvalid      <= 1'b1;
                s_axi_ctrl_rresp       <= axil_read_addr_hit ? AXI_RESP_OKAY : AXI_RESP_SLVERR;
                s_axi_ctrl_rdata       <= axil_rdata_next;
                axil_ar_hold_valid_reg <= 1'b0;
            end

            if (s_axi_ctrl_rvalid && s_axi_ctrl_rready) begin
                s_axi_ctrl_rvalid <= 1'b0;
            end
        end
    end

    assign irq = reg_irq_en && (done_sticky_reg || error_sticky_reg);

    frame_config_cdc #(
        .ADDR_W(AXI_ADDR_W)
    ) u_frame_config_cdc (
        .src_clk(axi_clk),
        .sys_rst(sys_rst),
        .cfg_valid_src(start_pulse_reg),
        .src_base_addr_src(reg_src_base_addr),
        .dst_base_addr_src(reg_dst_base_addr),
        .src_stride_src(reg_src_stride),
        .dst_stride_src(reg_dst_stride),
        .src_w_src(reg_src_w),
        .src_h_src(reg_src_h),
        .dst_w_src(reg_dst_w),
        .dst_h_src(reg_dst_h),
        .rot_sin_q16_src(reg_rot_sin_q16),
        .rot_cos_q16_src(reg_rot_cos_q16),
        .cache_prefetch_en_src(reg_cache_prefetch_en),
        .cfg_ready_src(cfg_ready_axi),
        .dst_clk(core_clk),
        .cfg_valid_dst(core_cfg_valid),
        .src_base_addr_dst(core_src_base_addr),
        .dst_base_addr_dst(core_dst_base_addr),
        .src_stride_dst(core_src_stride),
        .dst_stride_dst(core_dst_stride),
        .src_w_dst(core_src_w_cfg),
        .src_h_dst(core_src_h_cfg),
        .dst_w_dst(core_dst_w_cfg),
        .dst_h_dst(core_dst_h_cfg),
        .rot_sin_q16_dst(core_rot_sin_q16),
        .rot_cos_q16_dst(core_rot_cos_q16),
        .cache_prefetch_en_dst(core_cache_prefetch_en),
        .cfg_ready_dst(core_cfg_ready)
    );

    result_cdc u_ctrl_result_cdc (
        .src_clk(core_clk),
        .sys_rst(sys_rst),
        .result_valid_src(ctrl_done_core || ctrl_error_core),
        .result_done_src(ctrl_done_core),
        .result_error_src(ctrl_error_core),
        .result_ready_src(),
        .dst_clk(axi_clk),
        .result_valid_dst(ctrl_result_valid_axi),
        .result_done_dst(ctrl_result_done_axi),
        .result_error_dst(ctrl_result_error_axi)
    );

    cache_stats_cdc u_cache_stats_cdc (
        .src_clk(core_clk),
        .sys_rst(sys_rst),
        .stats_valid_src(ctrl_done_core || ctrl_error_core),
        .read_starts_src(src_cache_stat_read_starts),
        .misses_src(src_cache_stat_misses),
        .prefetch_starts_src(src_cache_stat_prefetch_starts),
        .prefetch_hits_src(src_cache_stat_prefetch_hits),
        .stats_ready_src(),
        .dst_clk(axi_clk),
        .read_starts_dst(src_cache_stat_read_starts_axi),
        .misses_dst(src_cache_stat_misses_axi),
        .prefetch_starts_dst(src_cache_stat_prefetch_starts_axi),
        .prefetch_hits_dst(src_cache_stat_prefetch_hits_axi)
    );

    assign core_cfg_ready = !ctrl_busy_core;


    // 缩放链路主控：负责源行缓存预装、core 启动和结果写回时序。
    scaler_ctrl #(
        .PIXEL_W(PIXEL_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .LINE_NUM(LINE_NUM)
    ) u_scaler_ctrl (
        .clk(core_clk),
        .sys_rst(core_sys_rst),
        .start(core_cfg_valid),
        .src_base_addr(core_src_base_addr),
        .dst_base_addr(core_dst_base_addr),
        .src_stride(core_src_stride),
        .dst_stride(core_dst_stride),
        .src_w(core_src_w_cfg[SRC_X_W-1:0]),
        .src_h(core_src_h_cfg[SRC_Y_W-1:0]),
        .dst_w(core_dst_w_cfg[DST_X_W-1:0]),
        .dst_h(core_dst_h_cfg[DST_Y_W-1:0]),
        .busy(ctrl_busy_core),
        .done(ctrl_done_core),
        .error(ctrl_error_core),
        .core_start(core_start),
        .core_busy(core_busy),
        .core_done(core_done),
        .core_error(core_error),
        .row_done(core_row_done),
        .wb_start(row_start),
        .wb_pixel_count(row_pixel_count),
        .wb_busy(row_busy),
        .wb_done_buf(row_done_fill),
        .wb_error(row_error),
        .wb_out_start(row_out_start),
        .wb_out_done(row_out_done),

        .write_start(write_start),
        .write_addr(write_addr),
        .write_byte_count(write_byte_count),
        .write_busy(write_busy),
        .write_done(write_done),
        .write_error(write_error)
    );

    // 主数据链路依次连接 DDR 读取、源行缓存、bilinear core、行缓冲和 DDR 写回。
    src_tile_cache #(
        .PIXEL_W(PIXEL_W),
        .ADDR_W(AXI_ADDR_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .TILE_W(16),
        .TILE_H(16),
        .TILE_NUM(4)
    ) u_src_tile_cache (
        .clk(core_clk),
        .sys_rst(core_sys_rst),
        .start(core_cfg_valid),
        .src_base_addr(core_src_base_addr),
        .src_stride(core_src_stride),
        .src_w(core_src_w_cfg[SRC_X_W-1:0]),
        .src_h(core_src_h_cfg[SRC_Y_W-1:0]),
        .prefetch_enable(core_cache_prefetch_en),
        .scan_dir_x(sample_scan_dir_x),
        .scan_dir_y(sample_scan_dir_y),
        .scan_dir_valid(sample_scan_dir_valid),
        .busy(read_busy_core),
        .error(src_cache_error),
        .read_start(cache_read_start),
        .read_addr(cache_read_addr),
        .read_byte_count(cache_read_byte_count),
        .read_busy(cache_read_busy),
        .read_done(cache_read_done),
        .read_error(cache_read_error),
        .in_data(read_out_data),
        .in_valid(read_out_valid),
        .in_ready(read_out_ready),
        .sample_req_valid(sample_req_valid),
        .sample_x0(sample_x0),
        .sample_y0(sample_y0),
        .sample_x1(sample_x1),
        .sample_y1(sample_y1),
        .sample_req_ready(sample_req_ready),
        .sample_p00(cache_sample_p00),
        .sample_p01(cache_sample_p01),
        .sample_p10(cache_sample_p10),
        .sample_p11(cache_sample_p11),
        .sample_rsp_valid(cache_sample_rsp_valid),
        .stat_read_starts(src_cache_stat_read_starts),
        .stat_misses(src_cache_stat_misses),
        .stat_prefetch_starts(src_cache_stat_prefetch_starts),
        .stat_prefetch_hits(src_cache_stat_prefetch_hits)
    );

    assign read_error_core = src_cache_error;
    assign read_done_core  = 1'b0;

    ddr_read_engine #(
        .ADDR_W(AXI_ADDR_W),
        .PIXEL_W(PIXEL_W),
        .AXI_ID_W(AXI_ID_W),
        .BURST_MAX_LEN(16),
        .FIFO_DEPTH_WORDS(64),
        .MAX_OUTSTANDING_BURSTS(4),
        .MAX_OUTSTANDING_BEATS(16)
    ) u_ddr_read_engine (
        .axi_clk(axi_clk),
        .core_clk(core_clk),
        .sys_rst(sys_rst),
        .task_start(cache_read_start),
        .task_addr(cache_read_addr),
        .task_byte_count(cache_read_byte_count),
        .task_busy(cache_read_busy),
        .task_done(cache_read_done),
        .task_error(cache_read_error),
        .out_data(read_out_data),
        .out_valid(read_out_valid),
        .out_ready(read_out_ready),
        .m_axi_rd(m_axi_rd_if)
    );

    rotate_core_bilinear #(
        .PIXEL_W(PIXEL_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .COORD_W(36)
    ) u_rotate_core_bilinear (
        .clk(core_clk),
        .rst(core_sys_rst),
        .start(core_start),
        .src_w(core_src_w_cfg[SRC_X_W-1:0]),
        .src_h(core_src_h_cfg[SRC_Y_W-1:0]),
        .dst_w(core_dst_w_cfg[DST_X_W-1:0]),
        .dst_h(core_dst_h_cfg[DST_Y_W-1:0]),
        .angle_cos_q16(core_rot_cos_q16),
        .angle_sin_q16(core_rot_sin_q16),
        .busy(core_busy),
        .done(core_done),
        .error(core_error),
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
        .scan_dir_x(sample_scan_dir_x),
        .scan_dir_y(sample_scan_dir_y),
        .scan_dir_valid(sample_scan_dir_valid),
        .pix_data(core_pix_data),
        .pix_valid(core_pix_valid),
        .pix_ready(core_pix_ready),
        .row_done(core_row_done)
    );

    row_out_buffer #(
        .PIXEL_W(PIXEL_W),
        .MAX_DST_W(MAX_DST_W)
    ) u_row_out_buffer (
        .clk(core_clk),
        .sys_rst(core_sys_rst),
        .row_start(row_start),
        .row_pixel_count(row_pixel_count),
        .row_busy(row_busy),
        .row_done(row_done_fill),
        .row_error(row_error),
        .in_data(row_in_data),
        .in_valid(row_in_valid),
        .in_ready(row_in_ready),
        .out_start(row_out_start),
        .out_data(row_out_data),
        .out_valid(row_out_valid),
        .out_ready(row_out_ready),
        .out_done(row_out_done)
    );

    assign row_in_data  = core_pix_pipe_data_reg;
    assign row_in_valid = core_pix_pipe_valid_reg;
    assign core_pix_ready = !core_pix_pipe_valid_reg || row_in_ready;

    always_ff @(posedge core_clk) begin
        if (core_sys_rst) begin
            sample_p00 <= '0;
            sample_p01 <= '0;
            sample_p10 <= '0;
            sample_p11 <= '0;
            sample_rsp_valid <= 1'b0;
            core_pix_pipe_valid_reg <= 1'b0;
            core_pix_pipe_data_reg  <= '0;
        end else begin
            sample_rsp_valid <= cache_sample_rsp_valid;
            if (cache_sample_rsp_valid) begin
                sample_p00 <= cache_sample_p00;
                sample_p01 <= cache_sample_p01;
                sample_p10 <= cache_sample_p10;
                sample_p11 <= cache_sample_p11;
            end

            if (!core_pix_pipe_valid_reg || core_pix_ready) begin
                core_pix_pipe_valid_reg <= core_pix_valid;
                if (core_pix_valid) begin
                    core_pix_pipe_data_reg <= core_pix_data;
                end
            end
        end
    end

    ddr_write_engine #(
        .DATA_W(AXI_DATA_W),
        .ADDR_W(AXI_ADDR_W),
        .PIXEL_W(PIXEL_W),
        .AXI_ID_W(AXI_ID_W)
    ) u_ddr_write_engine (
        .axi_clk(axi_clk),
        .core_clk(core_clk),
        .sys_rst(sys_rst),
        .task_start(write_start),
        .task_addr(write_addr),
        .task_byte_count(write_byte_count),
        .task_busy(write_busy),
        .task_done(write_done),
        .task_error(write_error),
        .in_data(row_out_data),
        .in_valid(row_out_valid),
        .in_ready(row_out_ready),
        .m_axi_wr(m_axi_wr_if)
    );

    assign m_axi_rd_arid       = m_axi_rd_if.arid;
    assign m_axi_rd_araddr     = m_axi_rd_if.araddr;
    assign m_axi_rd_arlen      = m_axi_rd_if.arlen;
    assign m_axi_rd_arsize     = m_axi_rd_if.arsize;
    assign m_axi_rd_arburst    = m_axi_rd_if.arburst;
    assign m_axi_rd_arlock     = m_axi_rd_if.arlock;
    assign m_axi_rd_arcache    = m_axi_rd_if.arcache;
    assign m_axi_rd_arprot     = m_axi_rd_if.arprot;
    assign m_axi_rd_arqos      = m_axi_rd_if.arqos;
    assign m_axi_rd_arregion   = m_axi_rd_if.arregion;
    assign m_axi_rd_arvalid    = m_axi_rd_if.arvalid;
    assign m_axi_rd_if.arready = m_axi_rd_arready;
    assign m_axi_rd_if.rid     = m_axi_rd_rid;
    assign m_axi_rd_if.rdata   = m_axi_rd_rdata;
    assign m_axi_rd_if.rresp   = m_axi_rd_rresp;
    assign m_axi_rd_if.rlast   = m_axi_rd_rlast;
    assign m_axi_rd_if.ruser   = '0;
    assign m_axi_rd_if.rvalid  = m_axi_rd_rvalid;
    assign m_axi_rd_rready     = m_axi_rd_if.rready;

    assign m_axi_wr_awid       = m_axi_wr_if.awid;
    assign m_axi_wr_awaddr     = m_axi_wr_if.awaddr;
    assign m_axi_wr_awlen      = m_axi_wr_if.awlen;
    assign m_axi_wr_awsize     = m_axi_wr_if.awsize;
    assign m_axi_wr_awburst    = m_axi_wr_if.awburst;
    assign m_axi_wr_awlock     = m_axi_wr_if.awlock;
    assign m_axi_wr_awcache    = m_axi_wr_if.awcache;
    assign m_axi_wr_awprot     = m_axi_wr_if.awprot;
    assign m_axi_wr_awqos      = m_axi_wr_if.awqos;
    assign m_axi_wr_awregion   = m_axi_wr_if.awregion;
    assign m_axi_wr_awvalid    = m_axi_wr_if.awvalid;
    assign m_axi_wr_wdata      = m_axi_wr_if.wdata;
    assign m_axi_wr_wstrb      = m_axi_wr_if.wstrb;
    assign m_axi_wr_wlast      = m_axi_wr_if.wlast;
    assign m_axi_wr_wvalid     = m_axi_wr_if.wvalid;
    assign m_axi_wr_if.awready = m_axi_wr_awready;
    assign m_axi_wr_if.wready  = m_axi_wr_wready;
    assign m_axi_wr_if.bid     = m_axi_wr_bid;
    assign m_axi_wr_if.bresp   = m_axi_wr_bresp;
    assign m_axi_wr_if.buser   = '0;
    assign m_axi_wr_if.bvalid  = m_axi_wr_bvalid;
    assign m_axi_wr_bready     = m_axi_wr_if.bready;

    assign unused_signals = &{
        1'b0,
        s_axi_ctrl_awprot,
        s_axi_ctrl_arprot,
        read_busy_core,
        read_done_core,
        read_error_core,
        core_rstn
    };

endmodule


