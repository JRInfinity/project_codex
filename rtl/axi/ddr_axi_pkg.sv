// 包职责：
// 1. 提供 DDR AXI 读写链路公用的地址、突发和计数辅助函数
// 2. 统一处理地址对齐、4KB 边界约束和总数据字数量计算
`timescale 1ns/1ps

package ddr_axi_pkg;

    // 返回两个无符号 64 位数中的较小值。
    function automatic longint unsigned min_u64(
        input longint unsigned lhs,
        input longint unsigned rhs
    );
        if (lhs < rhs) begin
            min_u64 = lhs;
        end else begin
            min_u64 = rhs;
        end
    endfunction

    // 按 AXI beat 宽度对地址向下对齐。
    function automatic longint unsigned align_addr(
        input longint unsigned addr,
        input int unsigned      axi_size_w
    );
        if (axi_size_w == 0) begin
            align_addr = addr;
        end else begin
            align_addr = (addr >> axi_size_w) << axi_size_w;
        end
    endfunction

    // 计算给定起始偏移和总字节数后，一共需要搬运多少个完整 word。
    function automatic longint unsigned calc_total_words(
        input longint unsigned byte_count,
        input longint unsigned addr_offset,
        input int unsigned      byte_w
    );
        calc_total_words = (byte_count + addr_offset + byte_w - 1) / byte_w;
    endfunction

    // 计算当前对齐地址到下一个 4KB 边界前还能放下多少个 word。
    // AXI INCR 突发不能跨 4KB 边界，因此这个值是突发切分的关键约束。
    function automatic longint unsigned calc_words_to_4kb(
        input longint unsigned aligned_addr,
        input int unsigned      byte_w
    );
        longint unsigned bytes_to_4kb;
        bytes_to_4kb = 64'd4096 - (aligned_addr & 64'hFFF);
        calc_words_to_4kb = bytes_to_4kb / byte_w;
        if (calc_words_to_4kb == 0) begin
            calc_words_to_4kb = 1;
        end
    endfunction

    // 综合考虑剩余数据量、4KB 边界、最大突发长度和 FIFO 空间后，
    // 计算下一拍最合适的突发 word 数。
    function automatic longint unsigned calc_burst_words(
        input longint unsigned words_remaining,
        input longint unsigned words_to_4kb,
        input int unsigned      burst_max_len,
        input longint unsigned fifo_space_words
    );
        calc_burst_words = min_u64(words_remaining, burst_max_len);
        calc_burst_words = min_u64(calc_burst_words, words_to_4kb);
        calc_burst_words = min_u64(calc_burst_words, fifo_space_words);
    endfunction

    // 已知本次突发 word 数后，反推出真正有效的字节数。
    // 第一拍可能带起始偏移，因此有效字节数未必等于 burst_words * byte_w。
    function automatic longint unsigned calc_burst_bytes(
        input longint unsigned burst_words,
        input longint unsigned addr_offset,
        input longint unsigned bytes_left,
        input int unsigned      byte_w
    );
        if (burst_words == 0) begin
            calc_burst_bytes = 0;
        end else begin
            calc_burst_bytes = (burst_words * byte_w) - addr_offset;
            calc_burst_bytes = min_u64(calc_burst_bytes, bytes_left);
        end
    endfunction

    // 计算当前首个对齐 word 中真正有效的字节数。
    function automatic longint unsigned calc_first_word_bytes(
        input longint unsigned addr_offset,
        input longint unsigned bytes_left,
        input int unsigned      byte_w
    );
        calc_first_word_bytes = byte_w - addr_offset;
        calc_first_word_bytes = min_u64(calc_first_word_bytes, bytes_left);
    endfunction

endpackage
