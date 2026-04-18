% Directly run this script in MATLAB to regenerate a source image plus
% a Vitis-friendly case config file.

src_w = 640;
src_h = 480;
dst_w = 640;
dst_h = 480;
angle_deg = 0;
pattern = "checkerboard";
out_prefix = "out/test_640x480";

cfg = export_image_geo_case(src_w, src_h, pattern, out_prefix, dst_w, dst_h, angle_deg);

disp('Generation complete.');
disp(cfg);
