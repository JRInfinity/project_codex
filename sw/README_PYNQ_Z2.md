# PYNQ-Z2 Software Bring-Up Notes

Relevant files:

- [image_geo_regs.h](/C:/Users/huawei/Desktop/project_codex/sw/include/image_geo_regs.h)
- [image_geo_demo.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_demo.c)
- [image_geo_bringup.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_bringup.c)
- [image_geo_sd_bringup.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_sd_bringup.c)
- [image_geo_sd_case_bringup.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_sd_case_bringup.c)

## What to replace before running

Update these items in `image_geo_demo.c`:

- `IMAGE_GEO_BASEADDR`
  Replace with the AXI-Lite base address assigned in Vivado Address Editor or
  the matching `XPAR_*` macro from `xparameters.h`.

- `SRC_BASEADDR`
  Replace with the DDR address of the input image buffer.

- `DST_BASEADDR`
  Replace with the DDR address of the output image buffer.

## Current demo flow

The demo runs two cases:

1. identity scale `7200x7200 -> 600x600`
2. `90 degree` rotation with the same source/destination sizes

Both cases:

- clear sticky status
- enable tile-cache prefetch
- flush CPU D-cache for source/destination DDR buffers
- program frame registers
- start the IP
- poll until done or error
- invalidate CPU D-cache for the destination buffer
- print cache statistics

## Recommended first bring-up flow

Before running the larger demo, start with:

- [image_geo_bringup.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_bringup.c)

This version is intentionally minimal:

- AXI-Lite base address is set to `0x40000000`
- source DDR buffer is set to `0x10000000`
- destination DDR buffer is set to `0x12000000`
- input/output image size is `64x64`
- transform is identity (`sin=0`, `cos=1`)

Expected first-pass success criteria:

- software can read/write the IP register bank
- the IP asserts `DONE`
- the IP does not assert `ERROR`
- the destination buffer matches the source buffer exactly

If this minimal test passes, then move on to:

1. larger source/destination sizes
2. `90 degree` rotation
3. loading a real image buffer from PS-side software

## MATLAB .bin import flow

If you want the source image to come from MATLAB instead of being generated in C,
use:

- [generate_gray_image.m](/C:/Users/huawei/Desktop/project_codex/matlab/generate_gray_image.m)
- [image_geo_sd_bringup.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_sd_bringup.c)
- [export_image_geo_case.m](/C:/Users/huawei/Desktop/project_codex/matlab/export_image_geo_case.m)
- [image_geo_sd_case_bringup.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_sd_case_bringup.c)

Recommended flow:

1. In MATLAB, generate the raw source file:
   ```matlab
   [img, meta] = generate_gray_image(640, 480, "horizontal_gradient", "out/test_640x480");
   ```
2. Copy `matlab/out/test_640x480.bin` to the SD card root directory.
3. In Vitis, build the application from `image_geo_sd_bringup.c`.
4. Run it on the board.
5. After completion, read `out_640x480.bin` back from the SD card for inspection.

Important consistency rules:

- the `.bin` file must be row-major
- 1 pixel must equal 1 byte
- input file size must equal `SRC_STRIDE * SRC_H`
- `SRC_W`, `SRC_H`, `DST_W`, `DST_H`, `SRC_STRIDE`, `DST_STRIDE`
  in C must match the image you generated and the case you want the IP to run

For the checked-in example:

- input path  = `0:/test_640x480.bin`
- output path = `0:/out_640x480.bin`
- source size = `640x480`
- destination size = `640x480`
- transform   = identity

To use this flow in bare-metal, ensure the application links the FatFs support
used by `ff.h`.

## Recommended MATLAB + case-config flow

If you also want MATLAB to export the run parameters used by software, prefer:

- [run_generate_gray_image.m](/C:/Users/huawei/Desktop/project_codex/matlab/run_generate_gray_image.m)
- [export_image_geo_case.m](/C:/Users/huawei/Desktop/project_codex/matlab/export_image_geo_case.m)
- [image_geo_sd_case_bringup.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_sd_case_bringup.c)

This flow generates:

- `test_640x480.bin`
- `test_640x480_meta.txt`
- `test_640x480_case.txt`

The `_case.txt` file contains:

- input file name
- output file name
- source width/height/stride
- destination width/height/stride
- `rot_sin_q16`
- `rot_cos_q16`
- prefetch enable flag

Typical use:

1. Run `run_generate_gray_image.m` in MATLAB.
2. Copy `test_640x480.bin` and `test_640x480_case.txt` to the SD card root.
3. In Vitis, use [image_geo_sd_case_bringup.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_sd_case_bringup.c) as `main.c`.
4. Run on hardware.
5. Read back the output `.bin` named in the case file.

Default checked-in case file path in software:

- `0:/test_640x480_case.txt`

## Typical integration in Vitis SDK / bare-metal

1. add `sw/include` to the include path
2. include `image_geo_regs.h`
3. copy or call `image_geo_run_example()`
4. replace the hard-coded base addresses with your platform addresses

## Optional next improvements

- replace polling with interrupt-driven completion
- replace hard-coded addresses with `xparameters.h` macros
- add a helper script in `sw/scripts/` to convert floating-point angles into Q16
