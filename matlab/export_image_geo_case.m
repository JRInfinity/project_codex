function cfg = export_image_geo_case(src_w, src_h, pattern, out_prefix, dst_w, dst_h, angle_deg)
%EXPORT_IMAGE_GEO_CASE Generate MATLAB image assets plus a software run config.
%   CFG = EXPORT_IMAGE_GEO_CASE(SRC_W, SRC_H, PATTERN, OUT_PREFIX, DST_W, DST_H, ANGLE_DEG)
%   creates:
%   - <OUT_PREFIX>.bin
%   - <OUT_PREFIX>_meta.txt
%   - <OUT_PREFIX>_case.txt
%
%   The _case.txt file is intended for the Vitis bare-metal bring-up program.
%
%   Example:
%       cfg = export_image_geo_case(640, 480, "checkerboard", ...
%           "out/test_640x480", 640, 480, 0);

    if nargin < 1 || isempty(src_w)
        src_w = 640;
    end
    if nargin < 2 || isempty(src_h)
        src_h = 480;
    end
    if nargin < 3 || isempty(pattern)
        pattern = "checkerboard";
    end
    if nargin < 4 || isempty(out_prefix)
        out_prefix = "out/test_640x480";
    end
    if nargin < 5 || isempty(dst_w)
        dst_w = src_w;
    end
    if nargin < 6 || isempty(dst_h)
        dst_h = src_h;
    end
    if nargin < 7 || isempty(angle_deg)
        angle_deg = 0;
    end

    [~, meta] = generate_gray_image(src_w, src_h, pattern, out_prefix);

    out_prefix = string(out_prefix);
    [~, base_name, ~] = fileparts(out_prefix);
    case_path = out_prefix + "_case.txt";
    input_bin_name = base_name + ".bin";
    output_bin_name = "out_" + base_name + ".bin";

    rot_sin_q16 = float_to_q16(sind(angle_deg));
    rot_cos_q16 = float_to_q16(cosd(angle_deg));

    fid = fopen(case_path, 'w');
    if fid < 0
        error('Failed to open case file for writing: %s', case_path);
    end

    cleanup = onCleanup(@() fclose(fid));

    fprintf(fid, 'input_bin=%s\n', input_bin_name);
    fprintf(fid, 'output_bin=%s\n', output_bin_name);
    fprintf(fid, 'src_w=%d\n', src_w);
    fprintf(fid, 'src_h=%d\n', src_h);
    fprintf(fid, 'src_stride=%d\n', src_w);
    fprintf(fid, 'dst_w=%d\n', dst_w);
    fprintf(fid, 'dst_h=%d\n', dst_h);
    fprintf(fid, 'dst_stride=%d\n', dst_w);
    fprintf(fid, 'angle_deg=%.6f\n', angle_deg);
    fprintf(fid, 'rot_sin_q16=%d\n', rot_sin_q16);
    fprintf(fid, 'rot_cos_q16=%d\n', rot_cos_q16);
    fprintf(fid, 'prefetch_enable=1\n');
    fprintf(fid, 'pixel_bits=%d\n', meta.pixel_bits);
    fprintf(fid, 'bytes_per_pixel=1\n');
    fprintf(fid, 'storage=row-major\n');

    cfg = struct();
    cfg.case_path = char(case_path);
    cfg.input_bin_name = char(input_bin_name);
    cfg.output_bin_name = char(output_bin_name);
    cfg.src_w = src_w;
    cfg.src_h = src_h;
    cfg.src_stride = src_w;
    cfg.dst_w = dst_w;
    cfg.dst_h = dst_h;
    cfg.dst_stride = dst_w;
    cfg.angle_deg = angle_deg;
    cfg.rot_sin_q16 = rot_sin_q16;
    cfg.rot_cos_q16 = rot_cos_q16;
    cfg.prefetch_enable = 1;
end

function q = float_to_q16(x)
    q = round(double(x) * 65536.0);
end
