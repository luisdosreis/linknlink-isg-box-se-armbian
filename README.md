# Armbian for LinknLink iSG Box SE

Armbian userpatches and FactoryTool image tooling for the LinknLink iSG Box SE
(Rockchip RK3528, 4 GB RAM, 64 GB eMMC, SeekWave SWT6621S Wi-Fi/Bluetooth).

Hardware details and tested interfaces are listed in [HARDWARE.md](HARDWARE.md).
Development discussion: https://forum.armbian.com/topic/58945-trying-to-boot-armbian-on-linknlink-isg-box-se/

> [!WARNING]
> This is an unofficial port. Flashing replaces data on the internal eMMC and
> may make the device unbootable. Keep a factory backup and a working Rockchip
> Maskrom/Loader recovery path.

## Image flavors

| Flavor | Build command | Contents |
| --- | --- | --- |
| Server | `./build.sh server` | Headless Armbian server, SSH, NetworkManager, and board drivers |
| Desktop | `./build.sh desktop` | Server base plus the Armbian XFCE mid-tier desktop |

## Technical baseline

- Armbian build framework: current upstream `main`.
- Userspace: Debian Bookworm.
- Kernel: Rockchip RK35xx vendor 6.1.x branch.
- Board definition: `userpatches/config/boards/linknlink-isg-box-se.csc`.
- Device tree: `rk3528-linknlink-isg-box-se.dts`.
- Wi-Fi/Bluetooth: in-build SWT6621S modules and firmware.
- Factory image: current upstream `afptool-rs` with the LinknLink RK3528 legacy
  header compatibility adjustment.

The two Armbian configurations are standard named userpatch configs:

```text
userpatches/config-linknlink-server.conf
userpatches/config-linknlink-desktop.conf
```

## 1. Prepare the build host

Use a Debian or Ubuntu x86-64 host with Docker and at least 50 GB of free disk
space. The tested path uses Docker to isolate Armbian's build dependencies.

```bash
sudo apt update
sudo apt install git rsync ca-certificates curl python3 docker.io cargo rustc util-linux coreutils e2fsprogs 7zip
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Use `p7zip-full` if your distribution does not provide the `7zip` package.
Log out and back in after adding your account to the `docker` group, then check:

```bash
docker version
df -h .
```

## 2. Clone the project

```bash
git clone https://github.com/luisdosreis/linknlink-isg-box-se-armbian.git
cd linknlink-isg-box-se-armbian
```

The wrapper creates a shallow Armbian checkout in `./build` when one does not
already exist. To refresh an existing clean checkout before a release build:

```bash
git -C build pull --ff-only
```

## 3. Build a raw image

Build one flavor:

```bash
./build.sh server
./build.sh desktop
```

Raw images are written to:

```text
build/output/images/
```

To use an Armbian checkout elsewhere:

```bash
./build.sh server /path/to/armbian-build
```

The same userpatches can be used directly with Armbian's community workflow:

```bash
git clone --depth=1 https://github.com/armbian/build.git armbian-build
./install-userpatches.sh ./armbian-build
cd armbian-build
./compile.sh linknlink-server build
```

Replace `linknlink-server` with `linknlink-desktop` for the desktop
configuration.

`install-userpatches.sh` synchronizes this project's complete `userpatches/`
tree with `--delete`; use a dedicated Armbian checkout because unrelated
userpatch files in that destination are removed.

## 4. Repack for Rockchip FactoryTool

The raw Armbian image cannot be flashed directly with FactoryTool. Repack the
specific image produced in the previous step:

```bash
image-tools/repack-afptool-rs.sh build/output/images/<raw-image>.img
```

The repacker fetches and builds current upstream `afptool-rs`, injects
`image-tools/assets/rk3528/MiniLoaderAll.bin`, and creates:

```text
output/factory/apftool-rs-patched/<raw-image>-factorytool.img
```

Normal builds use `FACTORY_AFP_CHIP=RK3528`, which writes the legacy-compatible
header required by this device. `RK3528_RAW` is available only for testing the
upstream modern encoding.

## 5. Package a release

GitHub release assets must be smaller than 2 GiB. Keep the raw image locally
for FactoryTool and publish an XZ-compressed copy:

```bash
xz -T0 -6 -k output/factory/apftool-rs-patched/<factorytool-image>.img
sha256sum output/factory/apftool-rs-patched/<factorytool-image>.img.xz \
  > output/factory/apftool-rs-patched/<factorytool-image>.img.xz.sha256
```

Upload the `.img.xz` and `.img.xz.sha256` files as GitHub release assets. Users
must decompress the image before opening it in Rockchip FactoryTool:

```bash
xz -dk <factorytool-image>.img.xz
```

## 6. Flash the eMMC

Put the box into Rockchip Loader or Maskrom mode and verify detection:

Rockchip's proprietary `upgrade_tool` is not committed to this repository.
Keep local copies of `upgrade_tool` and its `config.ini` under the ignored
`local-scripts/` directory, or set `UPGRADE_TOOL` to another installation:

```bash
export UPGRADE_TOOL="$PWD/local-scripts/upgrade_tool"
sudo "$UPGRADE_TOOL" ld
```

Flash the repacked image:

```bash
sudo "$UPGRADE_TOOL" uf output/factory/apftool-rs-patched/<factorytool-image>.img
```

Power-cycle the box after flashing. On first boot, connect Ethernet, find the
DHCP address, connect over SSH as `root`, and complete Armbian's first-login
password and user creation.

## Optional Home Assistant installation

Home Assistant is not an image flavor and is not included in this repository.
After completing Armbian first login on either the server or desktop image,
install the independent `armbian-ha-app` project:

```bash
git clone https://github.com/luisdosreis/armbian-ha-app.git
cd armbian-ha-app
sudo ./install.sh
```

Installation, management, updates and backup instructions are maintained in
the [`armbian-ha-app` repository](https://github.com/luisdosreis/armbian-ha-app).

## Clean generated files

Preview and remove local build products:

```bash
./clean.sh --dry-run
./clean.sh
```

If a container created root-owned files under `build/`, use
`sudo ./clean.sh`. Cleanup removes only this repository's generated `build/`,
`.cache/`, `output/`, firmware backup, and image dump directories.

## Repository layout

```text
userpatches/             Armbian board, configs, patches, extensions and overlay
image-tools/             FactoryTool repacker and RK3528 loader asset
build.sh                 Flavor-aware Armbian build wrapper
install-userpatches.sh   Copy userpatches into any Armbian checkout
clean.sh                 Remove generated local build data
```

Vendor firmware and the RK3528 loader are binary artifacts required by the
tested hardware path. SeekWave driver sources retain their upstream licensing
notices.
