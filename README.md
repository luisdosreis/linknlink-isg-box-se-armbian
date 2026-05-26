# Armbian Linux Unofficial for LinknLink iSG Box SE

Version: `v26.05 Rolling`
Kernel: `6.1.115-vendor-rk35xx`

Armbian build overlay for the LinknLink iSG Box SE - RK3528.

Discussion and support here:
https://forum.armbian.com/topic/58945-trying-to-boot-armbian-on-linknlink-isg-box-se/

What you get:

* A minimal Armbian server image with board's device tree
* Wi-Fi and Bluetooth necessary blob files
* Repack raw Armbian image as Rockchip FactoryTool image
* Flashe to eMMC using Rockchip USB tools

## Disclaimer

Use this at your own risk. Flashing unofficial firmware can brick hardware,
erase data, break vendor recovery paths, and void warranty.
I will not be held responsible for damaged devices, 
or any other consequence of using this content.

## What This Image Includes

- Armbian build framework from `https://github.com/armbian/build`.
- Debian Bookworm userland by default: `RELEASE=bookworm`.
- Rockchip RK35xx vendor kernel branch: `BRANCH=vendor`.
- Validated Linux kernel family: RK35xx vendor 6.1.x, tested on
  `6.1.115-vendor-rk35xx`.
- Board DTS: `rk3528-linknlink-isg-box-se.dts`.
- NetworkManager with DHCP Ethernet on `eth0`.
- SSH server enabled for first login.
- Wi-Fi userspace: `iw`, `wpasupplicant`, `network-manager`.
- SeekWave SWT6621S SDIO Wi-Fi/Bluetooth driver build extension.
- Rockchip FactoryTool repack support using a custom patched `apftool-rs`.

## Hardware

Board hardware mapping and tested external USB Zigbee adapters are documented in
[HARDWARE.md](HARDWARE.md).

## Sources

The build is based on these upstream projects:

- Armbian build: `https://github.com/armbian/build`
- `apftool-rs`: `https://github.com/suyulin/apftool-rs`

## Included Blobs and Runtime Artifacts

- `resources/blobs/rk3528/MiniLoaderAll.bin`: RK3528 loader used by the
  FactoryTool image because the generic loader did not initialize this box DDR
  reliably.
- `resources/firmware/seekwave-swt6621s/`: SeekWave SWT6621S firmware and NV
  files.
- `resources/drivers/seekwave-swt6621s-recon/`: reconstructed SeekWave
  SWT6621S driver tree used to build `skw_sdio_lite.ko`, `swt6621s_wifi.ko`, and `skwbt.ko`.

## Prerequisites

A Debian or Ubuntu Linux build host with Docker enabled.

Building has been tested on Debian GNU/Linux 13.4 `trixie` x86_64 with Linux `6.12.85+deb13-amd64`.

Install the required host tools:

```bash
sudo apt update
sudo apt install git rsync ca-certificates curl python3 docker.io cargo rustc util-linux coreutils e2fsprogs 7zip
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

If your Ubuntu release does not provide the `7zip` package, install
`p7zip-full` instead. The repacker needs the `7z` command.

Log out and back in after adding your user to the Docker group.

Clone this repository:

```bash
git clone <repository-url> linknlink-isg-box-se-armbian
cd linknlink-isg-box-se-armbian
```

## Build

Build the raw Armbian image:

```bash
./build.sh
```

Default build settings:

```text
BOARD=linknlink-isg-box-se
BRANCH=vendor
RELEASE=bookworm
BUILD_DESKTOP=no
KERNEL_CONFIGURE=no
```

Useful overrides:

```bash
RELEASE=bookworm ./build.sh
BUILD_MINIMAL=yes ./build.sh
```

The raw image is written under:

```text
build/output/images/
```

## Repack

The box is flashed through Rockchip firmware format, not by writing the raw
Armbian `.img` directly to removable media.

Repack the latest raw image:

```bash
image-tools/repack-afptool-rs.sh
```

Or specify an image:

```bash
image-tools/repack-afptool-rs.sh build/output/images/<raw-image>.img
```

Output:

```text
output/factory/apftool-rs-patched/<raw-image>-factorytool.img
```

The repacker:

- clones/builds `apftool-rs` into `.cache/repack-afptool-rs/`;
- applies local RK3528 compatibility edits;
- extracts `uboot`, `boot`, and `rootfs` from the raw image;
- injects `resources/blobs/rk3528/MiniLoaderAll.bin`;
- writes Rockchip parameter and package metadata;
- packs RKAF and RKFW images.

## Flash

Connect the box in Rockchip Loader or Maskrom mode.

Check that Rockchip tooling sees it:

```bash
export UPGRADE_TOOL=/path/to/upgrade_tool
sudo "$UPGRADE_TOOL" ld
```

Flash:

```bash
sudo "$UPGRADE_TOOL" uf output/factory/apftool-rs-patched/<raw-image>-factorytool.img
```

Power-cycle the box after the flash completes.

## Alternative Flashing Tools

- Rockchip `upgrade_tool`: proprietary flashing utility used to flash the final
  FactoryTool image.
- `imgRePackerRK`: closed-source alternative repacker, not part of the
  supported flow here.

## Optional Cleanup

Cleanup is not part of flashing a finished image. Use it only when you want to
remove generated local build and repack artifacts before starting a fresh build.

Preview cleanup:

```bash
./clean.sh --dry-run
```

Remove generated artifacts:

```bash
./clean.sh
```

If Docker or Armbian left root-owned files in `build/`, run:

```bash
sudo ./clean.sh
```

Cleanup removes generated local state only: `.cache/`, `output/`, `build/`,
`.firmware-backups/`, and local `*.img.dump/` directories.

## First Boot

Recommended first boot path:

1. Connect Ethernet to a DHCP network.
2. Power on the box.
3. Find the DHCP address from your router or DHCP server.
4. SSH to the box as `root`; the default password is `1234`.
5. Complete Armbian first-login setup and change credentials immediately.

## Future Ideas

- Add an optional image build profile with Home Assistant preinstalled and ready
  to run.
- Add an optional first-boot flow that installs and configures Home Assistant
  after network setup.

<a href="https://www.buymeacoffee.com/luismarcalreis" target="_blank" title="buymeacoffee">
  <img src="https://iili.io/JoQcIJS.md.png"  alt="buymeacoffee-black-badge" style="width: 104px;">
</a>
