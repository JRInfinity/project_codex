# -----------------------------------------------------------------------------
# image_geo_top dual-clock constraints
#
# This file is written as a pure XDC constraint file. Vivado does not accept Tcl
# control flow such as `if` inside a normal `.xdc`, so keep this file limited to
# direct constraint commands.
#
# Default target:
# - `image_geo_top` instantiated in a wrapper / Block Design
# - instance path matched by `*image_geo_top_0*` (the default name used by the
#   checked-in BD creation script)
#
# Current intended operating point:
# - axi_clk  = 200 MHz
# - core_clk = 100 MHz
#
# If your BD uses a different instance name, update the `*image_geo_top_0*`
# pattern below to match the generated wrapper hierarchy.
# If `image_geo_top` is the synthesis top instead of an instance under a wrapper,
# replace the `get_pins -hier *image_geo_top_0*/...` clock/reset endpoints below
# with `get_ports ...`.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Clocks
# -----------------------------------------------------------------------------
create_clock -name image_geo_axi_clk  -period 5.000  [get_pins -quiet -hier *image_geo_top_0*/axi_clk]
create_clock -name image_geo_core_clk -period 10.000 [get_pins -quiet -hier *image_geo_top_0*/core_clk]

# Top-level alternative when `image_geo_top` is synthesized directly:
# create_clock -name image_geo_axi_clk  -period 5.000  [get_ports axi_clk]
# create_clock -name image_geo_core_clk -period 10.000 [get_ports core_clk]

# -----------------------------------------------------------------------------
# Reset ports/pins
# These resets are synchronous in RTL usage, but they are external control
# signals and should not be used as timing startpoints for regular datapaths.
# -----------------------------------------------------------------------------
set_false_path \
    -from [get_pins -quiet -hier *image_geo_top_0*/axi_rstn] \
    -to   [get_cells -quiet -hier -filter {NAME =~ *image_geo_top_0* && IS_SEQUENTIAL}]

set_false_path \
    -from [get_pins -quiet -hier *image_geo_top_0*/core_rstn] \
    -to   [get_cells -quiet -hier -filter {NAME =~ *image_geo_top_0* && IS_SEQUENTIAL}]

# Top-level alternative when `image_geo_top` is synthesized directly:
# set_false_path -from [get_ports axi_rstn]  -to [get_cells -quiet -hier -filter {NAME =~ *image_geo_top* && IS_SEQUENTIAL}]
# set_false_path -from [get_ports core_rstn] -to [get_cells -quiet -hier -filter {NAME =~ *image_geo_top* && IS_SEQUENTIAL}]

# -----------------------------------------------------------------------------
# Main asynchronous relationship
# All intended axi_clk <-> core_clk crossings are handled by:
# - task_cdc / result_cdc
# - frame_config_cdc / cache_stats_cdc
# - async_word_fifo
# -----------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks image_geo_axi_clk] \
    -group [get_clocks image_geo_core_clk]

# -----------------------------------------------------------------------------
# CDC helper constraints
# The toggle synchronizer flops already use ASYNC_REG in RTL. The commands below
# reinforce that intent in case synthesis hierarchy changes or attributes are
# stripped in downstream flows.
# -----------------------------------------------------------------------------
set_property ASYNC_REG TRUE \
    [get_cells -quiet -hier -regexp {.*(ack_toggle_.*sync[12]_reg|req_toggle_.*sync[12]_reg).*}]

# Keep synchronizer chains from being SRL-extracted.
set_property SHREG_EXTRACT NO \
    [get_cells -quiet -hier -regexp {.*(ack_toggle_.*sync[12]_reg|req_toggle_.*sync[12]_reg).*}]

# -----------------------------------------------------------------------------
# Specific CDC/FIFO path exclusions
# These are technically redundant with set_clock_groups, but they make the CDC
# intent explicit in timing reports and are useful if the global clock-group
# constraint is later narrowed.
# -----------------------------------------------------------------------------
set_false_path -through [get_cells -quiet -hier -filter {
    NAME =~ *u_frame_config_cdc*      ||
    NAME =~ *u_ctrl_result_cdc*       ||
    NAME =~ *u_cache_stats_cdc*       ||
    NAME =~ *u_ddr_read_engine/u_task_cdc*   ||
    NAME =~ *u_ddr_read_engine/u_result_cdc* ||
    NAME =~ *u_ddr_write_engine/u_task_cdc*  ||
    NAME =~ *u_ddr_write_engine/u_result_cdc*
}]

set_false_path -through [get_cells -quiet -hier -filter {
    NAME =~ *u_ddr_read_engine/u_async_word_fifo* ||
    NAME =~ *u_ddr_write_engine/u_async_pixel_fifo*
}]

# -----------------------------------------------------------------------------
# Notes for Block Design integration
# 1. Drive axi_clk from the DDR-side/AXI interconnect clock, typically 200 MHz.
# 2. Drive core_clk from a separate 100 MHz clock source.
# 3. Do not insert automatic clock conversion IP between image_geo_top and its
#    own internal AXI-Lite / AXI clocks unless you intentionally redesign the
#    top-level partition.
# 4. Keep both clocks marked as unrelated in Timing Summary / CDC reports.
# -----------------------------------------------------------------------------
