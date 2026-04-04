# 递归记录全部波形对象，便于统一查看 testbench 和 DUT 的关键信号。
log_wave -recursive /*

if {[info exists ::env(XSIM_VCD_FILE)] && $::env(XSIM_VCD_FILE) ne ""} {
    # 当外部要求导出 VCD 时，同时把全部对象记录进去。
    open_vcd $::env(XSIM_VCD_FILE)
    log_vcd [get_objects -r /*]
}

run all

if {[info exists ::env(XSIM_VCD_FILE)] && $::env(XSIM_VCD_FILE) ne ""} {
    # run all 结束后显式关闭 VCD 文件，确保内容完整落盘。
    close_vcd
}

quit
