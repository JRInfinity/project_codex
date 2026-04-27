# -----------------------------------------------------------------------------
# Optional OOC AXI input timing template for image_geo_top
#
# Use this only when synthesizing image_geo_top directly as an out-of-context
# top and you want report_cdc/report_timing to classify AXI input ports with an
# explicit external timing model. The checked-in SmallConfig report flow does
# not source this file automatically.
#
# Integration wrappers / block designs should replace these conservative values
# with board/interconnect-specific input/output delay constraints.
# -----------------------------------------------------------------------------

# Example only: AXI read/write response/data channels are driven by logic in the
# axi_clk domain outside image_geo_top.
set_input_delay -clock [get_clocks image_geo_axi_clk] -max 2.000 [get_ports -quiet {m_axi_rd_rvalid m_axi_rd_rlast m_axi_rd_rdata[*] m_axi_rd_rresp[*] m_axi_wr_awready m_axi_wr_wready m_axi_wr_bvalid m_axi_wr_bresp[*] s_axi_ctrl_awvalid s_axi_ctrl_awaddr[*] s_axi_ctrl_wvalid s_axi_ctrl_wdata[*] s_axi_ctrl_wstrb[*] s_axi_ctrl_bready s_axi_ctrl_arvalid s_axi_ctrl_araddr[*] s_axi_ctrl_rready}]
set_input_delay -clock [get_clocks image_geo_axi_clk] -min 0.000 [get_ports -quiet {m_axi_rd_rvalid m_axi_rd_rlast m_axi_rd_rdata[*] m_axi_rd_rresp[*] m_axi_wr_awready m_axi_wr_wready m_axi_wr_bvalid m_axi_wr_bresp[*] s_axi_ctrl_awvalid s_axi_ctrl_awaddr[*] s_axi_ctrl_wvalid s_axi_ctrl_wdata[*] s_axi_ctrl_wstrb[*] s_axi_ctrl_bready s_axi_ctrl_arvalid s_axi_ctrl_araddr[*] s_axi_ctrl_rready}]

