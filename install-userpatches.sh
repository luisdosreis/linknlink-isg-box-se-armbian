#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARMBIAN_BUILD_DIR="${1:-}"

if [[ -z "$ARMBIAN_BUILD_DIR" ]]; then
  echo "usage: $0 /path/to/armbian-build" >&2
  exit 1
fi

if [[ ! -d "$ARMBIAN_BUILD_DIR" ]]; then
  echo "Armbian build directory not found: $ARMBIAN_BUILD_DIR" >&2
  exit 1
fi

mkdir -p "$ARMBIAN_BUILD_DIR/userpatches"
rsync -a --delete "$REPO_DIR/userpatches/" "$ARMBIAN_BUILD_DIR/userpatches/"
if [[ -d "$REPO_DIR/resources/firmware" ]]; then
  mkdir -p "$ARMBIAN_BUILD_DIR/userpatches/firmware"
  rsync -a --delete "$REPO_DIR/resources/firmware/" "$ARMBIAN_BUILD_DIR/userpatches/firmware/"
fi
if [[ -d "$REPO_DIR/resources/drivers" ]]; then
  mkdir -p "$ARMBIAN_BUILD_DIR/userpatches/drivers"
  rsync -a --delete "$REPO_DIR/resources/drivers/" "$ARMBIAN_BUILD_DIR/userpatches/drivers/"
fi

echo "Installed userpatches into: $ARMBIAN_BUILD_DIR/userpatches"
