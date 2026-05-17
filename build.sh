#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
usage: ./build.sh [options] [armbian-build-dir]

Build the raw Armbian image for the LinknLink iSG Box SE.

Options:
  --kernel vendor        Supported kernel path
  --help                Show this help

Environment overrides are still supported, including BOARD, BRANCH, and RELEASE.
This repo supports only the vendor kernel path.

After this finishes, repack the generated image with:
  image-tools/repack-afptool-rs.sh
EOF
}

ARMBIAN_BUILD_DIR=""
KERNEL_SELECTION="${KERNEL_SELECTION:-vendor}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --kernel)
      if [[ "$#" -lt 2 ]]; then
        echo "--kernel requires a value: vendor" >&2
        usage >&2
        exit 1
      fi
      KERNEL_SELECTION="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$ARMBIAN_BUILD_DIR" ]]; then
        echo "Unexpected extra argument: $1" >&2
        usage >&2
        exit 1
      fi
      ARMBIAN_BUILD_DIR="$1"
      shift
      ;;
  esac
done

case "$KERNEL_SELECTION" in
  vendor) ;;
  *)
    echo "Unsupported kernel selection: $KERNEL_SELECTION" >&2
    usage >&2
    exit 1
    ;;
esac

ARMBIAN_BUILD_DIR="${ARMBIAN_BUILD_DIR:-$PWD/build}"

if [ ! -d "$ARMBIAN_BUILD_DIR/.git" ]; then
  git clone --depth=1 https://github.com/armbian/build "$ARMBIAN_BUILD_DIR"
fi

mkdir -p "$ARMBIAN_BUILD_DIR/userpatches"
rsync -a --delete "$SELF_DIR/userpatches/" "$ARMBIAN_BUILD_DIR/userpatches/"
if [[ -d "$SELF_DIR/resources/firmware" ]]; then
  mkdir -p "$ARMBIAN_BUILD_DIR/userpatches/firmware"
  rsync -a --delete "$SELF_DIR/resources/firmware/" "$ARMBIAN_BUILD_DIR/userpatches/firmware/"
fi
if [[ -d "$SELF_DIR/resources/drivers" ]]; then
  mkdir -p "$ARMBIAN_BUILD_DIR/userpatches/drivers"
  rsync -a --delete "$SELF_DIR/resources/drivers/" "$ARMBIAN_BUILD_DIR/userpatches/drivers/"
fi

cd "$ARMBIAN_BUILD_DIR"
BOARD="${BOARD:-linknlink-isg-box-se}"
RELEASE="${RELEASE:-bookworm}"

cleanup_previous_outputs() {
  local deb_dir image_dir

  deb_dir="$ARMBIAN_BUILD_DIR/output/debs"
  image_dir="$ARMBIAN_BUILD_DIR/output/images"

  echo "Cleaning previous kernel packages and raw images..."

  if [[ -d "$deb_dir" ]]; then
    find "$deb_dir" -maxdepth 1 -type f \( \
      -name 'linux-image-*-rk35xx_*.deb' -o \
      -name 'linux-dtb-*-rk35xx_*.deb' -o \
      -name 'linux-headers-*-rk35xx_*.deb' -o \
      -name 'linux-libc-dev-*-rk35xx_*.deb' \
    \) -delete
  fi

  if [[ -d "$image_dir" ]]; then
    find "$image_dir" -maxdepth 1 -type f \( \
      -name '*.img' -o \
      -name '*.img.sha' -o \
      -name '*.img.txt' -o \
      -name '*.img.xz' -o \
      -name '*.img.xz.sha' -o \
      -name '*.img.xz.txt' \
    \) -delete
  fi
}

build_one() {
  local branch="$1"
  local enable_extensions="${ENABLE_EXTENSIONS:-}"

  case ",${enable_extensions}," in
    *,isg-build-network,*) ;;
    *)
      enable_extensions="${enable_extensions:+${enable_extensions},}isg-build-network"
      ;;
  esac

  if [[ "${ISG_FAST_KERNEL_CONFIG:-yes}" == "yes" ]]; then
    case ",${enable_extensions}," in
      *,isg-fast-kernel-config,*) ;;
      *)
        enable_extensions="${enable_extensions:+${enable_extensions},}isg-fast-kernel-config"
        ;;
    esac
  fi

  case ",${enable_extensions}," in
    *,isg-seekwave-driver,*) ;;
    *)
      enable_extensions="${enable_extensions:+${enable_extensions},}isg-seekwave-driver"
      ;;
  esac

	./compile.sh build \
		BOARD="$BOARD" \
		BRANCH="$branch" \
		RELEASE="$RELEASE" \
		BUILD_MINIMAL="${BUILD_MINIMAL:-no}" \
		BUILD_DESKTOP=no \
    KERNEL_CONFIGURE=no \
    KERNEL_BTF=no \
    NAMESERVER="${NAMESERVER:-1.1.1.1}" \
    ENABLE_EXTENSIONS="$enable_extensions"
}

cleanup_previous_outputs

if [[ -n "${BRANCH:-}" && "${BRANCH}" != "vendor" ]]; then
  echo "Unsupported BRANCH=${BRANCH}. This repo supports only BRANCH=vendor." >&2
  exit 1
fi

build_one vendor

echo "Raw Armbian image is available under: $ARMBIAN_BUILD_DIR/output/images/"
echo "Repack it with image-tools/repack-afptool-rs.sh."
