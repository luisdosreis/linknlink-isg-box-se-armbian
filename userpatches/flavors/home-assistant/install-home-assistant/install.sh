#!/usr/bin/env bash
set -euo pipefail

HA_APP_REPOSITORY_URL="${HA_APP_REPOSITORY_URL:-https://github.com/luisdosreis/armbian-ha-app.git}"
HA_APP_REF="${HA_APP_REF:-main}"
HA_APP_INSTALLER="${HA_APP_INSTALLER:-install.sh}"
checkout_dir=""

cleanup() {
    if [[ -n "$checkout_dir" && -d "$checkout_dir" ]]; then
        rm -rf -- "$checkout_dir"
    fi
}
trap cleanup EXIT

die() {
    echo "install-home-assistant: $*" >&2
    exit 1
}

network_help() {
    cat >&2 <<'EOF'
Internet access is not available yet.

Connect Ethernet or configure Wi-Fi first, then run this installer again.
Useful commands:
  sudo armbian-config
  nmcli device status
EOF
}

for command in curl git mktemp; do
    command -v "$command" >/dev/null 2>&1 || die "required command is missing: $command"
done

if ! curl --fail --location --silent --show-error \
    --connect-timeout 10 --max-time 20 https://github.com/ >/dev/null; then
    network_help
    exit 2
fi

if ((EUID != 0)); then
    die "run this installer with sudo: sudo ./install.sh"
fi

if ! git ls-remote --exit-code "$HA_APP_REPOSITORY_URL" "$HA_APP_REF" >/dev/null 2>&1; then
    die "cannot access ${HA_APP_REPOSITORY_URL} at ref ${HA_APP_REF}"
fi

checkout_dir="$(mktemp -d /tmp/armbian-ha-app.XXXXXX)"
git clone --depth=1 --branch "$HA_APP_REF" "$HA_APP_REPOSITORY_URL" "$checkout_dir/repository"

installer_path="${checkout_dir}/repository/${HA_APP_INSTALLER}"
[[ -f "$installer_path" ]] || die "repository installer was not found: ${HA_APP_INSTALLER}"

echo "Launching Home Assistant installer from ${HA_APP_REPOSITORY_URL} (${HA_APP_REF})"
(
    cd "${checkout_dir}/repository"
    bash "./${HA_APP_INSTALLER}" "$@"
)
