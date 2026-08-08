#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="$(basename "$0" .sh)"
WORK_DIR="${REPACK_WORK_DIR:-$REPO_DIR/.cache/$SCRIPT_NAME}"
AFPTOOL_BIN="${AFPTOOL_BIN:-$WORK_DIR/bin/afptool-rs}"
APFTOOL_RS_URL="${APFTOOL_RS_URL:-https://github.com/suyulin/apftool-rs.git}"
APFTOOL_RS_REF="${APFTOOL_RS_REF:-main}"
FACTORY_PACKER="afptool-rs"
FACTORY_OUTPUT_DIR="${FACTORY_OUTPUT_DIR:-$REPO_DIR/output/factory/apftool-rs-patched}"
FACTORY_WORK_DIR="${FACTORY_WORK_DIR:-$WORK_DIR/tmp}"
FACTORY_AFP_CHIP="${FACTORY_AFP_CHIP:-RK3528}"
FACTORY_BOOTLOADER_BLOB="${FACTORY_BOOTLOADER_BLOB:-}"
FACTORY_UBOOT_IMAGE="${FACTORY_UBOOT_IMAGE:-}"
FACTORY_BOOT_DTB_PATH="${FACTORY_BOOT_DTB_PATH:-}"
FACTORY_MACHINE_MODEL="${FACTORY_MACHINE_MODEL:-LinknLink-iSG-Box-SE}"
FACTORY_MACHINE_ID="${FACTORY_MACHINE_ID:-ISGSE}"
FACTORY_MANUFACTURER="${FACTORY_MANUFACTURER:-LinknLink}"
FACTORY_FW_VERSION="${FACTORY_FW_VERSION:-12.0.0}"
FACTORY_FW_CODE="${FACTORY_FW_CODE:-0x02000000}"
FACTORY_FW_TIMESTAMP="${FACTORY_FW_TIMESTAMP:-}"
FACTORY_BOOT_FDTFILE="${FACTORY_BOOT_FDTFILE:-rockchip/rk3528-linknlink-isg-box-se.dtb}"
FACTORY_BOOT_OVERLAY_PREFIX="${FACTORY_BOOT_OVERLAY_PREFIX:-rk35xx}"
FACTORY_BOOT_START_SECTORS="${FACTORY_BOOT_START_SECTORS:-0x8800}"
FACTORY_ROOTFS_START_SECTORS="${FACTORY_ROOTFS_START_SECTORS:-0x89000}"
FACTORY_ROOTFS_PARAMETER_SECTORS="${FACTORY_ROOTFS_PARAMETER_SECTORS:-0x39B4FBF}"
FACTORY_SOURCE_DUMP_DIR="${FACTORY_SOURCE_DUMP_DIR:-}"
FACTORY_KEEP_DUMP="${FACTORY_KEEP_DUMP:-no}"

log_section() {
  printf '\n==> %s\n' "$1"
}

log_item() {
  printf '    %-18s %s\n' "$1:" "$2"
}

log_warn() {
  printf 'WARNING: %s\n' "$1" >&2
}

usage() {
  cat <<'EOF'
usage: image-tools/repack-afptool-rs.sh [options] [raw-image-path]
       image-tools/repack-afptool-rs.sh [options] [armbian-build-dir]
       image-tools/repack-afptool-rs.sh [options] [armbian-build-dir] [raw-image-path]

Build a Rockchip FactoryTool image from an existing raw Armbian image using
this repo's patched afptool-rs flow.

If raw-image-path is omitted, the latest .img under
<armbian-build-dir>/output/images/ is used. If a single positional argument is
a file, it is treated as raw-image-path. If it is a directory, it is treated as
armbian-build-dir.

Options:
  --help, -h            Show this help

Environment:
  REPACK_WORK_DIR       Override the default .cache/repack-afptool-rs/ path
  AFPTOOL_BIN           Write the rebuilt afptool-rs binary to this path
  APFTOOL_RS_URL         afptool-rs Git repository (default: upstream)
  APFTOOL_RS_REF         afptool-rs branch or tag to build (default: main)
EOF
}

ARMBIAN_BUILD_DIR=""
RAW_IMAGE_PATH=""
POSITIONAL_ARGS=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      ;;
  esac
  shift
done

case "${#POSITIONAL_ARGS[@]}" in
  0)
    ;;
  1)
    if [[ -f "${POSITIONAL_ARGS[0]}" ]]; then
      RAW_IMAGE_PATH="${POSITIONAL_ARGS[0]}"
    elif [[ -d "${POSITIONAL_ARGS[0]}" ]]; then
      ARMBIAN_BUILD_DIR="${POSITIONAL_ARGS[0]}"
    elif [[ "${POSITIONAL_ARGS[0]}" == *.img ]]; then
      RAW_IMAGE_PATH="${POSITIONAL_ARGS[0]}"
    else
      ARMBIAN_BUILD_DIR="${POSITIONAL_ARGS[0]}"
    fi
    ;;
  2)
    ARMBIAN_BUILD_DIR="${POSITIONAL_ARGS[0]}"
    RAW_IMAGE_PATH="${POSITIONAL_ARGS[1]}"
    ;;
  *)
    echo "Unexpected extra argument: ${POSITIONAL_ARGS[2]}" >&2
    usage >&2
    exit 1
    ;;
esac

ARMBIAN_BUILD_DIR="${ARMBIAN_BUILD_DIR:-$REPO_DIR/build}"
mkdir -p "$WORK_DIR/bin" "$WORK_DIR/tmp"

rm_args=(-rf)
if rm --help 2>/dev/null | grep -q -- '--one-file-system'; then
  rm_args+=(--one-file-system)
fi

safe_rm_rf() {
  local path mounts
  path="$1"

  [[ -e "$path" ]] || return 0

  mounts="$(findmnt -R -rn -o TARGET "$path" 2>/dev/null || true)"
  if [[ -n "$mounts" ]]; then
    echo "Refusing to remove mounted filesystem(s) under: $path" >&2
    echo "$mounts" >&2
    echo "Unmount those paths first, then rerun repack." >&2
    return 1
  fi

  rm "${rm_args[@]}" "$path"
}

cleanup_path() {
  local path label size
  path="$1"
  label="$2"

  [[ -e "$path" ]] || return 0

  size="$(du -shx "$path" 2>/dev/null | awk '{print $1}')"
  : "${size:=unknown-size}"

  log_item "remove ${label}" "$path ($size)"
  safe_rm_rf "$path"
}

build_patched_afptool() {
  local tool_work_dir src_dir out_bin
  tool_work_dir="$WORK_DIR/apftool-rs"
  src_dir="$tool_work_dir/src"
  out_bin="$AFPTOOL_BIN"

  log_section "Build current afptool-rs"
  log_item "output" "$out_bin"
  log_item "work dir" "$WORK_DIR"
  log_item "source" "$APFTOOL_RS_URL"
  log_item "ref" "$APFTOOL_RS_REF"

  mkdir -p "$tool_work_dir" "$(dirname "$out_bin")"

  if [[ -n "${APFTOOL_RS_SRC:-}" ]]; then
    safe_rm_rf "$src_dir"
    mkdir -p "$src_dir"
    rsync -a --delete "$APFTOOL_RS_SRC/" "$src_dir/"
  else
    safe_rm_rf "$src_dir"
    git clone --depth=1 --branch "$APFTOOL_RS_REF" "$APFTOOL_RS_URL" "$src_dir"
  fi

  if ! grep -q 'RK3528_LEGACY' "$src_dir/src/pack.rs"; then
    python3 - <<'PY' "$src_dir"
from pathlib import Path
import sys

src_dir = Path(sys.argv[1])

main_rs = src_dir / "src/main.rs"
pack_rs = src_dir / "src/pack.rs"
unpack_rs = src_dir / "src/unpack.rs"

main_text = main_rs.read_text()
main_text = main_text.replace(
    "Chip family (e.g., RK29XX, RK30XX, RK31XX, RK32XX, RK3368, RK3326, RK3562, RK3566, PX30)",
    "Chip family (e.g., RK29XX, RK30XX, RK31XX, RK32XX, RK3368, RK3326, RK3528, RK3562, RK3566, PX30)",
)
main_rs.write_text(main_text)

pack_text = pack_rs.read_text()
old = '        "RK3566" | "RK3568" => Ok(0x38),\n        "RK3528" => Ok(0x39),'
new = (
    '        // LinknLink RK3528 devices expect the legacy-compatible support-type byte 0x38.\n'
    '        // Keep an explicit raw override for testing newer encodings.\n'
    '        "RK3528" | "RK3528_LEGACY" => Ok(0x38),\n'
    '        "RK3528_RAW" => Ok(0x39),\n'
    '        "RK3566" | "RK3568" => Ok(0x38),'
)
if old not in pack_text:
    raise SystemExit("expected RK3528 mapping not found in src/pack.rs")
pack_rs.write_text(pack_text.replace(old, new))

unpack_text = unpack_rs.read_text()
old = '        0x38 => chip = Some("RK3566/RK3568"),\n        0x39 => chip = Some("RK3528"),'
new = '        0x38 => chip = Some("RK3528 legacy / RK3566 / RK3568"),\n        0x39 => chip = Some("RK3528 raw"),'
if old not in unpack_text:
    raise SystemExit("expected RK3528 unpack mapping not found in src/unpack.rs")
unpack_rs.write_text(unpack_text.replace(old, new))
PY
  fi

  cargo build --quiet --release --manifest-path "$src_dir/Cargo.toml"
  install -Dm755 "$src_dir/target/release/afptool-rs" "$out_bin"

  log_item "revision" "$(git -C "$src_dir" rev-parse --short HEAD 2>/dev/null || echo local-source)"
  log_item "built binary" "$out_bin"
}

build_patched_afptool

find_latest_image() {
  find "$ARMBIAN_BUILD_DIR/output/images" -maxdepth 1 -type f -name '*.img' | sort | tail -n 1
}

cleanup_previous_factory_outputs() {
  local previous_output
  local -a previous_outputs=()

  mkdir -p "$FACTORY_OUTPUT_DIR"

  log_section "Clean previous FactoryTool images"
  mapfile -d '' -t previous_outputs < <(find "$FACTORY_OUTPUT_DIR" -maxdepth 1 \( \
    -type f -name '*-factorytool.img' -o \
    -type d -name '*-factorytool.img.dump' \
  \) -print0)

  if [[ "${#previous_outputs[@]}" -eq 0 ]]; then
    log_item "status" "none found"
    return 0
  fi

  for previous_output in "${previous_outputs[@]}"; do
    cleanup_path "$previous_output" "factory output"
  done
}

cleanup_factory_work_dir() {
  local tmp_dir
  local -a tmp_dirs=()

  mkdir -p "$FACTORY_WORK_DIR"

  log_section "Clean repack temporary work dirs"
  mapfile -d '' -t tmp_dirs < <(find "$FACTORY_WORK_DIR" -mindepth 1 -maxdepth 1 \( \
    -type d -name 'afptool-rs.*' -o \
    -type d -name 'boot-img.*' \
  \) -print0)

  if [[ "${#tmp_dirs[@]}" -eq 0 ]]; then
    log_item "status" "none found"
    return 0
  fi

  for tmp_dir in "${tmp_dirs[@]}"; do
    cleanup_path "$tmp_dir" "temporary work dir"
  done
}

resolve_bootloader_blob() {
  local candidate

  if [[ -n "${FACTORY_BOOTLOADER_BLOB}" ]]; then
    [[ -f "${FACTORY_BOOTLOADER_BLOB}" ]] || {
      echo "Rockchip bootloader blob not found: ${FACTORY_BOOTLOADER_BLOB}" >&2
      return 1
    }
    echo "${FACTORY_BOOTLOADER_BLOB}"
    return 0
  fi

  if [[ -n "$FACTORY_SOURCE_DUMP_DIR" && -f "$FACTORY_SOURCE_DUMP_DIR/Image/MiniLoaderAll.bin" ]]; then
    echo "$FACTORY_SOURCE_DUMP_DIR/Image/MiniLoaderAll.bin"
    return 0
  fi

  for candidate in \
    "$REPO_DIR/resources/blobs/rk3528/MiniLoaderAll.bin" \
    "$REPO_DIR/MiniLoaderAll.bin" \
    "$ARMBIAN_BUILD_DIR/cache/sources/rkbin-tools/rk35/rk3528_spl_loader_v1.07.104.bin"
  do
    [[ -f "$candidate" ]] || continue
    echo "$candidate"
    return 0
  done

  echo "Set FACTORY_BOOTLOADER_BLOB or add resources/blobs/rk3528/MiniLoaderAll.bin." >&2
  return 1
}

resolve_u_boot_image() {
  if [[ -n "${FACTORY_UBOOT_IMAGE}" ]]; then
    [[ -f "${FACTORY_UBOOT_IMAGE}" ]] || {
      echo "U-Boot image not found: ${FACTORY_UBOOT_IMAGE}" >&2
      return 1
    }
    echo "${FACTORY_UBOOT_IMAGE}"
    return 0
  fi

  return 1
}

resolve_boot_dtb_path() {
  if [[ -n "${FACTORY_BOOT_DTB_PATH}" ]]; then
    [[ -f "${FACTORY_BOOT_DTB_PATH}" ]] || {
      echo "Boot DTB not found: ${FACTORY_BOOT_DTB_PATH}" >&2
      return 1
    }
    echo "${FACTORY_BOOT_DTB_PATH}"
    return 0
  fi

  return 1
}

align_to_0x800_blocks() {
  local size
  size="$1"
  echo $(( (size + 0x7ff) / 0x800 ))
}

write_partition_metadata() {
  local dump_dir boot_param_start rootfs_param_start rootfs_param_sectors boot_sectors
  local metadata_path part_offset size padded_blocks
  dump_dir="$1"
  boot_sectors="$2"
  boot_param_start="$3"
  rootfs_param_start="$4"
  rootfs_param_sectors="$5"

  metadata_path="$dump_dir/partition-metadata.txt"
  part_offset=0x800

  : > "$metadata_path"

  size="$(stat -c '%s' "$dump_dir/package-file")"
  padded_blocks="$(align_to_0x800_blocks "$size")"
  printf 'package-file,package-file,0x00000000,0xffffffff,0x%08X,0x%08X,0x%08X\n' \
    "$part_offset" "$padded_blocks" "$size" >> "$metadata_path"
  part_offset=$(( part_offset + padded_blocks * 0x800 ))

  size="$(stat -c '%s' "$dump_dir/Image/MiniLoaderAll.bin")"
  padded_blocks="$(align_to_0x800_blocks "$size")"
  printf 'bootloader,Image/MiniLoaderAll.bin,0x00000000,0xffffffff,0x%08X,0x%08X,0x%08X\n' \
    "$part_offset" "$padded_blocks" "$size" >> "$metadata_path"
  part_offset=$(( part_offset + padded_blocks * 0x800 ))

  size="$(stat -c '%s' "$dump_dir/Image/parameter.txt")"
  padded_blocks="$(align_to_0x800_blocks "$size")"
  printf 'parameter,Image/parameter.txt,0x%08X,0x%08X,0x%08X,0x%08X,0x%08X\n' \
    0x2000 0 "$part_offset" "$padded_blocks" "$size" >> "$metadata_path"
  part_offset=$(( part_offset + padded_blocks * 0x800 ))

  size="$(stat -c '%s' "$dump_dir/Image/uboot.img")"
  padded_blocks="$(align_to_0x800_blocks "$size")"
  printf 'uboot,Image/uboot.img,0x%08X,0x%08X,0x%08X,0x%08X,0x%08X\n' \
    0x4000 0x4000 "$part_offset" "$padded_blocks" "$size" >> "$metadata_path"
  part_offset=$(( part_offset + padded_blocks * 0x800 ))

  size="$(stat -c '%s' "$dump_dir/Image/boot.img")"
  padded_blocks="$(align_to_0x800_blocks "$size")"
  printf 'boot,Image/boot.img,0x%08X,0x%08X,0x%08X,0x%08X,0x%08X\n' \
    "$boot_sectors" "$boot_param_start" "$part_offset" "$padded_blocks" "$size" >> "$metadata_path"
  part_offset=$(( part_offset + padded_blocks * 0x800 ))

  size="$(stat -c '%s' "$dump_dir/Image/rootfs.img")"
  padded_blocks="$(align_to_0x800_blocks "$size")"
  printf 'rootfs,Image/rootfs.img,0x%08X,0x%08X,0x%08X,0x%08X,0x%08X\n' \
    "$rootfs_param_sectors" "$rootfs_param_start" "$part_offset" "$padded_blocks" "$size" >> "$metadata_path"
}

run_afptool() {
  local packer_bin dump_dir out_img rkfw_input_dir embedded_update_img fw_timestamp
  packer_bin="$1"
  dump_dir="$2"
  out_img="$3"

  [[ -f "$dump_dir/partition-metadata.txt" ]] || {
    echo "partition-metadata.txt is required for afptool-rs packing." >&2
    return 1
  }

  mkdir -p "$FACTORY_OUTPUT_DIR" "$FACTORY_WORK_DIR"
  rkfw_input_dir="$(mktemp -d "$FACTORY_WORK_DIR/afptool-rs.XXXXXX")"
  trap 'cleanup_path "$rkfw_input_dir" "temporary work dir"' RETURN
  embedded_update_img="$rkfw_input_dir/embedded-update.img"

  cp "$dump_dir/Image/MiniLoaderAll.bin" "$rkfw_input_dir/BOOT"

  log_section "Pack RKAF update image"
  log_item "source dump" "$dump_dir"
  log_item "embedded image" "$embedded_update_img"

  "$packer_bin" pack-rkaf \
    "$dump_dir" \
    "$embedded_update_img" \
    --model "$FACTORY_MACHINE_MODEL" \
    --manufacturer "$FACTORY_MANUFACTURER"

  fw_timestamp="${FACTORY_FW_TIMESTAMP:-$(date -u +%s)}"

  log_section "Pack RKFW FactoryTool image"
  log_item "rkfw input" "$rkfw_input_dir"
  log_item "output" "$out_img"
  log_item "chip" "$FACTORY_AFP_CHIP"
  log_item "version" "$FACTORY_FW_VERSION"

  "$packer_bin" pack-rkfw \
    "$rkfw_input_dir" \
    "$out_img" \
    --chip "$FACTORY_AFP_CHIP" \
    --version "$FACTORY_FW_VERSION" \
    --timestamp "$fw_timestamp" \
    --code "$FACTORY_FW_CODE"

  cleanup_path "$rkfw_input_dir" "temporary work dir"
  trap - RETURN
}

set_boot_env_value() {
  local env_file key value
  env_file="$1"
  key="$2"
  value="$3"

  if grep -q "^${key}=" "$env_file"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "$env_file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

patch_boot_image() {
  local boot_img dtb_path dtb_basename work_dir rebuilt_boot_img
  local versioned_dtb_dir boot_uuid boot_label boot_size
  boot_img="$1"
  dtb_path="$2"
  dtb_basename="$(basename "$FACTORY_BOOT_FDTFILE")"
  mkdir -p "$FACTORY_WORK_DIR"
  work_dir="$(mktemp -d "$FACTORY_WORK_DIR/boot-img.XXXXXX")"
  rebuilt_boot_img="${boot_img}.rebuilt"

  7z x -y "$boot_img" "-o${work_dir}" >/dev/null

  versioned_dtb_dir="$(find "$work_dir" -maxdepth 1 -type d -name 'dtb-*' | head -n 1)"
  [[ -n "$versioned_dtb_dir" ]] || {
    echo "Could not locate versioned dtb directory inside $boot_img" >&2
    cleanup_path "$work_dir" "temporary work dir"
    return 1
  }

  mkdir -p "$versioned_dtb_dir/rockchip"
  cp "$dtb_path" "$versioned_dtb_dir/rockchip/$dtb_basename"

  if [[ -d "$work_dir/dtb/rockchip" ]]; then
    cp "$dtb_path" "$work_dir/dtb/rockchip/$dtb_basename"
  fi

  [[ -f "$work_dir/armbianEnv.txt" ]] || {
    echo "armbianEnv.txt not found inside $boot_img" >&2
    cleanup_path "$work_dir" "temporary work dir"
    return 1
  }

  set_boot_env_value "$work_dir/armbianEnv.txt" "overlay_prefix" "$FACTORY_BOOT_OVERLAY_PREFIX"
  set_boot_env_value "$work_dir/armbianEnv.txt" "fdtfile" "$FACTORY_BOOT_FDTFILE"

  boot_uuid="$("/sbin/blkid" -o value -s UUID "$boot_img" 2>/dev/null || true)"
  boot_label="$("/sbin/blkid" -o value -s LABEL "$boot_img" 2>/dev/null || true)"
  boot_size="$(stat -c '%s' "$boot_img")"
  : "${boot_uuid:=00000000-0000-0000-0000-000000000000}"
  : "${boot_label:=armbi_boot}"

  truncate -s "$boot_size" "$rebuilt_boot_img"
  /sbin/mkfs.ext4 -q -F -b 4096 -L "$boot_label" -U "$boot_uuid" -d "$work_dir" "$rebuilt_boot_img"
  mv "$rebuilt_boot_img" "$boot_img"
  cleanup_path "$work_dir" "temporary work dir"
}

extract_partition_images() {
  local raw_image dump_dir boot_start boot_sectors rootfs_start rootfs_sectors
  local boot_param_start rootfs_param_start rootfs_param_sectors bootloader_blob
  local u_boot_image dtb_path
  raw_image="$1"
  dump_dir="$2"

  log_section "Prepare FactoryTool source dump"
  log_item "input image" "$raw_image"
  log_item "dump dir" "$dump_dir"

  if [[ -n "$FACTORY_SOURCE_DUMP_DIR" ]]; then
    [[ -d "$FACTORY_SOURCE_DUMP_DIR/Image" ]] || {
      echo "FactoryTool source dump not found: $FACTORY_SOURCE_DUMP_DIR/Image" >&2
      return 1
    }

    mkdir -p "$dump_dir/Image"
    cp "$FACTORY_SOURCE_DUMP_DIR/package-file" "$dump_dir/package-file"
    cp "$FACTORY_SOURCE_DUMP_DIR/image.cfg" "$dump_dir/image.cfg"
    cp "$FACTORY_SOURCE_DUMP_DIR/Image/parameter.txt" "$dump_dir/Image/parameter.txt"
    [[ -f "$FACTORY_SOURCE_DUMP_DIR/Image/parameter.txt.parm" ]] && cp "$FACTORY_SOURCE_DUMP_DIR/Image/parameter.txt.parm" "$dump_dir/Image/parameter.txt.parm"
    cp "$FACTORY_SOURCE_DUMP_DIR/Image/MiniLoaderAll.bin" "$dump_dir/Image/MiniLoaderAll.bin"
    cp "$FACTORY_SOURCE_DUMP_DIR/Image/uboot.img" "$dump_dir/Image/uboot.img"
    cp "$FACTORY_SOURCE_DUMP_DIR/Image/boot.img" "$dump_dir/Image/boot.img"
    cp "$FACTORY_SOURCE_DUMP_DIR/Image/rootfs.img" "$dump_dir/Image/rootfs.img"
    [[ -f "$FACTORY_SOURCE_DUMP_DIR/partition-metadata.txt" ]] && cp "$FACTORY_SOURCE_DUMP_DIR/partition-metadata.txt" "$dump_dir/partition-metadata.txt"
    log_item "source" "$FACTORY_SOURCE_DUMP_DIR"
    return 0
  fi

  boot_start=""
  boot_sectors=""
  rootfs_start=""
  rootfs_sectors=""

  while read -r nr start sectors size name; do
    case "$name" in
      bootfs)
        boot_start="$start"
        boot_sectors="$sectors"
        ;;
      rootfs)
        rootfs_start="$start"
        rootfs_sectors="$sectors"
        ;;
    esac
  done < <(partx -g --show -o NR,START,SECTORS,SIZE,NAME "$raw_image")

  [[ -n "$boot_start" && -n "$boot_sectors" ]] || {
    echo "Could not locate bootfs partition in $raw_image" >&2
    return 1
  }
  [[ -n "$rootfs_start" && -n "$rootfs_sectors" ]] || {
    echo "Could not locate rootfs partition in $raw_image" >&2
    return 1
  }

  mkdir -p "$dump_dir/Image"

  log_item "bootfs start" "$boot_start sectors"
  log_item "bootfs size" "$boot_sectors sectors"
  log_item "rootfs start" "$rootfs_start sectors"
  log_item "rootfs size" "$rootfs_sectors sectors"

  if u_boot_image="$(resolve_u_boot_image)"; then
    log_item "uboot image" "$u_boot_image"
    cp "$u_boot_image" "$dump_dir/Image/uboot.img"
  else
    log_item "uboot image" "from raw image"
    dd if="$raw_image" of="$dump_dir/Image/uboot.img" bs=512 skip=16384 count=16384 status=none
  fi

  log_section "Extract raw partitions"
  log_item "boot" "$dump_dir/Image/boot.img"
  dd if="$raw_image" of="$dump_dir/Image/boot.img" bs=512 skip="$boot_start" count="$boot_sectors" status=none
  log_item "rootfs" "$dump_dir/Image/rootfs.img"
  dd if="$raw_image" of="$dump_dir/Image/rootfs.img" bs=512 skip="$rootfs_start" count="$rootfs_sectors" status=none

  if dtb_path="$(resolve_boot_dtb_path)"; then
    log_item "patch boot dtb" "$dtb_path"
    patch_boot_image "$dump_dir/Image/boot.img" "$dtb_path"
  fi

  bootloader_blob="$(resolve_bootloader_blob)"
  log_item "bootloader" "$bootloader_blob"
  cp "$bootloader_blob" "$dump_dir/Image/MiniLoaderAll.bin"

  boot_param_start="${FACTORY_BOOT_START_SECTORS}"
  rootfs_param_start="${FACTORY_ROOTFS_START_SECTORS}"
  rootfs_param_sectors="${FACTORY_ROOTFS_PARAMETER_SECTORS:-$rootfs_sectors}"

  cat > "$dump_dir/package-file" <<'EOF'
package-file	package-file
bootloader	Image/MiniLoaderAll.bin
parameter	Image/parameter.txt
uboot	Image/uboot.img
boot	Image/boot.img
rootfs Image/rootfs.img
EOF

  cat > "$dump_dir/image.cfg" <<EOF
[RKFW]

FW_DateTime = $(date -u +'%Y.%m.%d_%H:%M:%S')
FW_ChipID   = 0x33353238
FW_Version  = ${FACTORY_FW_VERSION}
FW_Code     = ${FACTORY_FW_CODE}
RKFWtype    = 0x00000001
Unknown_1   = 0x00000000

[RKAF]

package-file:type=00
bootloader:type=00
parameter:type=12
uboot:type=43
boot:type=03
baseparameter:type=00
rootfs:type=03

[SPECIAL]

BlockCount     = true
DirtyBlk       = false
Loader         = false
BackupEndExist = false
EOF

  cat > "$dump_dir/Image/parameter.txt" <<EOF
FIRMWARE_VER: 12.0
MACHINE_MODEL: ${FACTORY_MACHINE_MODEL}
MACHINE_ID: ${FACTORY_MACHINE_ID}
MANUFACTURER: ${FACTORY_MANUFACTURER}
MAGIC: 0x5041524B
ATAG: 0x00200800
MACHINE: rockchip012
CHECK_MASK: 0x80
PWR_HLD: 0,0,A,0,1
TYPE: GPT
CMDLINE:mtdparts=rk29xxnand:0x00002000@0x00002000(security),0x00004000@0x00004000(uboot),$(printf '0x%08X' "$boot_sectors")@$(printf '0x%08X' "$((boot_param_start))")(boot:bootable),$(printf '0x%08X' "$((rootfs_param_sectors))")@$(printf '0x%08X' "$((rootfs_param_start))")(rootfs:grow)
EOF

  write_partition_metadata \
    "$dump_dir" \
    "$boot_sectors" \
    "$((boot_param_start))" \
    "$((rootfs_param_start))" \
    "$((rootfs_param_sectors))"
}

main() {
  local image_base out_img dump_dir packer_bin

  trap cleanup_factory_work_dir EXIT

  if [[ -z "$RAW_IMAGE_PATH" ]]; then
    if [[ -n "$FACTORY_SOURCE_DUMP_DIR" ]]; then
      RAW_IMAGE_PATH="${FACTORY_SOURCE_DUMP_DIR%.dump}"
    else
      RAW_IMAGE_PATH="$(find_latest_image)"
    fi
  fi

  [[ -n "$RAW_IMAGE_PATH" && -f "$RAW_IMAGE_PATH" ]] || {
    echo "No input image found to package." >&2
    return 1
  }

  if [[ -z "$FACTORY_SOURCE_DUMP_DIR" && ! -d "$ARMBIAN_BUILD_DIR/output/images" ]]; then
    echo "Armbian output directory not found: $ARMBIAN_BUILD_DIR/output/images" >&2
    return 1
  fi

  resolve_bootloader_blob >/dev/null

  packer_bin="$AFPTOOL_BIN"
  [[ -x "$packer_bin" ]] || {
    echo "Expected rebuilt afptool-rs binary was not found: $packer_bin" >&2
    return 1
  }

  mkdir -p "$FACTORY_OUTPUT_DIR"
  cleanup_factory_work_dir
  cleanup_previous_factory_outputs

  image_base="$(basename "$RAW_IMAGE_PATH" .img)"
  out_img="$FACTORY_OUTPUT_DIR/${image_base}-factorytool.img"
  dump_dir="${out_img}.dump"

  cleanup_path "$dump_dir" "factory dump"
  cleanup_path "$out_img" "factory output"

  log_section "Start FactoryTool repack"
  log_item "input" "$RAW_IMAGE_PATH"
  log_item "output" "$out_img"
  log_item "packer" "$packer_bin"

  extract_partition_images "$RAW_IMAGE_PATH" "$dump_dir"
  run_afptool "$packer_bin" "$dump_dir" "$out_img"

  [[ -f "$out_img" ]] || {
    echo "Expected FactoryTool image was not produced: $out_img" >&2
    return 1
  }

  if [[ "$FACTORY_KEEP_DUMP" != "yes" ]]; then
    cleanup_path "$dump_dir" "factory dump"
  fi

  cleanup_factory_work_dir

  log_section "FactoryTool image created"
  log_item "output" "$out_img"
  log_item "size" "$(du -h "$out_img" 2>/dev/null | awk '{print $1}')"
  trap - EXIT
}

main "$@"
