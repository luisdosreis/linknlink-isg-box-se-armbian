#!/usr/bin/env bash
set -euo pipefail

install_overlay() {
    [[ -d /tmp/overlay ]] || {
        echo "LinknLink image overlay is not available" >&2
        exit 1
    }

    # The overlay is bind-mounted from the build host and therefore carries the
    # host user's UID, GID, and umask-derived directory modes. Archive mode must
    # not be used here: it would apply those attributes to existing paths such
    # as /, /etc, and /usr in the target image.
    (
        umask 022
        cp -R --no-preserve=ownership /tmp/overlay/. /
    )

    chown root:root /etc/NetworkManager/system-connections/eth0-dhcp.nmconnection
    chmod 0600 /etc/NetworkManager/system-connections/eth0-dhcp.nmconnection
    chown root:root /usr/local/sbin/linknlink-eth0-mac
    chmod 0755 /usr/local/sbin/linknlink-eth0-mac

    local path owner_uid
    for path in / /etc /usr /usr/local /usr/local/sbin \
        /etc/NetworkManager/system-connections/eth0-dhcp.nmconnection \
        /usr/local/sbin/linknlink-eth0-mac; do
        owner_uid="$(stat -c '%u' "$path")"
        if [[ "$owner_uid" != "0" ]]; then
            echo "LinknLink image overlay left $path owned by UID $owner_uid; expected UID 0" >&2
            exit 1
        fi
    done
}

configure_boot_environment() {
    [[ -f /boot/armbianEnv.txt ]] || return 0

    if grep -q '^extraargs=' /boot/armbianEnv.txt; then
        sed -i '/^extraargs=/ {
            /net.ifnames=0/! s/$/ net.ifnames=0/
            /biosdevname=0/! s/$/ biosdevname=0/
        }' /boot/armbianEnv.txt
    else
        printf '%s\n' 'extraargs=net.ifnames=0 biosdevname=0' >>/boot/armbianEnv.txt
    fi
}

enable_services() {
    command -v systemctl >/dev/null 2>&1 || return 0

    systemctl disable armbian-led-state.service 2>/dev/null || true
    systemctl enable NetworkManager.service 2>/dev/null || true
    systemctl enable linknlink-eth0-mac.service 2>/dev/null || true
    systemctl enable systemd-resolved.service 2>/dev/null || true
    systemctl enable keyboard-setup.service console-setup.service 2>/dev/null || true
    systemctl enable bluetooth.service 2>/dev/null || systemctl enable bluetooth 2>/dev/null || true
    systemctl enable ssh.service 2>/dev/null || systemctl enable ssh 2>/dev/null || true
}

install_overlay
install -d -m 0755 /data /run/sshd

if command -v setupcon >/dev/null 2>&1; then
    LC_ALL=C LANG=C setupcon --save --force 2>/dev/null || true
fi

configure_boot_environment
enable_services
