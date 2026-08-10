#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARMBIAN_BUILD_DIR="${1:-}"

if [[ -z "$ARMBIAN_BUILD_DIR" || ! -x "${ARMBIAN_BUILD_DIR}/compile.sh" ]]; then
    echo "usage: $0 /path/to/armbian-build" >&2
    exit 1
fi

mkdir -p "${ARMBIAN_BUILD_DIR}/userpatches"
rsync -a --delete "${REPO_DIR}/userpatches/" "${ARMBIAN_BUILD_DIR}/userpatches/"

echo "Installed LinknLink userpatches into: ${ARMBIAN_BUILD_DIR}/userpatches"
