# ddr_axi_pkg 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\axi\ddr_axi_pkg.sv`

## 作用
提供 DDR 读写引擎共用的地址对齐、突发切分和字节数计算函数。

## 关键函数
- `min_u64`：返回较小值
- `align_addr`：按 AXI beat 宽度对齐地址
- `calc_total_words`：计算总共需要多少个 word
- `calc_words_to_4kb`：计算到 4KB 边界前还能放多少个 word
- `calc_burst_words`：综合多种限制得到下一次突发长度
- `calc_burst_bytes`：计算该次突发真正有效的字节数
- `calc_first_word_bytes`：计算首个 word 的有效字节数

## 使用场景
- `axi_burst_reader`
- `ddr_write_engine`

## 注意事项
- 所有辅助函数都基于无符号整型计算，适合地址和字节计数类场景。
