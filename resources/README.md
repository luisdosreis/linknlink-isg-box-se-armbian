# Resources

This directory contains board-specific build inputs used by `build.sh`,
`install-userpatches.sh`, and `image-tools/repack-afptool-rs.sh`.

## Boot Blob

- `blobs/rk3528/MiniLoaderAll.bin`

This RK3528 loader is injected into the Rockchip FactoryTool image by
`image-tools/repack-afptool-rs.sh`. It is required for this board because the
generic loader path did not reliably initialize DDR on the tested iSG Box SE
hardware.

## SeekWave Firmware

- `firmware/seekwave-swt6621s/`

Firmware and NV files for the SeekWave SWT6621S SDIO Wi-Fi/Bluetooth combo.
The bundled set is limited to the files used by the current SV6160LITE SDIO
board path:

- `SWT6621S_DRAM_SDIO.bin`
- `SWT6621S_IRAM_SDIO.bin`
- `SWT6621S_NV_SDIO.bin`
- `sv6160lite.nvbin`
- `SWT6621S_SEEKWAVE_R*.bin` calibration variants selected by chip efuse data

The build extension installs these files under `/lib/firmware` and
`/lib/firmware/seekwave-swt6621s` in the generated image because the vendor
drivers request both root-level and namespaced firmware paths.

## SeekWave Driver Source

- `drivers/seekwave-swt6621s-recon/sources/seekwave-swt6621s/`

Reconstructed driver tree used by `userpatches/extensions/isg-seekwave-driver.sh`
to build:

- `skw_sdio_lite.ko`
- `swt6621s_wifi.ko`
- `skwbt.ko`
