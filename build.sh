#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARMBIAN_BUILD_DIR="${ARMBIAN_BUILD_DIR:-${REPO_DIR}/build}"
ARMBIAN_BUILD_URL="${ARMBIAN_BUILD_URL:-https://github.com/armbian/build.git}"
flavor="server"

usage() {
    cat <<'EOF'
usage: ./build.sh [server|desktop|home-assistant] [armbian-build-dir]

Build a LinknLink iSG Box SE Armbian image using a named userpatch config.
The default flavor is server and the default Armbian checkout is ./build.

Environment:
  ARMBIAN_BUILD_DIR   Override the Armbian checkout path
  ARMBIAN_BUILD_URL   Override the Armbian build repository URL
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ -n "${1:-}" ]]; then
    flavor="$1"
    shift
fi

case "$flavor" in
    server|desktop|home-assistant) ;;
    *)
        echo "Unknown image flavor: $flavor" >&2
        usage >&2
        exit 1
        ;;
esac

if [[ -n "${1:-}" ]]; then
    ARMBIAN_BUILD_DIR="$1"
    shift
fi

if (($#)); then
    echo "Unexpected argument: $1" >&2
    usage >&2
    exit 1
fi

if [[ ! -d "${ARMBIAN_BUILD_DIR}/.git" ]]; then
    git clone --depth=1 "$ARMBIAN_BUILD_URL" "$ARMBIAN_BUILD_DIR"
fi

"${REPO_DIR}/install-userpatches.sh" "$ARMBIAN_BUILD_DIR"

cd "$ARMBIAN_BUILD_DIR"
./compile.sh "linknlink-${flavor}" build

echo "Raw ${flavor} image: ${ARMBIAN_BUILD_DIR}/output/images/"
echo "FactoryTool repack: ${REPO_DIR}/image-tools/repack-afptool-rs.sh ${ARMBIAN_BUILD_DIR}"
