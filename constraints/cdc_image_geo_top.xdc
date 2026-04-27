# -----------------------------------------------------------------------------
# image_geo_top dual-clock constraints
#
# This file is written as a pure XDC constraint file. Vivado does not accept Tcl
# control flow such as `if` inside a normal `.xdc`, so keep this file limited to
# direct constraint commands.
#
# Default target:
# - wrapper / Block Design top ports named `axi_clk` and `core_clk`, or
#   `image_geo_top` synthesized directly as the top module by report scripts.
#
# Current intended operating point:
# - axi_clk  = 200 MHz
# - core_clk = 100 MHz
#
# If your BD hides these clocks inside instance pins instead of wrapper ports,
# add a wrapper-specific XDC rather than using unsupported Tcl control flow here.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Clocks
# -----------------------------------------------------------------------------
create_clock -name image_geo_axi_clk  -period 5.000  [get_ports -quiet axi_clk]
create_clock -name image_geo_core_clk -period 10.000 [get_ports -quiet core_clk]

# -----------------------------------------------------------------------------
# Reset ports/pins
# These resets are synchronous in RTL usage, but they are external control
# signals and should not be used as timing startpoints for regular datapaths.
# -----------------------------------------------------------------------------
set_false_path \
    -from [get_ports -quiet axi_rstn] \
    -to   [get_cells -quiet -hier -filter {IS_SEQUENTIAL && (NAME =~ *image_geo_top_0* || NAME =~ *u_* || NAME =~ *reg*)}]

set_false_path \
    -from [get_ports -quiet core_rstn] \
    -to   [get_cells -quiet -hier -filter {IS_SEQUENTIAL && (NAME =~ *image_geo_top_0* || NAME =~ *u_* || NAME =~ *reg*)}]

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

# Reset synchronizers added in the RTL use async assertion and synchronous
# release in each clock domain.
set_property ASYNC_REG TRUE \
    [get_cells -quiet -hier -regexp {.*u_.*reset_sync.*rst_pipe_reg.*}]

set_property SHREG_EXTRACT NO \
    [get_cells -quiet -hier -regexp {.*u_.*reset_sync.*rst_pipe_reg.*}]

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

# Config, task, result and cache-stat payloads now cross domains through
# async FIFO based CDC blocks, so there is no remaining wide bundled-data
# payload path that needs a max-delay sideband constraint here. If a future
# req/ack bundled-data CDC is added, constrain that specific payload path in
# the owning wrapper instead of reintroducing a broad hierarchical regexp.

# -----------------------------------------------------------------------------
# Notes for Block Design integration
# 1. Drive axi_clk from the DDR-side/AXI interconnect clock, typically 200 MHz.
# 2. Drive core_clk from a separate 100 MHz clock source.
# 3. Do not insert automatic clock conversion IP between image_geo_top and its
#    own internal AXI-Lite / AXI clocks unless you intentionally redesign the
#    top-level partition.
# 4. Keep both clocks marked as unrelated in Timing Summary / CDC reports.
# -----------------------------------------------------------------------------
