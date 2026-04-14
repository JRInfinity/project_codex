# PYNQ-Z2 BD Notes

This note matches:

- [create_bd.tcl](/C:/Users/huawei/Desktop/project_codex/bd/scripts/create_bd.tcl)
- [image_geo_top.sv](/C:/Users/huawei/Desktop/project_codex/rtl/top/image_geo_top.sv)

## Recommended PS connections

For PYNQ-Z2 (`xc7z020clg400-1`), use `processing_system7` with:

- `M_AXI_GP0` enabled
- `S_AXI_HP0` enabled
- `IRQ_F2P` enabled
- `FCLK_CLK0 = 100 MHz`

The BD script assumes:

- `M_AXI_GP0` drives the AXI-Lite control path
- `S_AXI_HP0` is the DDR-facing slave used by the read/write data masters

## Clock plan

- `ps_0/FCLK_CLK0` -> `clk_wiz_0/clk_in1`
- `clk_wiz_0/clk_out1 = 200 MHz` -> `image_geo_top/axi_clk`
- `clk_wiz_0/clk_out2 = 100 MHz` -> `image_geo_top/core_clk`

## Reset plan

Use two `proc_sys_reset` blocks:

- `rst_axi_0` driven by `clk_out1`
- `rst_core_0` driven by `clk_out2`

Connect:

- `rst_axi_0/peripheral_aresetn` -> `image_geo_top/axi_rstn`
- `rst_core_0/peripheral_aresetn` -> `image_geo_top/core_rstn`

## AXI connections

Control path:

- `ps_0/M_AXI_GP0` -> `smartconnect_ctrl_0/S00_AXI`
- `smartconnect_ctrl_0/M00_AXI` -> `image_geo_top/s_axi_ctrl`

DDR path:

- `image_geo_top/m_axi_rd` -> `smartconnect_mem_0/S00_AXI`
- `image_geo_top/m_axi_wr` -> `smartconnect_mem_0/S01_AXI`
- `smartconnect_mem_0/M00_AXI` -> `ps_0/S_AXI_HP0`

## Interrupt

- `image_geo_top/irq` -> `xlconcat_0/In0`
- `xlconcat_0/dout` -> `ps_0/IRQ_F2P`

## Constraints

Add:

- [cdc_image_geo_top.xdc](/C:/Users/huawei/Desktop/project_codex/constraints/cdc_image_geo_top.xdc)

Then verify after synthesis:

- `image_geo_axi_clk` exists at 200 MHz
- `image_geo_core_clk` exists at 100 MHz
- the two clocks are reported as asynchronous groups
- no unexpected unconstrained CDC paths appear around `image_geo_top`

The checked-in constraint file assumes the default BD instance name
`*image_geo_top_0*`. If your instance name differs,
update the `get_pins -hier` patterns in that XDC before implementation.
