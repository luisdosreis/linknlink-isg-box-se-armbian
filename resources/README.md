# Resources

This directory contains the board-specific resources that are copied into the
Armbian build tree by `build.sh` and
`install-userpatches.sh`.

## Boot Blob

- `blobs/rk3528/MiniLoaderAll.bin`

This RK3528 loader is injected into the Rockchip FactoryTool image by
`image-tools/repack-afptool-rs.sh`. It is required for this board because the generic
loader path did not reliably initialize DDR on the tested iSG Box SE hardware.

Treat this as a vendor/Rockchip binary blob. Verify redistribution rights before
publishing binary release artifacts.

## SeekWave Firmware

- `firmware/seekwave-swt6621s/`

Firmware and NV files for the SeekWave SWT6621S SDIO Wi-Fi/Bluetooth combo.
The bundled set is limited to the files requested by the current SV6160LITE
SDIO board path:

- `SWT6621S_DRAM_SDIO.bin`
- `SWT6621S_IRAM_SDIO.bin`
- `SWT6621S_NV_SDIO.bin`
- `sv6160lite.nvbin`
- `SWT6621S_SEEKWAVE_R*.bin` calibration variants selected by chip efuse data

The build extension installs these files under `/lib/firmware` and
`/lib/firmware/seekwave-swt6621s` in the generated image because the vendor
drivers request both root-level and namespaced firmware paths.

Treat these files as vendor firmware blobs.

## SeekWave Driver Source

- `drivers/seekwave-swt6621s-recon/sources/seekwave-swt6621s/`

Reconstructed driver tree used by `userpatches/extensions/isg-seekwave-driver.sh`
to build:

- `skw_sdio_lite.ko`
- `swt6621s_wifi.ko`
- `skwbt.ko`

Source files carry SeekWave copyright notices and GPL/GPL-2.0 style kernel
module licensing. No official public upstream for this exact board driver tree
is tracked in this repository.

Review licensing and redistribution obligations before publishing binary module
artifacts.
