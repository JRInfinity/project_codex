function [img, meta] = generate_gray_image(width, height, pattern, out_prefix)
%GENERATE_GRAY_IMAGE Generate an 8-bit grayscale image and export DDR-friendly files.
%   [IMG, META] = GENERATE_GRAY_IMAGE(WIDTH, HEIGHT, PATTERN, OUT_PREFIX)
%   creates a HEIGHT x WIDTH uint8 image with pixels in [0,255].
%
%   Outputs:
%   1) <OUT_PREFIX>.png
%      Human-readable debug image.
%   2) <OUT_PREFIX>_preview.png
%      Debug image with grayscale legend bar on the right side.
%   3) <OUT_PREFIX>.bin
%      Raw bytes for PS DDR. Layout is row-major, 1 byte per pixel:
%      byte offset = y * width + x, with x in [0,width-1], y in [0,height-1]
%   4) <OUT_PREFIX>.coe
%      Optional BRAM/ROM initialization text in hexadecimal byte format.
%   5) <OUT_PREFIX>_meta.txt
%      Basic metadata for software/RTL integration.
%
%   PATTERN options:
%   - "random"
%   - "horizontal_gradient"
%   - "vertical_gradient"
%   - "checkerboard"
%   - "noisy_gradient"
%   - "random_blocks"
%   - "impulse_points"
%   - "rings"
%   - "diagonal_ramp"
%   - "constant"
%
%   Example:
%       [img, meta] = generate_gray_image(640, 480, "horizontal_gradient", "out/test_640x480");

    if nargin < 1 || isempty(width)
        width = 640;
    end
    if nargin < 2 || isempty(height)
        height = 480;
    end
    if nargin < 3 || isempty(pattern)
        pattern = "horizontal_gradient";
    end
    if nargin < 4 || isempty(out_prefix)
        out_prefix = sprintf("out/img_%dx%d", width, height);
    end

    validateattributes(width,  {'numeric'}, {'scalar', 'integer', 'positive'});
    validateattributes(height, {'numeric'}, {'scalar', 'integer', 'positive'});

    pattern = string(pattern);
    out_prefix = string(out_prefix);

    out_dir = fileparts(out_prefix);
    if strlength(out_dir) > 0 && ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    img = build_pattern(width, height, pattern);
    img = uint8(img);

    png_path     = out_prefix + ".png";
    preview_path = out_prefix + "_preview.png";
    bin_path     = out_prefix + ".bin";
    coe_path     = out_prefix + ".coe";
    meta_path    = out_prefix + "_meta.txt";

    imwrite(img, png_path);
    imwrite(make_preview_with_legend(img), preview_path);
    write_raw_bin(img, bin_path);
    write_coe(img, coe_path);
    write_meta(width, height, pattern, png_path, preview_path, bin_path, coe_path, meta_path);

    meta = struct();
    meta.width = width;
    meta.height = height;
    meta.pixel_bits = 8;
    meta.total_bytes = width * height;
    meta.layout = 'row-major';
    meta.bin_path = char(bin_path);
    meta.png_path = char(png_path);
    meta.preview_path = char(preview_path);
    meta.coe_path = char(coe_path);
    meta.ddr_note = '1 byte per pixel, contiguous row-major storage';
end

function img = build_pattern(width, height, pattern)
    [x, y] = meshgrid(0:width-1, 0:height-1);

    switch lower(char(pattern))
        case 'random'
            img = randi([0, 255], height, width, 'uint8');

        case 'horizontal_gradient'
            row = uint8(round(linspace(0, 255, width)));
            img = repmat(row, height, 1);

        case 'vertical_gradient'
            col = uint8(round(linspace(0, 255, height))).';
            img = repmat(col, 1, width);

        case 'checkerboard'
            block = 16;
            img = uint8(mod(floor(x / block) + floor(y / block), 2) * 255);

        case 'noisy_gradient'
            base = double(repmat(uint8(round(linspace(0, 255, width))), height, 1));
            noise = 24 * randn(height, width);
            img = uint8(min(max(round(base + noise), 0), 255));

        case 'random_blocks'
            block = 16;
            bh = ceil(height / block);
            bw = ceil(width / block);
            coarse = randi([0, 255], bh, bw, 'uint8');
            img = kron(coarse, ones(block, block, 'uint8'));
            img = img(1:height, 1:width);

        case 'impulse_points'
            img = uint8(zeros(height, width));
            count = max(8, round(0.01 * width * height));
            idx = randperm(width * height, min(count, width * height));
            vals = uint8(randi([0, 255], numel(idx), 1));
            img(idx) = vals;

        case 'rings'
            xc = (width - 1) / 2;
            yc = (height - 1) / 2;
            r = sqrt((x - xc).^2 + (y - yc).^2);
            img = uint8(round(255 * 0.5 * (1 + sin(r / 6))));

        case 'diagonal_ramp'
            denom = max(width + height - 2, 1);
            img = uint8(round(255 * (x + y) / denom));

        case 'constant'
            img = uint8(128 * ones(height, width));

        otherwise
            error('Unsupported pattern: %s', pattern);
    end
end

function preview = make_preview_with_legend(img)
    [height, ~] = size(img);
    legend_w = 156;
    gap_w = 12;

    preview = uint8(255 * ones(height, size(img, 2) + gap_w + legend_w));
    preview(:, 1:size(img, 2)) = img;

    bar_left = size(img, 2) + gap_w + 64;
    bar_w = 24;
    title_y = 8;
    bar_h = max(height - 56, 32);
    bar_top = 24;
    bar_bottom = bar_top + bar_h - 1;
    ramp = uint8(round(linspace(255, 0, bar_h))).';
    preview(bar_top:bar_bottom, bar_left:bar_left + bar_w - 1) = repmat(ramp, 1, bar_w);

    preview = draw_rect_outline(preview, bar_left - 1, bar_top - 1, bar_w + 2, bar_h + 2);
    preview = draw_tick(preview, bar_left - 8, bar_top, 8);
    preview = draw_tick(preview, bar_left - 8, bar_bottom, 8);

    title = 'Gray Level';
    title_x = bar_left + floor((bar_w - text_width(title)) / 2);
    preview = put_text(preview, title_x, title_y, title);

    preview = put_text(preview, bar_left - text_width('255') - 18, bar_top - 3, '255');
    preview = put_text(preview, bar_left - text_width('0') - 18, bar_bottom - 3, '0');
end

function img = put_text(img, x, y, text)
    cursor_x = x;
    for c = char(text)
        glyph = glyph5x7(c);
        img = draw_glyph(img, cursor_x, y, glyph);
        cursor_x = cursor_x + size(glyph, 2) + 1;
    end
end

function w = text_width(text)
    w = 0;
    for c = char(text)
        glyph = glyph5x7(c);
        w = w + size(glyph, 2) + 1;
    end
    if w > 0
        w = w - 1;
    end
end

function img = draw_glyph(img, x, y, glyph)
    [h, w] = size(glyph);
    [img_h, img_w] = size(img);
    for row = 1:h
        for col = 1:w
            yy = y + row - 1;
            xx = x + col - 1;
            if yy >= 1 && yy <= img_h && xx >= 1 && xx <= img_w && glyph(row, col)
                img(yy, xx) = uint8(0);
            end
        end
    end
end

function img = draw_rect_outline(img, x, y, w, h)
    [img_h, img_w] = size(img);
    x0 = max(1, x);
    y0 = max(1, y);
    x1 = min(img_w, x + w - 1);
    y1 = min(img_h, y + h - 1);

    img(y0, x0:x1) = uint8(0);
    img(y1, x0:x1) = uint8(0);
    img(y0:y1, x0) = uint8(0);
    img(y0:y1, x1) = uint8(0);
end

function img = draw_tick(img, x_right, y_center, len)
    [img_h, img_w] = size(img);
    y0 = max(1, y_center);
    x0 = max(1, x_right - len + 1);
    x1 = min(img_w, x_right);
    if y0 >= 1 && y0 <= img_h
        img(y0, x0:x1) = uint8(0);
    end
end

function glyph = glyph5x7(ch)
    switch ch
        case '0'
            rows = ["01110","10001","10011","10101","11001","10001","01110"];
        case '2'
            rows = ["01110","10001","00001","00010","00100","01000","11111"];
        case '5'
            rows = ["11111","10000","11110","00001","00001","10001","01110"];
        case 'G'
            rows = ["01110","10001","10000","10111","10001","10001","01110"];
        case 'L'
            rows = ["10000","10000","10000","10000","10000","10000","11111"];
        case 'e'
            rows = ["00000","00000","01110","10001","11111","10000","01110"];
        case 'l'
            rows = ["00100","00100","00100","00100","00100","00100","00010"];
        case 'v'
            rows = ["00000","00000","10001","10001","10001","01010","00100"];
        case 'a'
            rows = ["00000","00000","01110","00001","01111","10001","01111"];
        case 'r'
            rows = ["00000","00000","10110","11001","10000","10000","10000"];
        case ' '
            rows = ["000","000","000","000","000","000","000"];
        case 'y'
            rows = ["00000","00000","10001","10001","01111","00001","01110"];
        otherwise
            rows = ["00000","00000","00000","00000","00000","00000","00000"];
    end

    glyph = false(numel(rows), strlength(rows(1)));
    for i = 1:numel(rows)
        glyph(i, :) = char(rows(i)) == '1';
    end
end

function write_raw_bin(img, bin_path)
% MATLAB stores matrices in column-major order, so transpose before linearizing.
% This produces row-major bytes: row0, row1, row2, ...
    bytes = reshape(img.', [], 1);
    fid = fopen(bin_path, 'wb');
    assert(fid >= 0, 'Failed to open %s for writing.', bin_path);
    cleaner = onCleanup(@() fclose(fid));
    count = fwrite(fid, bytes, 'uint8');
    assert(count == numel(bytes), 'Incomplete write to %s.', bin_path);
end

function write_coe(img, coe_path)
    bytes = reshape(img.', [], 1);
    fid = fopen(coe_path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', coe_path);
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, 'memory_initialization_radix=16;\n');
    fprintf(fid, 'memory_initialization_vector=\n');
    for k = 1:numel(bytes)
        if k < numel(bytes)
            fprintf(fid, '%02X,\n', bytes(k));
        else
            fprintf(fid, '%02X;\n', bytes(k));
        end
    end
end

function write_meta(width, height, pattern, png_path, preview_path, bin_path, coe_path, meta_path)
    fid = fopen(meta_path, 'w');
    assert(fid >= 0, 'Failed to open %s for writing.', meta_path);
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, 'width=%d\n', width);
    fprintf(fid, 'height=%d\n', height);
    fprintf(fid, 'pixel_bits=8\n');
    fprintf(fid, 'pixel_range=0..255\n');
    fprintf(fid, 'pattern=%s\n', pattern);
    fprintf(fid, 'storage=row-major\n');
    fprintf(fid, 'bytes_per_pixel=1\n');
    fprintf(fid, 'total_bytes=%d\n', width * height);
    fprintf(fid, 'png_path=%s\n', png_path);
    fprintf(fid, 'preview_path=%s\n', preview_path);
    fprintf(fid, 'bin_path=%s\n', bin_path);
    fprintf(fid, 'coe_path=%s\n', coe_path);
    fprintf(fid, 'ddr_offset_formula=addr_base + y * width + x\n');
end
