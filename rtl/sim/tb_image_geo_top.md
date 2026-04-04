# tb_image_geo_top

- Version: `v1`
- DUT: `image_geo_top`
- Testbench: `tb_image_geo_top.sv`

当前目标：

- 验证 Stage A 顶层链路能通过 AXI-Lite 配置启动
- 验证最近邻缩放链路可从 DDR 读入并写回 DDR
- 覆盖最小联调路径，不追求完整异常覆盖
