function result = image_geo_cache_ref(src_w, src_h, dst_w, dst_h, angle_deg, varargin)
%IMAGE_GEO_CACHE_REF RTL-style geometry and tile-cache reference model.
%   Results are written under one case directory:
%     input.png/input.bin/input_meta.txt/case.txt
%     input.txt, which is a row-major hex text dump matching input.bin
%     output_ref.png/output_ref.bin/output_ref.txt
%     coeffs.txt/tile_summary.txt/tile_summary.csv/prefetch_plan.csv/tile_heatmap.png
%
%   The geometry uses the same Q16 inverse mapping as the RTL. Source
%   coordinates outside the source frame generate output pixel 0 and do not
%   create tile/cache traffic.

    validateattributes(src_w, {'numeric'}, {'scalar', 'integer', 'positive'});
    validateattributes(src_h, {'numeric'}, {'scalar', 'integer', 'positive'});
    validateattributes(dst_w, {'numeric'}, {'scalar', 'integer', 'positive'});
    validateattributes(dst_h, {'numeric'}, {'scalar', 'integer', 'positive'});
    validateattributes(angle_deg, {'numeric'}, {'scalar', 'real'});

    parser = inputParser;
    parser.FunctionName = 'image_geo_cache_ref';
    addParameter(parser, 'Pattern', 'diagonal_ramp');
    addParameter(parser, 'ResultRoot', fullfile('out', 'cache_ref_runs'));
    addParameter(parser, 'CaseName', '');
    addParameter(parser, 'OutPrefix', '');
    addParameter(parser, 'TileConfigs', default_tile_configs());
    addParameter(parser, 'DdrLatencyCycles', 80);
    addParameter(parser, 'DdrBytesPerCycle', 4);
    addParameter(parser, 'DdrOutstanding', 1);
    addParameter(parser, 'PixelCycles', 1);
    addParameter(parser, 'WriteTimeline', false);
    addParameter(parser, 'WritePreview', false);
    addParameter(parser, 'WriteCoe', false);
    addParameter(parser, 'WritePixelTxt', true);
    addParameter(parser, 'Seed', 1);
    parse(parser, varargin{:});
    opts = parser.Results;

    opts.Pattern = char(opts.Pattern);
    opts.ResultRoot = char(opts.ResultRoot);
    opts.CaseName = char(opts.CaseName);
    opts.OutPrefix = char(opts.OutPrefix);
    opts.TileConfigs = double(opts.TileConfigs);
    validate_tile_configs(opts.TileConfigs);
    validateattributes(opts.DdrLatencyCycles, {'numeric'}, {'scalar', 'nonnegative', 'finite'});
    validateattributes(opts.DdrBytesPerCycle, {'numeric'}, {'scalar', 'positive', 'finite'});
    validateattributes(opts.DdrOutstanding, {'numeric'}, {'scalar', 'integer', 'positive'});
    validateattributes(opts.PixelCycles, {'numeric'}, {'scalar', 'positive', 'finite'});

    if isempty(opts.CaseName)
        opts.CaseName = default_case_name(src_w, src_h, dst_w, dst_h, angle_deg);
    end
    if isempty(opts.OutPrefix)
        case_dir = fullfile(opts.ResultRoot, opts.CaseName);
    else
        case_dir = opts.OutPrefix;
    end
    if ~exist(case_dir, 'dir')
        mkdir(case_dir);
    end

    paths = build_paths(case_dir, opts.WriteTimeline);
    [case_cfg, src_img, src_meta] = export_image_geo_case( ...
        src_w, src_h, opts.Pattern, paths.input_prefix, dst_w, dst_h, angle_deg, ...
        'WritePreview', opts.WritePreview, ...
        'WriteCoe', opts.WriteCoe, ...
        'WritePixelTxt', opts.WritePixelTxt, ...
        'Seed', opts.Seed, ...
        'CasePath', paths.case_txt, ...
        'OutputBinName', 'output_ref.bin');

    geom = compute_rtl_geometry(src_w, src_h, dst_w, dst_h, angle_deg);
    [trace, output_img] = build_sample_trace(src_img, geom);
    imwrite(output_img, paths.output_png);
    write_raw_bin_local(output_img, paths.output_bin);
    if opts.WritePixelTxt
        write_pixel_txt_local(output_img, paths.output_txt);
    end

    analysis = cell(size(opts.TileConfigs, 1), 1);
    for cfg_idx = 1:size(opts.TileConfigs, 1)
        cfg = struct();
        cfg.tile_w = opts.TileConfigs(cfg_idx, 1);
        cfg.tile_h = opts.TileConfigs(cfg_idx, 2);
        cfg.tile_num = opts.TileConfigs(cfg_idx, 3);
        analysis{cfg_idx} = analyze_tile_config(trace, geom, cfg, opts);
    end
    [best_idx, best_score] = choose_best_config(analysis);

    write_coeffs_txt(paths.coeffs_txt, geom, opts, case_cfg, trace);
    if opts.WriteTimeline
        write_timeline_csv(paths.timeline_csv, trace, analysis{1}.cfg);
    end
    write_prefetch_plan_csv(paths.prefetch_csv, analysis{best_idx});
    write_summary_csv(paths.summary_csv, analysis);
    write_summary_txt(paths.summary_txt, geom, opts, analysis, paths, best_idx, best_score);
    write_heatmap_png(paths.heatmap_png, analysis{best_idx}.heat_counts);

    result = struct();
    result.case_dir = case_dir;
    result.case_cfg = case_cfg;
    result.src_meta = src_meta;
    result.geom = geom;
    result.trace = trace;
    result.output_img = output_img;
    result.analysis = analysis;
    result.best_idx = best_idx;
    result.best_score = best_score;
    result.paths = paths;

    fprintf('image_geo_cache_ref complete: %s\n', case_dir);
    fprintf('  output:  %s\n', paths.output_png);
    fprintf('  summary: %s\n', paths.summary_txt);
end

function cfgs = default_tile_configs()
    cfgs = [
        16 16 8
        32 16 8
        32 16 12
        32 16 16
        32 32 8
        32 32 12
        64 16 8
        64 32 8
    ];
end

function paths = build_paths(case_dir, write_timeline)
    paths = struct();
    paths.case_dir = case_dir;
    paths.input_prefix = fullfile(case_dir, 'input');
    paths.input_png = fullfile(case_dir, 'input.png');
    paths.input_bin = fullfile(case_dir, 'input.bin');
    paths.input_txt = fullfile(case_dir, 'input.txt');
    paths.input_meta = fullfile(case_dir, 'input_meta.txt');
    paths.case_txt = fullfile(case_dir, 'case.txt');
    paths.output_png = fullfile(case_dir, 'output_ref.png');
    paths.output_bin = fullfile(case_dir, 'output_ref.bin');
    paths.output_txt = fullfile(case_dir, 'output_ref.txt');
    paths.coeffs_txt = fullfile(case_dir, 'coeffs.txt');
    paths.summary_txt = fullfile(case_dir, 'tile_summary.txt');
    paths.summary_csv = fullfile(case_dir, 'tile_summary.csv');
    paths.prefetch_csv = fullfile(case_dir, 'prefetch_plan.csv');
    paths.heatmap_png = fullfile(case_dir, 'tile_heatmap.png');
    if write_timeline
        paths.timeline_csv = fullfile(case_dir, 'tile_timeline.csv');
    else
        paths.timeline_csv = '';
    end
end

function name = default_case_name(src_w, src_h, dst_w, dst_h, angle_deg)
    angle_txt = sprintf('%.3f', angle_deg);
    angle_txt = strrep(angle_txt, '-', 'm');
    angle_txt = strrep(angle_txt, '.', 'p');
    name = sprintf('src%dx%d_dst%dx%d_rot%s', src_w, src_h, dst_w, dst_h, angle_txt);
end

function validate_tile_configs(tile_configs)
    validateattributes(tile_configs, {'numeric'}, {'2d', 'ncols', 3, 'positive', 'integer'});
end

function geom = compute_rtl_geometry(src_w, src_h, dst_w, dst_h, angle_deg)
    frac_w = 16;
    q_scale = int64(2^frac_w);

    rot_sin_q16 = int64(round(sind(angle_deg) * double(q_scale)));
    rot_cos_q16 = int64(round(cosd(angle_deg) * double(q_scale)));
    scale_x_q16 = int64(floor(double(src_w) * double(q_scale) / double(dst_w)));
    scale_y_q16 = int64(floor(double(src_h) * double(q_scale) / double(dst_h)));

    src_cx_q16 = int64(src_w - 1) * int64(2^(frac_w - 1));
    src_cy_q16 = int64(src_h - 1) * int64(2^(frac_w - 1));
    dst_cx_q16 = int64(dst_w - 1) * int64(2^(frac_w - 1));
    dst_cy_q16 = int64(dst_h - 1) * int64(2^(frac_w - 1));

    step_x_x_q16 = q_mul_shift(rot_cos_q16, scale_x_q16, frac_w);
    step_y_x_q16 = -q_mul_shift(rot_sin_q16, scale_x_q16, frac_w);
    step_x_y_q16 = q_mul_shift(rot_sin_q16, scale_y_q16, frac_w);
    step_y_y_q16 = q_mul_shift(rot_cos_q16, scale_y_q16, frac_w);

    row0_x_q16 = src_cx_q16 ...
        - q_mul_shift(dst_cx_q16, step_x_x_q16, frac_w) ...
        - q_mul_shift(dst_cy_q16, step_x_y_q16, frac_w);
    row0_y_q16 = src_cy_q16 ...
        - q_mul_shift(dst_cx_q16, step_y_x_q16, frac_w) ...
        - q_mul_shift(dst_cy_q16, step_y_y_q16, frac_w);

    geom = struct();
    geom.src_w = src_w;
    geom.src_h = src_h;
    geom.dst_w = dst_w;
    geom.dst_h = dst_h;
    geom.angle_deg = angle_deg;
    geom.frac_w = frac_w;
    geom.q_scale = q_scale;
    geom.rot_sin_q16 = rot_sin_q16;
    geom.rot_cos_q16 = rot_cos_q16;
    geom.scale_x_q16 = scale_x_q16;
    geom.scale_y_q16 = scale_y_q16;
    geom.src_cx_q16 = src_cx_q16;
    geom.src_cy_q16 = src_cy_q16;
    geom.dst_cx_q16 = dst_cx_q16;
    geom.dst_cy_q16 = dst_cy_q16;
    geom.step_x_x_q16 = step_x_x_q16;
    geom.step_y_x_q16 = step_y_x_q16;
    geom.step_x_y_q16 = step_x_y_q16;
    geom.step_y_y_q16 = step_y_y_q16;
    geom.row0_x_q16 = row0_x_q16;
    geom.row0_y_q16 = row0_y_q16;
    geom.max_x_q16 = int64(src_w - 1) * q_scale;
    geom.max_y_q16 = int64(src_h - 1) * q_scale;
    geom.scan_dir_x = sign_int(step_x_x_q16);
    geom.scan_dir_y = sign_int(step_y_x_q16);
    geom.corners = compute_corners(geom);
end

function corners = compute_corners(geom)
    pts = [0 0; geom.dst_w - 1 0; 0 geom.dst_h - 1; geom.dst_w - 1 geom.dst_h - 1];
    corners = zeros(size(pts, 1), 6);
    for k = 1:size(pts, 1)
        x = int64(pts(k, 1));
        y = int64(pts(k, 2));
        sx_q16 = geom.row0_x_q16 + x * geom.step_x_x_q16 + y * geom.step_x_y_q16;
        sy_q16 = geom.row0_y_q16 + x * geom.step_y_x_q16 + y * geom.step_y_y_q16;
        corners(k, :) = [pts(k, 1), pts(k, 2), double(sx_q16), double(sy_q16), ...
                         q_to_double(sx_q16, geom.frac_w), q_to_double(sy_q16, geom.frac_w)];
    end
end

function y = q_mul_shift(a, b, frac_w)
    y = int64(floor(double(a) * double(b) / double(2^frac_w)));
end

function s = sign_int(x)
    if x > 0
        s = 1;
    elseif x < 0
        s = -1;
    else
        s = 0;
    end
end

function [trace, output_img] = build_sample_trace(src_img, geom)
    n = geom.dst_w * geom.dst_h;
    output_img = uint8(zeros(geom.dst_h, geom.dst_w));

    trace = struct();
    trace.pixel_idx = zeros(n, 1, 'uint32');
    trace.dst_x = zeros(n, 1, 'uint32');
    trace.dst_y = zeros(n, 1, 'uint32');
    trace.src_x_q16 = zeros(n, 1, 'int64');
    trace.src_y_q16 = zeros(n, 1, 'int64');
    trace.valid = false(n, 1);
    trace.sample_x0 = zeros(n, 1, 'uint32');
    trace.sample_y0 = zeros(n, 1, 'uint32');
    trace.sample_x1 = zeros(n, 1, 'uint32');
    trace.sample_y1 = zeros(n, 1, 'uint32');
    trace.frac_x_q16 = zeros(n, 1, 'uint32');
    trace.frac_y_q16 = zeros(n, 1, 'uint32');
    trace.p00 = zeros(n, 1, 'uint8');
    trace.p01 = zeros(n, 1, 'uint8');
    trace.p10 = zeros(n, 1, 'uint8');
    trace.p11 = zeros(n, 1, 'uint8');
    trace.output_pixel = zeros(n, 1, 'uint8');

    idx = 1;
    row_x_q16 = geom.row0_x_q16;
    row_y_q16 = geom.row0_y_q16;
    q_scale = geom.q_scale;

    for dst_y = 0:(geom.dst_h - 1)
        cur_x_q16 = row_x_q16;
        cur_y_q16 = row_y_q16;
        for dst_x = 0:(geom.dst_w - 1)
            valid = (cur_x_q16 >= 0) && (cur_x_q16 <= geom.max_x_q16) && ...
                    (cur_y_q16 >= 0) && (cur_y_q16 <= geom.max_y_q16);

            trace.pixel_idx(idx) = uint32(idx - 1);
            trace.dst_x(idx) = uint32(dst_x);
            trace.dst_y(idx) = uint32(dst_y);
            trace.src_x_q16(idx) = cur_x_q16;
            trace.src_y_q16(idx) = cur_y_q16;
            trace.valid(idx) = valid;

            if valid
                sx0 = floor(double(cur_x_q16) / double(q_scale));
                sy0 = floor(double(cur_y_q16) / double(q_scale));
                sx1 = min(sx0 + 1, geom.src_w - 1);
                sy1 = min(sy0 + 1, geom.src_h - 1);
                frac_x = cur_x_q16 - int64(sx0) * q_scale;
                frac_y = cur_y_q16 - int64(sy0) * q_scale;

                p00 = src_img(sy0 + 1, sx0 + 1);
                p01 = src_img(sy0 + 1, sx1 + 1);
                p10 = src_img(sy1 + 1, sx0 + 1);
                p11 = src_img(sy1 + 1, sx1 + 1);
                out_pix = bilinear_q16(p00, p01, p10, p11, frac_x, frac_y);

                trace.sample_x0(idx) = uint32(sx0);
                trace.sample_y0(idx) = uint32(sy0);
                trace.sample_x1(idx) = uint32(sx1);
                trace.sample_y1(idx) = uint32(sy1);
                trace.frac_x_q16(idx) = uint32(frac_x);
                trace.frac_y_q16(idx) = uint32(frac_y);
                trace.p00(idx) = p00;
                trace.p01(idx) = p01;
                trace.p10(idx) = p10;
                trace.p11(idx) = p11;
                trace.output_pixel(idx) = out_pix;
                output_img(dst_y + 1, dst_x + 1) = out_pix;
            end

            idx = idx + 1;
            cur_x_q16 = cur_x_q16 + geom.step_x_x_q16;
            cur_y_q16 = cur_y_q16 + geom.step_y_x_q16;
        end
        row_x_q16 = row_x_q16 + geom.step_x_y_q16;
        row_y_q16 = row_y_q16 + geom.step_y_y_q16;
    end
end

function pix = bilinear_q16(p00, p01, p10, p11, frac_x, frac_y)
    q = 65536;
    half = 32768;
    fx = double(frac_x);
    fy = double(frac_y);
    top = floor((double(p00) * (q - fx) + double(p01) * fx + half) / q);
    bot = floor((double(p10) * (q - fx) + double(p11) * fx + half) / q);
    out = floor((top * (q - fy) + bot * fy + half) / q);
    pix = uint8(min(max(out, 0), 255));
end

function analysis = analyze_tile_config(trace, geom, cfg, opts)
    cfg.tile_count_x = ceil(geom.src_w / cfg.tile_w);
    cfg.tile_count_y = ceil(geom.src_h / cfg.tile_h);
    cfg.total_tiles = cfg.tile_count_x * cfg.tile_count_y;
    cfg.bram_bits = cfg.tile_w * cfg.tile_h * cfg.tile_num * 8;

    n = numel(trace.pixel_idx);
    tile_ids4 = zeros(n, 4, 'uint32');
    unique_count = zeros(n, 1, 'uint8');
    first_use = inf(cfg.total_tiles, 1);
    last_use = -ones(cfg.total_tiles, 1);
    access_count = zeros(cfg.total_tiles, 1);
    last_seen = -ones(cfg.total_tiles, 1);
    gap_sum = zeros(cfg.total_tiles, 1);
    gap_count = zeros(cfg.total_tiles, 1);
    max_gap = zeros(cfg.total_tiles, 1);
    heat_counts = zeros(cfg.tile_count_y, cfg.tile_count_x);
    total_tile_requests = 0;
    cross_tile_pixels = 0;
    primary_tile_changes = 0;
    prev_primary = 0;

    for i = 1:n
        if ~trace.valid(i)
            continue;
        end

        tx00 = floor(double(trace.sample_x0(i)) / cfg.tile_w);
        tx01 = floor(double(trace.sample_x1(i)) / cfg.tile_w);
        ty00 = floor(double(trace.sample_y0(i)) / cfg.tile_h);
        ty10 = floor(double(trace.sample_y1(i)) / cfg.tile_h);

        id00 = tile_id(tx00, ty00, cfg.tile_count_x);
        id01 = tile_id(tx01, ty00, cfg.tile_count_x);
        id10 = tile_id(tx00, ty10, cfg.tile_count_x);
        id11 = tile_id(tx01, ty10, cfg.tile_count_x);
        tile_ids4(i, :) = uint32([id00, id01, id10, id11]);
        ids = ordered_unique4(id00, id01, id10, id11);
        unique_count(i) = uint8(numel(ids));
        total_tile_requests = total_tile_requests + numel(ids);
        if numel(ids) > 1
            cross_tile_pixels = cross_tile_pixels + 1;
        end
        if prev_primary ~= 0 && id00 ~= prev_primary
            primary_tile_changes = primary_tile_changes + 1;
        end
        prev_primary = id00;

        for k = 1:numel(ids)
            tid = ids(k);
            first_use(tid) = min(first_use(tid), double(i - 1));
            last_use(tid) = double(i - 1);
            access_count(tid) = access_count(tid) + 1;
            if last_seen(tid) >= 0
                gap = double(i - 1) - last_seen(tid);
                gap_sum(tid) = gap_sum(tid) + gap;
                gap_count(tid) = gap_count(tid) + 1;
                max_gap(tid) = max(max_gap(tid), gap);
            end
            last_seen(tid) = double(i - 1);
            [tile_x, tile_y] = id_to_tile_xy(tid, cfg.tile_count_x);
            heat_counts(tile_y + 1, tile_x + 1) = heat_counts(tile_y + 1, tile_x + 1) + 1;
        end
    end

    used_ids = find(isfinite(first_use));
    tile_bytes = compute_tile_bytes(cfg, geom);
    ddr = build_prefetch_schedules(cfg, opts, used_ids, first_use, last_use, access_count, tile_bytes);

    no_prefetch = simulate_cache(tile_ids4, first_use, cfg.tile_num, [], [], tile_bytes);
    oracle = simulate_cache(tile_ids4, first_use, cfg.tile_num, ddr.oracle.ready_pixel, ddr.oracle.start_pixel, tile_bytes);
    lookahead = simulate_cache(tile_ids4, first_use, cfg.tile_num, ddr.lookahead.ready_pixel, ddr.lookahead.start_pixel, tile_bytes);

    avg_reuse_gap = 0;
    max_reuse_gap = 0;
    if ~isempty(used_ids)
        max_reuse_gap = max(max_gap(used_ids));
        if any(gap_count(used_ids) > 0)
            avg_reuse_gap = sum(gap_sum(used_ids)) / max(sum(gap_count(used_ids)), 1);
        end
    end

    summary = struct();
    summary.total_pixels = n;
    summary.valid_pixels = sum(trace.valid);
    summary.oob_pixels = n - summary.valid_pixels;
    summary.oob_ratio = summary.oob_pixels / max(n, 1);
    summary.total_tile_requests = total_tile_requests;
    summary.unique_tiles = numel(used_ids);
    summary.cross_tile_pixels = cross_tile_pixels;
    summary.primary_tile_changes = primary_tile_changes;
    summary.avg_reuse_gap = avg_reuse_gap;
    summary.max_reuse_gap = max_reuse_gap;
    summary.max_unique_tiles_per_pixel = max(double(unique_count));
    summary.no_prefetch = no_prefetch;
    summary.oracle = oracle;
    summary.lookahead = lookahead;
    summary.recommended_lead_pixels = ddr.recommended_lead_pixels;
    summary.bram_bits = cfg.bram_bits;
    summary.slot_pressure = (cfg.tile_num <= 4) || (lookahead.max_live_tiles >= cfg.tile_num);

    analysis = struct();
    analysis.cfg = cfg;
    analysis.tile_ids4 = tile_ids4;
    analysis.unique_count = unique_count;
    analysis.first_use = first_use;
    analysis.last_use = last_use;
    analysis.access_count = access_count;
    analysis.tile_bytes = tile_bytes;
    analysis.heat_counts = heat_counts;
    analysis.ddr = ddr;
    analysis.summary = summary;
end

function bytes = compute_tile_bytes(cfg, geom)
    bytes = zeros(cfg.total_tiles, 1);
    for tid = 1:cfg.total_tiles
        [tile_x, tile_y] = id_to_tile_xy(tid, cfg.tile_count_x);
        w = min(cfg.tile_w, geom.src_w - tile_x * cfg.tile_w);
        h = min(cfg.tile_h, geom.src_h - tile_y * cfg.tile_h);
        bytes(tid) = max(w, 0) * max(h, 0);
    end
end

function ddr = build_prefetch_schedules(cfg, opts, used_ids, first_use, last_use, access_count, tile_bytes)
    fill_cycles = opts.DdrLatencyCycles + ceil(tile_bytes / opts.DdrBytesPerCycle);
    if isempty(used_ids)
        recommended_lead_pixels = 0;
    else
        recommended_lead_pixels = max(1, ceil(max(fill_cycles(used_ids)) / opts.PixelCycles));
    end

    latest_prefetch_pixel = nan(cfg.total_tiles, 1);
    oracle_start = nan(cfg.total_tiles, 1);
    oracle_ready = nan(cfg.total_tiles, 1);
    lookahead_start = nan(cfg.total_tiles, 1);
    lookahead_ready = nan(cfg.total_tiles, 1);

    if ~isempty(used_ids)
        latest_prefetch_pixel(used_ids) = max(0, first_use(used_ids) - recommended_lead_pixels);
        [oracle_start, oracle_ready] = schedule_prefetches( ...
            used_ids, latest_prefetch_pixel, first_use, fill_cycles, opts.PixelCycles, opts.DdrOutstanding);

        lookahead_desired = nan(cfg.total_tiles, 1);
        lookahead_desired(used_ids) = max(0, first_use(used_ids) - 2 * recommended_lead_pixels);
        [lookahead_start, lookahead_ready] = schedule_prefetches( ...
            used_ids, lookahead_desired, first_use, fill_cycles, opts.PixelCycles, opts.DdrOutstanding);
    end

    ddr = struct();
    ddr.fill_cycles = fill_cycles;
    ddr.tile_bytes = tile_bytes;
    ddr.recommended_lead_pixels = recommended_lead_pixels;
    ddr.latest_prefetch_pixel = latest_prefetch_pixel;
    ddr.oracle = struct('start_pixel', oracle_start, 'ready_pixel', oracle_ready);
    ddr.lookahead = struct('start_pixel', lookahead_start, 'ready_pixel', lookahead_ready);
    ddr.first_use = first_use;
    ddr.last_use = last_use;
    ddr.access_count = access_count;
end

function [start_pixel, ready_pixel] = schedule_prefetches(used_ids, desired_start_pixel, first_use, fill_cycles, pixel_cycles, outstanding)
    start_pixel = nan(size(first_use));
    ready_pixel = nan(size(first_use));
    [~, order] = sortrows([desired_start_pixel(used_ids), first_use(used_ids)]);
    ordered_ids = used_ids(order);
    lane_free_cycle = zeros(outstanding, 1);

    for k = 1:numel(ordered_ids)
        tid = ordered_ids(k);
        [free_cycle, lane] = min(lane_free_cycle);
        desired_cycle = desired_start_pixel(tid) * pixel_cycles;
        start_cycle = max(desired_cycle, free_cycle);
        finish_cycle = start_cycle + fill_cycles(tid);
        lane_free_cycle(lane) = finish_cycle;
        start_pixel(tid) = floor(start_cycle / pixel_cycles);
        ready_pixel(tid) = ceil(finish_cycle / pixel_cycles);
    end
end

function stats = simulate_cache(tile_ids4, first_use, tile_num, ready_pixel_by_id, start_pixel_by_id, tile_bytes)
    n = size(tile_ids4, 1);
    slot_tile = zeros(tile_num, 1);
    slot_valid = false(tile_num, 1);
    slot_prefetched = false(tile_num, 1);
    last_touch = zeros(tile_num, 1);
    touch = 0;

    stats = struct();
    stats.total_requests = 0;
    stats.misses = 0;
    stats.hits = 0;
    stats.hit_rate = 0;
    stats.prefetches = 0;
    stats.prefetch_hits = 0;
    stats.prefetch_late = 0;
    stats.prefetch_duplicate = 0;
    stats.prefetch_wasted = 0;
    stats.max_live_tiles = 0;
    stats.read_bytes = 0;
    stats.loads = 0;

    event_ids = [];
    event_ready = [];
    if ~isempty(ready_pixel_by_id)
        event_ids = find(~isnan(ready_pixel_by_id) & ~isnan(start_pixel_by_id));
        event_ready = ready_pixel_by_id(event_ids);
        [event_ready, order] = sort(event_ready);
        event_ids = event_ids(order);
        stats.prefetches = numel(event_ids);
    end
    event_ptr = 1;

    for pix = 0:(n - 1)
        ids = ordered_unique4(tile_ids4(pix + 1, 1), tile_ids4(pix + 1, 2), ...
                              tile_ids4(pix + 1, 3), tile_ids4(pix + 1, 4));

        while event_ptr <= numel(event_ids) && event_ready(event_ptr) <= pix
            tid = event_ids(event_ptr);
            if first_use(tid) < pix
                stats.prefetch_late = stats.prefetch_late + 1;
            elseif find_slot(slot_tile, slot_valid, tid) > 0
                stats.prefetch_duplicate = stats.prefetch_duplicate + 1;
            else
                [slot_tile, slot_valid, slot_prefetched, last_touch, touch, stats] = ...
                    allocate_tile(slot_tile, slot_valid, slot_prefetched, last_touch, touch, stats, tid, true, ids, tile_bytes);
            end
            event_ptr = event_ptr + 1;
        end

        stats.total_requests = stats.total_requests + numel(ids);
        for k = 1:numel(ids)
            tid = ids(k);
            slot = find_slot(slot_tile, slot_valid, tid);
            if slot == 0
                stats.misses = stats.misses + 1;
                [slot_tile, slot_valid, slot_prefetched, last_touch, touch, stats] = ...
                    allocate_tile(slot_tile, slot_valid, slot_prefetched, last_touch, touch, stats, tid, false, ids, tile_bytes);
                slot = find_slot(slot_tile, slot_valid, tid);
            else
                stats.hits = stats.hits + 1;
            end

            if slot > 0
                if slot_prefetched(slot)
                    stats.prefetch_hits = stats.prefetch_hits + 1;
                    slot_prefetched(slot) = false;
                end
                touch = touch + 1;
                last_touch(slot) = touch;
            end
        end
        stats.max_live_tiles = max(stats.max_live_tiles, sum(slot_valid));
    end

    if event_ptr <= numel(event_ids)
        stats.prefetch_late = stats.prefetch_late + (numel(event_ids) - event_ptr + 1);
    end
    stats.prefetch_wasted = stats.prefetch_wasted + sum(slot_valid & slot_prefetched);
    if stats.total_requests > 0
        stats.hit_rate = stats.hits / stats.total_requests;
    end
end

function [slot_tile, slot_valid, slot_prefetched, last_touch, touch, stats] = ...
    allocate_tile(slot_tile, slot_valid, slot_prefetched, last_touch, touch, stats, tid, is_prefetch, protected_ids, tile_bytes)

    slot = find(~slot_valid, 1, 'first');
    if isempty(slot)
        candidate = true(size(slot_tile));
        for k = 1:numel(protected_ids)
            candidate = candidate & ~(slot_valid & (slot_tile == protected_ids(k)));
        end
        candidate_idx = find(candidate & slot_valid);
        if isempty(candidate_idx)
            candidate_idx = find(slot_valid);
        end
        [~, rel] = min(last_touch(candidate_idx));
        slot = candidate_idx(rel);
        if slot_prefetched(slot)
            stats.prefetch_wasted = stats.prefetch_wasted + 1;
        end
    end

    slot_tile(slot) = tid;
    slot_valid(slot) = true;
    slot_prefetched(slot) = is_prefetch;
    touch = touch + 1;
    last_touch(slot) = touch;
    stats.loads = stats.loads + 1;
    stats.read_bytes = stats.read_bytes + tile_bytes(tid);
end

function slot = find_slot(slot_tile, slot_valid, tid)
    hit = find(slot_valid & (slot_tile == tid), 1, 'first');
    if isempty(hit)
        slot = 0;
    else
        slot = hit;
    end
end

function id = tile_id(tile_x, tile_y, tile_count_x)
    id = tile_y * tile_count_x + tile_x + 1;
end

function [tile_x, tile_y] = id_to_tile_xy(id, tile_count_x)
    tile_x = mod(double(id) - 1, tile_count_x);
    tile_y = floor((double(id) - 1) / tile_count_x);
end

function ids = ordered_unique4(a, b, c, d)
    vals = double([a, b, c, d]);
    ids = zeros(1, 4);
    count = 0;
    for i = 1:4
        v = vals(i);
        if v > 0 && (count == 0 || ~any(ids(1:count) == v))
            count = count + 1;
            ids(count) = v;
        end
    end
    ids = ids(1:count);
end

function [best_idx, best_score] = choose_best_config(analysis)
    best_idx = 1;
    best_score = inf;
    for i = 1:numel(analysis)
        s = analysis{i}.summary;
        score = double(s.lookahead.misses) * 1e9 + ...
                double(s.lookahead.prefetch_late) * 1e8 + ...
                double(s.lookahead.prefetch_wasted) * 1e6 + ...
                double(s.lookahead.read_bytes) * 10 + ...
                double(s.bram_bits);
        if score < best_score
            best_score = score;
            best_idx = i;
        end
    end
end

function write_coeffs_txt(path, geom, opts, case_cfg, trace)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', path);
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, 'RTL geometry coefficients\n');
    fprintf(fid, '=========================\n');
    fprintf(fid, 'src=%dx%d dst=%dx%d angle_deg=%.6f clockwise_positive=1\n', ...
        geom.src_w, geom.src_h, geom.dst_w, geom.dst_h, geom.angle_deg);
    fprintf(fid, 'pattern=%s input_bin=%s output_bin=output_ref.bin case=%s\n\n', ...
        opts.Pattern, case_cfg.input_bin_name, case_cfg.case_path);

    fprintf(fid, 'Unified inverse mapping, RTL Q16 form:\n');
    fprintf(fid, '  xs_q16 = row0_x_q16 + xo * step_x_x_q16 + yo * step_x_y_q16\n');
    fprintf(fid, '  ys_q16 = row0_y_q16 + xo * step_y_x_q16 + yo * step_y_y_q16\n');
    fprintf(fid, '  If xs_q16/ys_q16 is outside source bounds, output pixel is 0 and no tile is requested.\n\n');

    fprintf(fid, 'Q format:\n');
    fprintf(fid, '  frac_w=%d q_scale=%d\n\n', geom.frac_w, geom.q_scale);

    fprintf(fid, 'Input trigonometry:\n');
    fprintf(fid, '  rot_sin_q16=%d %s float=%.12f\n', geom.rot_sin_q16, hex32(geom.rot_sin_q16), q_to_double(geom.rot_sin_q16, geom.frac_w));
    fprintf(fid, '  rot_cos_q16=%d %s float=%.12f\n\n', geom.rot_cos_q16, hex32(geom.rot_cos_q16), q_to_double(geom.rot_cos_q16, geom.frac_w));

    fprintf(fid, 'Scale and centers:\n');
    fprintf(fid, '  scale_x_q16=%d %s float=%.12f\n', geom.scale_x_q16, hex32(geom.scale_x_q16), q_to_double(geom.scale_x_q16, geom.frac_w));
    fprintf(fid, '  scale_y_q16=%d %s float=%.12f\n', geom.scale_y_q16, hex32(geom.scale_y_q16), q_to_double(geom.scale_y_q16, geom.frac_w));
    fprintf(fid, '  src_cx_q16=%d float=%.12f\n', geom.src_cx_q16, q_to_double(geom.src_cx_q16, geom.frac_w));
    fprintf(fid, '  src_cy_q16=%d float=%.12f\n', geom.src_cy_q16, q_to_double(geom.src_cy_q16, geom.frac_w));
    fprintf(fid, '  dst_cx_q16=%d float=%.12f\n', geom.dst_cx_q16, q_to_double(geom.dst_cx_q16, geom.frac_w));
    fprintf(fid, '  dst_cy_q16=%d float=%.12f\n\n', geom.dst_cy_q16, q_to_double(geom.dst_cy_q16, geom.frac_w));

    fprintf(fid, 'Steps:\n');
    fprintf(fid, '  step_x_x_q16=%d float=%.12f\n', geom.step_x_x_q16, q_to_double(geom.step_x_x_q16, geom.frac_w));
    fprintf(fid, '  step_y_x_q16=%d float=%.12f\n', geom.step_y_x_q16, q_to_double(geom.step_y_x_q16, geom.frac_w));
    fprintf(fid, '  step_x_y_q16=%d float=%.12f\n', geom.step_x_y_q16, q_to_double(geom.step_x_y_q16, geom.frac_w));
    fprintf(fid, '  step_y_y_q16=%d float=%.12f\n', geom.step_y_y_q16, q_to_double(geom.step_y_y_q16, geom.frac_w));
    fprintf(fid, '  scan_dir_x=%d scan_dir_y=%d\n\n', geom.scan_dir_x, geom.scan_dir_y);

    fprintf(fid, 'Row-0 base:\n');
    fprintf(fid, '  row0_x_q16=%d float=%.12f\n', geom.row0_x_q16, q_to_double(geom.row0_x_q16, geom.frac_w));
    fprintf(fid, '  row0_y_q16=%d float=%.12f\n\n', geom.row0_y_q16, q_to_double(geom.row0_y_q16, geom.frac_w));

    fprintf(fid, 'Output coverage:\n');
    fprintf(fid, '  total_pixels=%d valid_pixels=%d oob_pixels=%d oob_ratio=%.6f\n\n', ...
        numel(trace.valid), sum(trace.valid), sum(~trace.valid), sum(~trace.valid) / max(numel(trace.valid), 1));

    fprintf(fid, 'Output corners before zero-fill test:\n');
    fprintf(fid, '  dst_x,dst_y,src_x_q16,src_y_q16,src_x_float,src_y_float\n');
    for k = 1:size(geom.corners, 1)
        fprintf(fid, '  %d,%d,%.0f,%.0f,%.6f,%.6f\n', geom.corners(k, :));
    end
end

function write_timeline_csv(path, trace, cfg)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', path);
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, ['pixel_idx,dst_x,dst_y,valid,src_x_q16,src_y_q16,src_x_float,src_y_float,' ...
        'sample_x0,sample_y0,sample_x1,sample_y1,frac_x_q16,frac_y_q16,' ...
        'p00,p01,p10,p11,output_pixel,tile00_x,tile00_y,tile01_x,tile01_y,' ...
        'tile10_x,tile10_y,tile11_x,tile11_y,unique_tile_count\n']);

    n = numel(trace.pixel_idx);
    for i = 1:n
        if trace.valid(i)
            sx0 = double(trace.sample_x0(i));
            sx1 = double(trace.sample_x1(i));
            sy0 = double(trace.sample_y0(i));
            sy1 = double(trace.sample_y1(i));
            tx00 = floor(sx0 / cfg.tile_w);
            tx01 = floor(sx1 / cfg.tile_w);
            ty00 = floor(sy0 / cfg.tile_h);
            ty10 = floor(sy1 / cfg.tile_h);
            ids = ordered_unique4(tile_id(tx00, ty00, cfg.tile_count_x), ...
                                  tile_id(tx01, ty00, cfg.tile_count_x), ...
                                  tile_id(tx00, ty10, cfg.tile_count_x), ...
                                  tile_id(tx01, ty10, cfg.tile_count_x));
        else
            tx00 = -1; tx01 = -1; ty00 = -1; ty10 = -1; ids = [];
        end
        fprintf(fid, '%d,%d,%d,%d,%d,%d,%.6f,%.6f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n', ...
            trace.pixel_idx(i), trace.dst_x(i), trace.dst_y(i), trace.valid(i), ...
            trace.src_x_q16(i), trace.src_y_q16(i), ...
            q_to_double(trace.src_x_q16(i), 16), q_to_double(trace.src_y_q16(i), 16), ...
            trace.sample_x0(i), trace.sample_y0(i), trace.sample_x1(i), trace.sample_y1(i), ...
            trace.frac_x_q16(i), trace.frac_y_q16(i), ...
            trace.p00(i), trace.p01(i), trace.p10(i), trace.p11(i), trace.output_pixel(i), ...
            tx00, ty00, tx01, ty00, tx00, ty10, tx01, ty10, numel(ids));
    end
end

function write_prefetch_plan_csv(path, analysis)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', path);
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, ['tile_x,tile_y,first_use_pixel,last_use_pixel,access_count,tile_bytes,' ...
        'fill_cycles,lead_pixels,prefetch_at_pixel,oracle_start_pixel,oracle_ready_pixel,' ...
        'lookahead_start_pixel,lookahead_ready_pixel,risk\n']);

    used_ids = find(isfinite(analysis.first_use));
    [~, order] = sort(analysis.first_use(used_ids));
    used_ids = used_ids(order);
    for k = 1:numel(used_ids)
        tid = used_ids(k);
        [tile_x, tile_y] = id_to_tile_xy(tid, analysis.cfg.tile_count_x);
        risk = 'ok';
        if analysis.ddr.oracle.ready_pixel(tid) > analysis.first_use(tid)
            risk = 'late_prefetch';
        elseif analysis.ddr.latest_prefetch_pixel(tid) == 0 && analysis.first_use(tid) < analysis.ddr.recommended_lead_pixels
            risk = 'startup_window';
        elseif analysis.summary.slot_pressure
            risk = 'slot_pressure';
        end
        fprintf(fid, '%d,%d,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%s\n', ...
            tile_x, tile_y, analysis.first_use(tid), analysis.last_use(tid), ...
            analysis.access_count(tid), analysis.tile_bytes(tid), analysis.ddr.fill_cycles(tid), ...
            analysis.ddr.recommended_lead_pixels, analysis.ddr.latest_prefetch_pixel(tid), ...
            analysis.ddr.oracle.start_pixel(tid), analysis.ddr.oracle.ready_pixel(tid), ...
            analysis.ddr.lookahead.start_pixel(tid), analysis.ddr.lookahead.ready_pixel(tid), risk);
    end
end

function write_summary_csv(path, analysis)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', path);
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, ['tile_w,tile_h,tile_num,tile_count_x,tile_count_y,total_pixels,valid_pixels,oob_pixels,oob_ratio,' ...
        'total_tile_requests,unique_tiles,cross_tile_pixels,primary_tile_changes,lead_pixels,bram_bits,slot_pressure,' ...
        'no_prefetch_misses,no_prefetch_hit_rate,no_prefetch_read_bytes,' ...
        'oracle_misses,oracle_prefetches,oracle_hits,oracle_wasted,oracle_late,oracle_read_bytes,' ...
        'lookahead_misses,lookahead_prefetches,lookahead_hits,lookahead_wasted,lookahead_late,lookahead_read_bytes,' ...
        'avg_reuse_gap,max_reuse_gap\n']);
    for i = 1:numel(analysis)
        a = analysis{i};
        s = a.summary;
        fprintf(fid, ['%d,%d,%d,%d,%d,%d,%d,%d,%.6f,%d,%d,%d,%d,%d,%d,%d,' ...
            '%d,%.6f,%.0f,%d,%d,%d,%d,%d,%.0f,%d,%d,%d,%d,%d,%.0f,%.6f,%.0f\n'], ...
            a.cfg.tile_w, a.cfg.tile_h, a.cfg.tile_num, a.cfg.tile_count_x, a.cfg.tile_count_y, ...
            s.total_pixels, s.valid_pixels, s.oob_pixels, s.oob_ratio, ...
            s.total_tile_requests, s.unique_tiles, s.cross_tile_pixels, ...
            s.primary_tile_changes, s.recommended_lead_pixels, s.bram_bits, s.slot_pressure, ...
            s.no_prefetch.misses, s.no_prefetch.hit_rate, s.no_prefetch.read_bytes, ...
            s.oracle.misses, s.oracle.prefetches, s.oracle.prefetch_hits, s.oracle.prefetch_wasted, s.oracle.prefetch_late, s.oracle.read_bytes, ...
            s.lookahead.misses, s.lookahead.prefetches, s.lookahead.prefetch_hits, s.lookahead.prefetch_wasted, s.lookahead.prefetch_late, s.lookahead.read_bytes, ...
            s.avg_reuse_gap, s.max_reuse_gap);
    end
end

function write_summary_txt(path, geom, opts, analysis, paths, best_idx, best_score)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', path);
    cleaner = onCleanup(@() fclose(fid));

    base = analysis{1}.summary;
    fprintf(fid, 'Tile/cache reference summary\n');
    fprintf(fid, '============================\n');
    fprintf(fid, 'src=%dx%d dst=%dx%d angle=%.6f deg pattern=%s\n', ...
        geom.src_w, geom.src_h, geom.dst_w, geom.dst_h, geom.angle_deg, opts.Pattern);
    if isempty(opts.Seed)
        fprintf(fid, 'seed=\n');
    else
        fprintf(fid, 'seed=%d\n', opts.Seed);
    end
    fprintf(fid, 'zero_fill_oob=1 valid_pixels=%d oob_pixels=%d oob_ratio=%.6f\n', ...
        base.valid_pixels, base.oob_pixels, base.oob_ratio);
    fprintf(fid, 'DDR model: latency=%.0f cycles, bytes_per_cycle=%.3f, outstanding=%d, pixel_cycles=%.3f\n\n', ...
        opts.DdrLatencyCycles, opts.DdrBytesPerCycle, opts.DdrOutstanding, opts.PixelCycles);

    fprintf(fid, 'Configs:\n');
    fprintf(fid, 'tile_w tile_h slots uniq  reqs no_pf_miss look_miss look_late look_bytes bram_bits lead pressure\n');
    for i = 1:numel(analysis)
        a = analysis{i};
        s = a.summary;
        fprintf(fid, '%6d %6d %5d %4d %5d %10d %9d %9d %10.0f %9d %4d %8d\n', ...
            a.cfg.tile_w, a.cfg.tile_h, a.cfg.tile_num, s.unique_tiles, s.total_tile_requests, ...
            s.no_prefetch.misses, s.lookahead.misses, s.lookahead.prefetch_late, ...
            s.lookahead.read_bytes, s.bram_bits, s.recommended_lead_pixels, s.slot_pressure);
    end

    b = analysis{best_idx};
    fprintf(fid, '\nRecommended for this case: TILE_W=%d TILE_H=%d TILE_NUM=%d lead_pixels=%d\n', ...
        b.cfg.tile_w, b.cfg.tile_h, b.cfg.tile_num, b.summary.recommended_lead_pixels);
    fprintf(fid, 'score=%.0f\n', best_score);
    if b.summary.slot_pressure
        fprintf(fid, 'note=slot pressure is high; do not prefetch beyond the live window, or current 4-sample tiles may be evicted.\n');
    else
        fprintf(fid, 'note=prefetch_at=max(0, first_use_pixel - lead_pixels). Keep candidates ordered by first_use_pixel.\n');
    end
    fprintf(fid, 'rtl_note=current RTL clamp behavior differs from this MATLAB zero-fill OOB reference.\n\n');

    fprintf(fid, 'Generated files:\n');
    fprintf(fid, '  input_png=%s\n', paths.input_png);
    fprintf(fid, '  input_bin=%s\n', paths.input_bin);
    fprintf(fid, '  input_txt=%s\n', paths.input_txt);
    fprintf(fid, '  output_png=%s\n', paths.output_png);
    fprintf(fid, '  output_bin=%s\n', paths.output_bin);
    fprintf(fid, '  output_txt=%s\n', paths.output_txt);
    fprintf(fid, '  coeffs_txt=%s\n', paths.coeffs_txt);
    fprintf(fid, '  summary_csv=%s\n', paths.summary_csv);
    fprintf(fid, '  prefetch_plan_csv=%s\n', paths.prefetch_csv);
    fprintf(fid, '  tile_heatmap_png=%s\n', paths.heatmap_png);
    if ~isempty(paths.timeline_csv)
        fprintf(fid, '  tile_timeline_csv=%s\n', paths.timeline_csv);
    end
end

function write_heatmap_png(path, heat_counts)
    max_count = max(heat_counts(:));
    if max_count <= 0
        heat_u8 = uint8(zeros(size(heat_counts)));
    else
        heat_u8 = uint8(round(255 * log1p(heat_counts) / log1p(max_count)));
    end
    max_dim = max(size(heat_u8));
    scale = max(1, min(16, floor(768 / max(max_dim, 1))));
    heat_img = kron(heat_u8, ones(scale, scale, 'uint8'));
    imwrite(heat_img, path);
end

function write_raw_bin_local(img, bin_path)
    bytes = reshape(img.', [], 1);
    fid = fopen(bin_path, 'wb');
    assert(fid >= 0, 'Failed to open %s for writing.', bin_path);
    cleaner = onCleanup(@() fclose(fid));
    count = fwrite(fid, bytes, 'uint8');
    assert(count == numel(bytes), 'Incomplete write to %s.', bin_path);
end

function write_pixel_txt_local(img, txt_path)
    fid = fopen(txt_path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', txt_path);
    cleaner = onCleanup(@() fclose(fid));

    [height, width] = size(img);
    fprintf(fid, '# format=row-major uint8 grayscale, hex byte per pixel\n');
    fprintf(fid, '# width=%d height=%d byte_offset=y*width+x\n', width, height);
    for y = 1:height
        for x = 1:width
            if x < width
                fprintf(fid, '%02X ', img(y, x));
            else
                fprintf(fid, '%02X\n', img(y, x));
            end
        end
    end
end

function x = q_to_double(q, frac_w)
    x = double(q) / double(2^frac_w);
end

function txt = hex32(q)
    u = uint32(mod(double(q), 2^32));
    txt = sprintf('0x%08X', u);
end
