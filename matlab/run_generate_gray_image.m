% Directly run this script in MATLAB to regenerate and overwrite outputs.
% Change these parameters as needed before clicking "Run".

width = 640;
height = 480;
pattern = "checkerboard";
out_prefix = "out/test_640x480";

[img, meta] = generate_gray_image(width, height, pattern, out_prefix);

disp('Generation complete.');
disp(meta);
