# -----------------------------------------------------------------------------
# create_bd.tcl
#
# Skeleton Block Design script for integrating the packaged `image_geo_top`
# IP on PYNQ-Z2. This script targets the common pattern:
#
# - Zynq-7000 Processing System (`processing_system7`)
# - Clocking Wizard generating 200 MHz axi_clk and 100 MHz core_clk
# - SmartConnect for AXI-Lite control and DDR data access
# - packaged image_geo_top IP
#
# This is a starting point, not a one-click final BD. Board-specific DDR and PS
# settings still need to be completed in the target Vivado project.
# -----------------------------------------------------------------------------

set design_name design_image_geo
set part_name xc7z020clg400-1
set image_geo_ip_vlnv xilinx.com:user:image_geo_top:1.0

proc safe_delete_bd {name} {
    if {[llength [get_bd_designs -quiet $name]] != 0} {
        close_bd_design [get_bd_designs $name]
        remove_bd_design [get_bd_designs $name]
    }
}

if {[string equal [current_project -quiet] ""]} {
    create_project image_geo_bd_tmp . -part $part_name
}

safe_delete_bd $design_name
create_bd_design $design_name
current_bd_design $design_name

# -----------------------------------------------------------------------------
# Core IP blocks
# -----------------------------------------------------------------------------
set ps_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:* ps_0]
set clk_wiz_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:* clk_wiz_0]
set rst_axi_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_axi_0]
set rst_core_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_core_0]
set reset_inv_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:* reset_inv_0]
set smartconnect_ctrl_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* smartconnect_ctrl_0]
set smartconnect_mem_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* smartconnect_mem_0]
set xlconcat_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:* xlconcat_0]

# Packaged image_geo_top IP
# Update image_geo_ip_vlnv if the packaged VLNV changes in your Vivado project.
set image_geo_top_0 [create_bd_cell -type ip -vlnv $image_geo_ip_vlnv image_geo_top_0]

# -----------------------------------------------------------------------------
# Suggested IP configuration for PYNQ-Z2 / Zynq-7000
# -----------------------------------------------------------------------------
set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
] $smartconnect_ctrl_0

set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {2} \
] $smartconnect_mem_0

set_property -dict [list \
    CONFIG.NUM_PORTS {1} \
] $xlconcat_0

set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
] $reset_inv_0

# Clock Wizard:
# - input clock assumed to be 100 MHz from PS FCLK_CLK0
# - output 1 = 200 MHz for axi_clk
# - output 2 = 100 MHz for core_clk
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {100.000} \
] $clk_wiz_0

# PYNQ-Z2 uses Zynq-7000 PS. Prefer the board preset when board files are
# installed; otherwise configure the needed interfaces manually.
catch {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} $ps_0
}

# Ensure the interfaces needed by image_geo_top are enabled.
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_FCLK0_PERIPHERAL_FREQMHZ {100.0} \
] $ps_0

# -----------------------------------------------------------------------------
# Clock connections
# -----------------------------------------------------------------------------
connect_bd_net [get_bd_pins $ps_0/FCLK_CLK0] [get_bd_pins $clk_wiz_0/clk_in1]

connect_bd_net [get_bd_pins $clk_wiz_0/clk_out1] [get_bd_pins $image_geo_top_0/axi_clk]
connect_bd_net [get_bd_pins $clk_wiz_0/clk_out2] [get_bd_pins $image_geo_top_0/core_clk]

connect_bd_net [get_bd_pins $clk_wiz_0/clk_out1] [get_bd_pins $smartconnect_ctrl_0/aclk]
connect_bd_net [get_bd_pins $clk_wiz_0/clk_out1] [get_bd_pins $smartconnect_mem_0/aclk]

# PS AXI interface clocks
foreach pin [list M_AXI_GP0_ACLK S_AXI_HP0_ACLK] {
    if {[llength [get_bd_pins -quiet $ps_0/$pin]] != 0} {
        connect_bd_net [get_bd_pins $clk_wiz_0/clk_out1] [get_bd_pins $ps_0/$pin]
    }
}

# SmartConnect slave/master clock pins
foreach pin [list \
    S00_ACLK M00_ACLK \
] {
    if {[llength [get_bd_pins -quiet $smartconnect_ctrl_0/$pin]] != 0} {
        connect_bd_net [get_bd_pins $clk_wiz_0/clk_out1] [get_bd_pins $smartconnect_ctrl_0/$pin]
    }
}

foreach pin [list \
    S00_ACLK S01_ACLK M00_ACLK \
] {
    if {[llength [get_bd_pins -quiet $smartconnect_mem_0/$pin]] != 0} {
        connect_bd_net [get_bd_pins $clk_wiz_0/clk_out1] [get_bd_pins $smartconnect_mem_0/$pin]
    }
}

# -----------------------------------------------------------------------------
# Reset connections
# -----------------------------------------------------------------------------
connect_bd_net [get_bd_pins $clk_wiz_0/locked] [get_bd_pins $rst_axi_0/dcm_locked]
connect_bd_net [get_bd_pins $clk_wiz_0/locked] [get_bd_pins $rst_core_0/dcm_locked]

connect_bd_net [get_bd_pins $clk_wiz_0/clk_out1] [get_bd_pins $rst_axi_0/slowest_sync_clk]
connect_bd_net [get_bd_pins $clk_wiz_0/clk_out2] [get_bd_pins $rst_core_0/slowest_sync_clk]

# Match the hand-fixed BD:
# - use PS FCLK_RESET0_N as the reset source
# - invert it with util_vector_logic
# - drive clk_wiz reset directly from the inverted reset
# - keep proc_sys_reset ext_reset_in sourced from the same inverted reset
connect_bd_net [get_bd_pins $ps_0/FCLK_RESET0_N] [get_bd_pins $reset_inv_0/Op1]
connect_bd_net [get_bd_pins $reset_inv_0/Res] [get_bd_pins $clk_wiz_0/reset]
connect_bd_net [get_bd_pins $reset_inv_0/Res] [get_bd_pins $rst_axi_0/ext_reset_in]
connect_bd_net [get_bd_pins $reset_inv_0/Res] [get_bd_pins $rst_core_0/ext_reset_in]

connect_bd_net [get_bd_pins $rst_axi_0/peripheral_aresetn] [get_bd_pins $image_geo_top_0/axi_rstn]
connect_bd_net [get_bd_pins $rst_core_0/peripheral_aresetn] [get_bd_pins $image_geo_top_0/core_rstn]

# -----------------------------------------------------------------------------
# AXI-Lite control path
# -----------------------------------------------------------------------------
# PYNQ-Z2 control path:
# PS M_AXI_GP0 -> SmartConnect control -> image_geo_top AXI-Lite slave
connect_bd_intf_net [get_bd_intf_pins $ps_0/M_AXI_GP0] \
                    [get_bd_intf_pins $smartconnect_ctrl_0/S00_AXI]

connect_bd_intf_net [get_bd_intf_pins $smartconnect_ctrl_0/M00_AXI] \
                    [get_bd_intf_pins $image_geo_top_0/s_axi_ctrl]

# -----------------------------------------------------------------------------
# DDR AXI data path
# -----------------------------------------------------------------------------
# image_geo_top has two AXI masters:
# - m_axi_rd
# - m_axi_wr
#
# Connect both into the memory SmartConnect, then connect the SmartConnect
# master to Zynq PS S_AXI_HP0.
connect_bd_intf_net [get_bd_intf_pins $image_geo_top_0/m_axi_rd] \
                    [get_bd_intf_pins $smartconnect_mem_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $image_geo_top_0/m_axi_wr] \
                    [get_bd_intf_pins $smartconnect_mem_0/S01_AXI]

connect_bd_intf_net [get_bd_intf_pins $smartconnect_mem_0/M00_AXI] \
                    [get_bd_intf_pins $ps_0/S_AXI_HP0]

# -----------------------------------------------------------------------------
# Interrupt
# -----------------------------------------------------------------------------
connect_bd_net [get_bd_pins $image_geo_top_0/irq] [get_bd_pins $xlconcat_0/In0]
if {[llength [get_bd_pins -quiet $ps_0/IRQ_F2P]] != 0} {
    connect_bd_net [get_bd_pins $xlconcat_0/dout] [get_bd_pins $ps_0/IRQ_F2P]
} else {
    puts "WARNING: ps_0/IRQ_F2P not present. Check PS interrupt configuration in BD."
}

# -----------------------------------------------------------------------------
# Address assignment
# -----------------------------------------------------------------------------
# image_geo_top AXI-Lite register bank size is small; 64 KB is usually more than
# enough for clean addressing in BD.
#
assign_bd_address
catch {
    set_property range 64K [get_bd_addr_segs {ps_0/Data/SEG_image_geo_top_0_reg0}]
}

# -----------------------------------------------------------------------------
# Finalization
# -----------------------------------------------------------------------------
regenerate_bd_layout
validate_bd_design
save_bd_design

puts "Created BD skeleton: $design_name"
puts "Next steps:"
puts "1. Configure PS DDR/IRQ/master/slave interfaces."
puts "2. Verify the Processing System board preset and DDR settings."
puts "3. Verify AXI address assignments in Address Editor."
puts "4. Generate the HDL wrapper and add constraints/cdc_image_geo_top.xdc."
