# PYNQ-Z2 Software Bring-Up Notes

Relevant files:

- [image_geo_regs.h](/C:/Users/huawei/Desktop/project_codex/sw/include/image_geo_regs.h)
- [image_geo_demo.c](/C:/Users/huawei/Desktop/project_codex/sw/examples/image_geo_demo.c)

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

## Typical integration in Vitis SDK / bare-metal

1. add `sw/include` to the include path
2. include `image_geo_regs.h`
3. copy or call `image_geo_run_example()`
4. replace the hard-coded base addresses with your platform addresses

## Optional next improvements

- replace polling with interrupt-driven completion
- replace hard-coded addresses with `xparameters.h` macros
- add a helper script in `sw/scripts/` to convert floating-point angles into Q16
