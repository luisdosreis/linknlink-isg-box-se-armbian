# Armbian for LinknLink iSG Box SE

Build and flash Armbian images for the LinknLink iSG Box SE: Rockchip RK3528,
4 GB RAM, 64 GB eMMC, and SeekWave SWT6621S Wi-Fi/Bluetooth.

See [HARDWARE.md](HARDWARE.md) for tested hardware and interface details.
Development discussion is available on the
[Armbian forum](https://forum.armbian.com/topic/58945-trying-to-boot-armbian-on-linknlink-isg-box-se/).

> [!WARNING]
> This is an unofficial port. Flashing overwrites the internal eMMC and can
> make the box unbootable. Back up important data and keep a working Rockchip
> Loader/Maskrom recovery path.

## Image flavors

| Flavor | Build command | Description |
| --- | --- | --- |
| Server | `./build.sh server` | Headless Armbian with SSH, NetworkManager, and board drivers |
| Desktop | `./build.sh desktop` | Server base with the Armbian XFCE mid-tier desktop |

Both flavors use Debian Bookworm, the Rockchip vendor 6.1 kernel, and the same
board, Wi-Fi, Bluetooth, Ethernet, audio, HDMI, USB, and eMMC support.

## 1. Prepare the build host

Use a Debian or Ubuntu x86-64 host with Docker and at least 50 GB of free disk
space:

```bash
sudo apt update
sudo apt install git rsync ca-certificates curl docker.io cargo rustc \
  util-linux coreutils e2fsprogs 7zip libudev-dev libusb-1.0-0-dev \
  dh-autoreconf pkg-config
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Use `p7zip-full` instead of `7zip` if your distribution does not provide that
package. Log out and back in after adding your account to the Docker group,
then verify the host:

```bash
docker version
df -h .
```

## 2. Clone the repository

```bash
git clone https://github.com/luisdosreis/linknlink-isg-box-se-armbian.git
cd linknlink-isg-box-se-armbian
```

All remaining commands run from this repository directory.

## 3. Build an image

Build one flavor:

```bash
./build.sh server
```

or:

```bash
./build.sh desktop
```

The first build automatically creates a shallow Armbian checkout under
`build/`. Images are written to `build/output/images/`.

List the generated image:

```bash
ls -lh build/output/images/*.img
```

In the commands below, replace `<image-file>.img` with the filename displayed
by this command. Verify it before flashing:

```bash
cd build/output/images
sha256sum --check "<image-file>.img.sha"
cd ../../..
```

## 4. Flash with rkdeveloptool (recommended)

[`rkdeveloptool`](https://github.com/rockchip-linux/rkdeveloptool) is the
open-source Linux flashing tool. The Loader-mode workflow below has been
tested through a successful Armbian boot. Build and install it once:

```bash
mkdir -p .cache/tools
git clone --depth=1 https://github.com/rockchip-linux/rkdeveloptool.git \
  .cache/tools/rkdeveloptool
cd .cache/tools/rkdeveloptool
./autogen.sh
./configure
make
sudo install -m 0755 rkdeveloptool /usr/local/bin/rkdeveloptool
cd ../../..
```

Put the box into Rockchip USB flashing mode and check detection:

```bash
sudo rkdeveloptool ld
```

Continue only if the output reports `Loader`. If it reports `Maskrom`, use the
tested Upgrade Tool method in the next section.

Write the raw image from sector zero, then reboot the box:

```bash
sudo rkdeveloptool wl 0 "build/output/images/<image-file>.img"
sudo rkdeveloptool rd
```

## 5. Flash with Rockchip Upgrade Tool (alternative)

Rockchip's proprietary Linux `upgrade_tool` cannot use the raw Armbian image
with its `UF` command. First create and verify an RKFW upgrade image from the
raw image:

```bash
image-tools/repack-afptool-rs.sh "build/output/images/<image-file>.img"
ls -lh output/factory/afptool-rs/*-factorytool.img
```

The output filename is the raw image name with `-factorytool` added. Use the
same `<image-file>` name below, then verify it:

```bash
cd output/factory/afptool-rs
sha256sum --check "<image-file>-factorytool.img.sha256"
cd ../../..
```

Download and configure the proprietary tool by following the
[Linux Upgrade Tool distribution instructions](https://github.com/vicharak-in/Linux_Upgrade_Tool).
Version 2.17 has been tested from Maskrom mode through a successful Armbian
first boot.

Print the absolute image path from this repository:

```bash
realpath "output/factory/afptool-rs/<image-file>-factorytool.img"
```

Then enter the downloaded Linux Upgrade Tool directory. Following its
documented usage, detect the box and flash using the absolute path printed
above:

```bash
cd "<linux-upgrade-tool-directory>"
sudo ./upgrade_tool ld
sudo ./upgrade_tool uf "<absolute-path-to-upgrade-image>"
```

## 6. First boot

Power-cycle the box if the flashing tool does not reboot it. Connect Ethernet,
find the assigned DHCP address, then connect as `root` and complete Armbian's
first-login password and user setup:

```bash
ssh "root@<box-ip-address>"
```

## Optional Home Assistant installation

Home Assistant is not an image flavor. After completing the first boot on
either image, install the independent
[`armbian-ha-app`](https://github.com/luisdosreis/armbian-ha-app) project:

```bash
git clone https://github.com/luisdosreis/armbian-ha-app.git
cd armbian-ha-app
sudo ./install.sh
```

## Update and rebuild

Run these commands from the repository directory.

Update this project:

```bash
git pull --ff-only
```

Update the existing Armbian build framework checkout. Skip this step when
`build/` does not exist; the first `./build.sh` run creates it automatically:

```bash
git -C build pull --ff-only
```

Rebuild the Server image:

```bash
./build.sh server
```

Or rebuild the Desktop image:

```bash
./build.sh desktop
```

## Clean generated files

Preview cleanup first, then remove generated build data:

```bash
./clean.sh --dry-run
./clean.sh
```

If Docker created root-owned files, run `sudo ./clean.sh`. Cleanup removes
generated `build/`, `.cache/`, `output/`, firmware backups, and image dump
directories; it does not remove repository source files.
