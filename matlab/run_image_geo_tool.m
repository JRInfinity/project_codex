% Unified user entry for image generation and tile/cache reference analysis.
%
% Edit the configuration block below, then run this file from MATLAB.
%
% mode:
%   "input_only"  - Generate input.png/input.bin/input.txt/input_meta.txt/case.txt.
%   "single_case" - Generate input files, output_ref image, coefficients, tile/cache stats.
%   "sweep"       - Run representative cases and emit rtl_recommendations.md/.csv.

clear;
clc;

this_dir = fileparts(mfilename('fullpath'));
if ~isempty(this_dir)
    addpath(this_dir);
end

%% User configuration

mode = "single_case";  % "input_only", "single_case", or "sweep"

src_w = 600;
src_h = 600;
dst_w = 600;
dst_h = 600;
angle_deg = 45;        % Clockwise is positive.

pattern = "random_blocks";
seed = 1;              % Use [] for non-reproducible random patterns.
case_name = "";        % Empty means auto-name from size and angle.

tile_configs = [
    16 16 8
    32 16 8
    32 16 12
    32 16 16
    32 32 8
    32 32 12
    64 16 8
    64 32 8
];

ddr_latency_cycles = 80;
ddr_bytes_per_cycle = 4;
ddr_outstanding = 1;
pixel_cycles = 1;

write_pixel_txt = true;    % Set false for very large images.
write_timeline = false;    % Only enable for small RTL trace-debug cases.

result_root = fullfile(this_dir, "out", "cache_ref_runs");
input_only_root = fullfile(this_dir, "out", "ddr_inputs");

% Sweep mode uses these cases. Add/remove rows here when exploring RTL params.
sweep_cases = default_sweep_cases();

%% Run selected mode

mode = lower(mode);
if strlength(case_name) == 0
    case_name = make_case_name(src_w, src_h, dst_w, dst_h, angle_deg);
end

switch mode
    case "input_only"
        case_dir = fullfile(input_only_root, case_name);
        if ~exist(case_dir, 'dir')
            mkdir(case_dir);
        end
        [cfg, ~, meta] = export_image_geo_case(src_w, src_h, pattern, ...
            fullfile(case_dir, "input"), dst_w, dst_h, angle_deg, ...
            "Seed", seed, ...
            "WritePreview", false, ...
            "WriteCoe", false, ...
            "WritePixelTxt", write_pixel_txt, ...
            "CasePath", fullfile(case_dir, "case.txt"), ...
            "OutputBinName", "output_ref.bin");
        fprintf('\nInput-only generation complete.\n');
        fprintf('  case_dir: %s\n', case_dir);
        fprintf('  input_png: %s\n', meta.png_path);
        fprintf('  input_bin: %s\n', meta.bin_path);
        fprintf('  input_txt: %s\n', meta.pixel_txt_path);
        fprintf('  case_txt:  %s\n', cfg.case_path);

    case "single_case"
        result = image_geo_cache_ref(src_w, src_h, dst_w, dst_h, angle_deg, ...
            "Pattern", pattern, ...
            "Seed", seed, ...
            "ResultRoot", result_root, ...
            "CaseName", case_name, ...
            "TileConfigs", tile_configs, ...
            "DdrLatencyCycles", ddr_latency_cycles, ...
            "DdrBytesPerCycle", ddr_bytes_per_cycle, ...
            "DdrOutstanding", ddr_outstanding, ...
            "PixelCycles", pixel_cycles, ...
            "WriteTimeline", write_timeline, ...
            "WritePreview", false, ...
            "WriteCoe", false, ...
            "WritePixelTxt", write_pixel_txt);
        fprintf('\nSingle-case analysis complete.\n');
        fprintf('  case_dir: %s\n', result.case_dir);
        fprintf('  summary:  %s\n', result.paths.summary_txt);
        fprintf('  coeffs:   %s\n', result.paths.coeffs_txt);

    case "sweep"
        run_sweep(result_root, sweep_cases, pattern, seed, tile_configs, ...
            ddr_latency_cycles, ddr_bytes_per_cycle, ddr_outstanding, pixel_cycles);

    otherwise
        error('Unsupported mode: %s. Use input_only, single_case, or sweep.', mode);
end

function run_sweep(result_root, cases, pattern, seed_base, tile_configs, ...
    ddr_latency_cycles, ddr_bytes_per_cycle, ddr_outstanding, pixel_cycles)
    if ~exist(result_root, 'dir')
        mkdir(result_root);
    end

    rows = repmat(empty_row(), numel(cases), 1);
    for k = 1:numel(cases)
        c = cases(k);
        case_seed = seed_base;
        if ~isempty(seed_base)
            case_seed = seed_base + k - 1;
        end
        fprintf('\n[%02d/%02d] %s\n', k, numel(cases), c.name);
        r = image_geo_cache_ref(c.src_w, c.src_h, c.dst_w, c.dst_h, c.angle_deg, ...
            "Pattern", pattern, ...
            "Seed", case_seed, ...
            "ResultRoot", result_root, ...
            "CaseName", c.name, ...
            "TileConfigs", tile_configs, ...
            "DdrLatencyCycles", ddr_latency_cycles, ...
            "DdrBytesPerCycle", ddr_bytes_per_cycle, ...
            "DdrOutstanding", ddr_outstanding, ...
            "PixelCycles", pixel_cycles, ...
            "WriteTimeline", false, ...
            "WritePreview", false, ...
            "WriteCoe", false, ...
            "WritePixelTxt", false);
        rows(k) = make_row(c, r);
    end

    csv_path = fullfile(result_root, "rtl_recommendations.csv");
    md_path = fullfile(result_root, "rtl_recommendations.md");
    write_recommendation_csv(csv_path, rows);
    write_recommendation_md(md_path, rows, tile_configs, ...
        ddr_latency_cycles, ddr_bytes_per_cycle, ddr_outstanding, pixel_cycles);

    fprintf('\nSweep complete.\n');
    fprintf('  csv: %s\n', csv_path);
    fprintf('  md:  %s\n', md_path);
end

function cases = default_sweep_cases()
    specs = {};
    specs{end+1} = {600, 600, 600, 600, [0 15 45 75 90]};
    specs{end+1} = {1200, 1200, 600, 600, [0 15 45 75]};
    specs{end+1} = {2400, 2400, 600, 600, [0 30 45 60]};
    specs{end+1} = {7200, 6000, 600, 500, [0 15 45 75]};
    specs{end+1} = {300, 300, 600, 600, [0 45]};

    cases = struct('src_w', {}, 'src_h', {}, 'dst_w', {}, 'dst_h', {}, ...
        'angle_deg', {}, 'name', {});
    for s = 1:numel(specs)
        item = specs{s};
        src_w = item{1};
        src_h = item{2};
        dst_w = item{3};
        dst_h = item{4};
        angles = item{5};
        for a = 1:numel(angles)
            c = struct();
            c.src_w = src_w;
            c.src_h = src_h;
            c.dst_w = dst_w;
            c.dst_h = dst_h;
            c.angle_deg = angles(a);
            c.name = make_case_name(src_w, src_h, dst_w, dst_h, angles(a));
            cases(end+1) = c; %#ok<AGROW>
        end
    end
end

function name = make_case_name(src_w, src_h, dst_w, dst_h, angle_deg)
    angle_txt = sprintf('%g', angle_deg);
    angle_txt = strrep(angle_txt, '-', 'm');
    angle_txt = strrep(angle_txt, '.', 'p');
    name = sprintf('src%dx%d_dst%dx%d_rot%s', src_w, src_h, dst_w, dst_h, angle_txt);
end

function row = empty_row()
    row = struct( ...
        'case_name', '', ...
        'group_name', '', ...
        'scale_class', '', ...
        'src_w', 0, 'src_h', 0, 'dst_w', 0, 'dst_h', 0, 'angle_deg', 0, ...
        'oob_ratio', 0, ...
        'tile_w', 0, 'tile_h', 0, 'tile_num', 0, 'lead_pixels', 0, ...
        'lookahead_misses', 0, 'lookahead_late', 0, 'lookahead_wasted', 0, ...
        'read_bytes', 0, 'bram_bits', 0, 'score', 0, ...
        'case_dir', '');
end

function row = make_row(c, result)
    best = result.analysis{result.best_idx};
    s = best.summary;
    row = empty_row();
    row.case_name = c.name;
    row.group_name = classify_angle(c.angle_deg);
    row.scale_class = classify_scale(c.src_w, c.src_h, c.dst_w, c.dst_h);
    row.src_w = c.src_w;
    row.src_h = c.src_h;
    row.dst_w = c.dst_w;
    row.dst_h = c.dst_h;
    row.angle_deg = c.angle_deg;
    row.oob_ratio = s.oob_ratio;
    row.tile_w = best.cfg.tile_w;
    row.tile_h = best.cfg.tile_h;
    row.tile_num = best.cfg.tile_num;
    row.lead_pixels = s.recommended_lead_pixels;
    row.lookahead_misses = s.lookahead.misses;
    row.lookahead_late = s.lookahead.prefetch_late;
    row.lookahead_wasted = s.lookahead.prefetch_wasted;
    row.read_bytes = s.lookahead.read_bytes;
    row.bram_bits = s.bram_bits;
    row.score = result.best_score;
    row.case_dir = result.case_dir;
end

function g = classify_angle(angle_deg)
    a = abs(angle_deg);
    if a == 0
        g = 'pure_scale_0deg';
    elseif a <= 15
        g = 'small_angle';
    elseif a >= 75
        g = 'near_90_or_large_angle';
    elseif a >= 30 && a <= 60
        g = 'diagonal_30_60';
    else
        g = 'mid_angle';
    end
end

function s = classify_scale(src_w, src_h, dst_w, dst_h)
    sx = dst_w / src_w;
    sy = dst_h / src_h;
    scale = min(sx, sy);
    if sx > 1 || sy > 1
        s = 'upscale';
    elseif scale <= 0.25
        s = 'large_downscale';
    elseif scale < 1
        s = 'downscale';
    else
        s = 'same_size';
    end
end

function write_recommendation_csv(path, rows)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', path);
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, ['case_name,group_name,scale_class,src_w,src_h,dst_w,dst_h,angle_deg,oob_ratio,' ...
        'tile_w,tile_h,tile_num,lead_pixels,lookahead_misses,lookahead_late,lookahead_wasted,' ...
        'read_bytes,bram_bits,score,case_dir\n']);
    for i = 1:numel(rows)
        r = rows(i);
        fprintf(fid, '%s,%s,%s,%d,%d,%d,%d,%.6f,%.6f,%d,%d,%d,%d,%d,%d,%d,%.0f,%d,%.0f,%s\n', ...
            r.case_name, r.group_name, r.scale_class, r.src_w, r.src_h, r.dst_w, r.dst_h, ...
            r.angle_deg, r.oob_ratio, r.tile_w, r.tile_h, r.tile_num, r.lead_pixels, ...
            r.lookahead_misses, r.lookahead_late, r.lookahead_wasted, r.read_bytes, ...
            r.bram_bits, r.score, r.case_dir);
    end
end

function write_recommendation_md(path, rows, tile_configs, ddr_latency, ...
    bytes_per_cycle, outstanding, pixel_cycles)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', path);
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, '# RTL Tile/Prefetch Recommendations\n\n');
    fprintf(fid, 'DDR model: latency %.0f cycles, %.3f bytes/cycle, outstanding %d, pixel %.3f cycles.\n\n', ...
        ddr_latency, bytes_per_cycle, outstanding, pixel_cycles);
    fprintf(fid, 'Candidate tile configs:\n\n');
    fprintf(fid, '| tile_w | tile_h | tile_num |\n|---:|---:|---:|\n');
    for i = 1:size(tile_configs, 1)
        fprintf(fid, '| %d | %d | %d |\n', tile_configs(i, 1), tile_configs(i, 2), tile_configs(i, 3));
    end

    fprintf(fid, '\n## Per-Case Best\n\n');
    fprintf(fid, '| Case | Group | Scale | OOB | Tile | Lead | Miss | Late | Wasted | BRAM bits |\n');
    fprintf(fid, '|---|---|---|---:|---|---:|---:|---:|---:|---:|\n');
    for i = 1:numel(rows)
        r = rows(i);
        fprintf(fid, '| `%s` | %s | %s | %.3f | %dx%d x%d | %d | %d | %d | %d | %d |\n', ...
            r.case_name, r.group_name, r.scale_class, r.oob_ratio, ...
            r.tile_w, r.tile_h, r.tile_num, r.lead_pixels, ...
            r.lookahead_misses, r.lookahead_late, r.lookahead_wasted, r.bram_bits);
    end

    fprintf(fid, '\n## Group Guidance\n\n');
    groups = unique({rows.group_name});
    for g = 1:numel(groups)
        group = groups{g};
        group_rows = rows(strcmp({rows.group_name}, group));
        [tile_w, tile_h, tile_num, lead] = aggregate_group(group_rows);
        fprintf(fid, '- `%s`: recommend `TILE_W=%d`, `TILE_H=%d`, `TILE_NUM=%d`, lead around `%d` pixels. ', ...
            group, tile_w, tile_h, tile_num, lead);
        fprintf(fid, 'Prefetch at `max(0, first_use_pixel - lead_pixels)` and keep candidates ordered by first use.\n');
    end

    fprintf(fid, '\n## Notes\n\n');
    fprintf(fid, '- OOB pixels are zero-filled in this MATLAB reference and do not request tiles.\n');
    fprintf(fid, '- Current RTL clamp behavior differs from this target reference; account for that when comparing output images.\n');
    fprintf(fid, '- When `tile_num` is close to 4, avoid prefetching beyond the live window so the current four bilinear sample tiles are not evicted.\n');
end

function [tile_w, tile_h, tile_num, lead] = aggregate_group(rows)
    keys = cell(numel(rows), 1);
    for i = 1:numel(rows)
        keys{i} = sprintf('%d_%d_%d', rows(i).tile_w, rows(i).tile_h, rows(i).tile_num);
    end
    unique_keys = unique(keys);
    best_key = unique_keys{1};
    best_score = inf;
    for k = 1:numel(unique_keys)
        idx = strcmp(keys, unique_keys{k});
        score = mean([rows(idx).score]);
        if score < best_score
            best_score = score;
            best_key = unique_keys{k};
        end
    end
    parts = sscanf(best_key, '%d_%d_%d');
    tile_w = parts(1);
    tile_h = parts(2);
    tile_num = parts(3);
    idx = strcmp(keys, best_key);
    lead = ceil(median([rows(idx).lead_pixels]));
end
