BOARD_NAME="LinknLink iSG Box SE"
BOARD_VENDOR="linknlink"
BOARDFAMILY="rk35xx"
ARCH="arm64"
KERNEL_TARGET="vendor"
BOOTCONFIG="hinlink_rk3528_defconfig"
BOOT_FDT_FILE="rockchip/rk3528-linknlink-isg-box-se.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOOTFS_TYPE="ext4"
SERIALCON="ttyS2"
PACKAGE_LIST_BOARD="openssh-server network-manager rfkill iw wpasupplicant wireless-regdb bluez"

LINKNLINK_VENDOR_LOADER="${USERPATCHES_PATH}/blobs/rk3528/MiniLoaderAll.bin"
[[ -f "${LINKNLINK_VENDOR_LOADER}" ]] || exit_with_error "LinknLink RK3528 vendor loader is missing" "${LINKNLINK_VENDOR_LOADER}"
UBOOT_HASH_EXTRA="$(sha256sum "${LINKNLINK_VENDOR_LOADER}")"
UBOOT_HASH_EXTRA="${UBOOT_HASH_EXTRA%% *}"

function board_uboot_spl_blobs_postprocess() {
	display_alert "LinknLink RK3528 bootloader" "creating IDB from tested vendor loader" "info"
	run_host_x86_binary_logged "${RKBIN_DIR}/tools/boot_merger" idb -l -o idbloader.img "${LINKNLINK_VENDOR_LOADER}"
}
