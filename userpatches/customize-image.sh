#!/usr/bin/env bash
set -euo pipefail

install_home_assistant_setup_helpers() {
    local overlay_dir="/tmp/overlay"

    [[ -d "$overlay_dir" ]] || {
        echo "Home Assistant setup helper overlay is not available" >&2
        exit 1
    }

    install -d -m 0755 /usr/local/bin /usr/share/ha-stack /etc/profile.d

    cp -a "${overlay_dir}/usr/local/bin/." /usr/local/bin/
    cp -a "${overlay_dir}/usr/share/ha-stack/." /usr/share/ha-stack/
    cp -a "${overlay_dir}/etc/profile.d/." /etc/profile.d/

    chmod 0755 /usr/local/bin/ha-setup /usr/local/bin/ha-app /usr/local/bin/ha-stack-check
    chmod 0644 /etc/profile.d/zz-ha-setup-prompt.sh
}

Main() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable armbian-led-state.service 2>/dev/null || true
    fi

    install -d -m 0755 /etc/default
    cat >/etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

    cat >/etc/default/console-setup <<'EOF'
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="guess"
FONTFACE="Fixed"
FONTSIZE="8x16"
VIDEOMODE=
EOF

    install -d -m 0755 /etc/systemd/system/console-setup.service.d
    cat >/etc/systemd/system/console-setup.service.d/10-linknlink-tmp-ordering.conf <<'EOF'
[Unit]
After=tmp.mount armbian-zram-config.service local-fs.target
RequiresMountsFor=/tmp
EOF

    if command -v setupcon >/dev/null 2>&1; then
        LC_ALL=C LANG=C setupcon --save --force 2>/dev/null || true
    fi

    install -d -m 0755 /etc/modules-load.d
    {
        echo "cpufreq_dt"
        if find /lib/modules -type f -name 'skw_sdio.ko' | grep -q .; then
            echo "skw_sdio"
        fi
        if find /lib/modules -type f -name 'skw.ko' | grep -q .; then
            echo "skw"
        fi
        if find /lib/modules -type f -name 'skw_sdio_lite.ko' | grep -q .; then
            echo "skw_sdio_lite"
        fi
        if find /lib/modules -type f -name 'swt6621s_wifi.ko' | grep -q .; then
            echo "swt6621s_wifi"
        fi
        if find /lib/modules -type f -name 'skwbt.ko' | grep -q .; then
            echo "skwbt"
        fi
    } >/etc/modules-load.d/swt6621s-wifi.conf

    install -d -m 0755 /etc/modprobe.d
    cat >/etc/modprobe.d/seekwave-power.conf <<'EOF'
# Keep the always-on iSG Box Wi-Fi responsive while idle. Set to 1 to allow
# firmware deep sleep and reduce power use.
options skw_sdio_lite fw_deepsleep=0
EOF
    chmod 0644 /etc/modprobe.d/seekwave-power.conf

    install -d -m 0755 /etc/NetworkManager/system-connections /data

    cat >/etc/NetworkManager/system-connections/eth0-dhcp.nmconnection <<'EOF'
[connection]
id=eth0-dhcp
type=ethernet
interface-name=eth0
autoconnect=true

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=default
EOF
    chmod 0600 /etc/NetworkManager/system-connections/eth0-dhcp.nmconnection

    install -d -m 0755 /usr/local/sbin /etc/systemd/system
    cat >/usr/local/sbin/linknlink-eth0-mac <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

connection_file="/etc/NetworkManager/system-connections/eth0-dhcp.nmconnection"
state_dir="/var/lib/linknlink"
done_file="${state_dir}/eth0-mac.done"

valid_mac() {
    [[ "${1:-}" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || return 1
    [[ "$1" != "00:00:00:00:00:00" && "$1" != "ff:ff:ff:ff:ff:ff" ]]
}

is_locally_administered() {
    local first
    first=$((16#${1%%:*}))
    ((first & 2))
}

write_connection() {
    local mac="${1:-}"

    {
        printf '%s\n' '[connection]'
        printf '%s\n' 'id=eth0-dhcp'
        printf '%s\n' 'type=ethernet'
        printf '%s\n' 'interface-name=eth0'
        printf '%s\n' 'autoconnect=true'
        printf '\n'
        if [[ -n "$mac" ]]; then
            printf '%s\n' '[ethernet]'
            printf 'cloned-mac-address=%s\n' "$mac"
            printf '\n'
        fi
        printf '%s\n' '[ipv4]'
        printf '%s\n' 'method=auto'
        printf '\n'
        printf '%s\n' '[ipv6]'
        printf '%s\n' 'method=auto'
        printf '%s\n' 'addr-gen-mode=default'
    } >"$connection_file"

    chmod 0600 "$connection_file"
}

hash_input() {
    local serial nvmem nvmem_hash machine_id

    if [[ -r /proc/device-tree/serial-number ]]; then
        serial="$(tr -d '\0' </proc/device-tree/serial-number || true)"
        if [[ -n "$serial" && "$serial" != "0000000000000000" ]]; then
            printf 'dt-serial:%s' "$serial"
            return 0
        fi
    fi

    for nvmem in /sys/bus/nvmem/devices/*/nvmem; do
        [[ -r "$nvmem" ]] || continue
        if [[ -s "$nvmem" ]]; then
            nvmem_hash="$(sha256sum "$nvmem" 2>/dev/null | awk '{print $1}' || true)"
            if [[ -n "$nvmem_hash" ]]; then
                printf 'nvmem:%s' "$nvmem_hash"
                return 0
            fi
        fi
    done

    if [[ -r /etc/machine-id ]]; then
        machine_id="$(cat /etc/machine-id || true)"
        if [[ -n "$machine_id" ]]; then
            printf 'machine-id:%s' "$machine_id"
            return 0
        fi
    fi

    return 1
}

derive_local_mac() {
    local seed hex first

    if seed="$(hash_input)"; then
        hex="$(printf '%s' "$seed" | sha256sum | awk '{print $1}')"
    else
        hex="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
    fi
    first=$(((16#${hex:0:2} & 254) | 2))

    printf '%02x:%s:%s:%s:%s:%s\n' \
        "$first" "${hex:2:2}" "${hex:4:2}" "${hex:6:2}" "${hex:8:2}" "${hex:10:2}"
}

current_mac=""
if [[ -r /sys/class/net/eth0/address ]]; then
    current_mac="$(cat /sys/class/net/eth0/address || true)"
fi

if valid_mac "$current_mac" && ! is_locally_administered "$current_mac"; then
    write_connection ""
    install -d -m 0755 "$state_dir"
    printf 'factory\n' >"$done_file"
    logger -t linknlink-eth0-mac "preserving factory MAC ${current_mac}"
    exit 0
fi

generated_mac="$(derive_local_mac)"
write_connection "$generated_mac"
install -d -m 0755 "$state_dir"
printf '%s\n' "$generated_mac" >"$done_file"
logger -t linknlink-eth0-mac "using stable local MAC ${generated_mac}"
EOF
    chmod 0755 /usr/local/sbin/linknlink-eth0-mac

    cat >/etc/systemd/system/linknlink-eth0-mac.service <<'EOF'
[Unit]
Description=Prepare stable Ethernet MAC for eth0
DefaultDependencies=no
Before=NetworkManager.service
After=sys-subsystem-net-devices-eth0.device systemd-machine-id-commit.service
Wants=sys-subsystem-net-devices-eth0.device
ConditionPathExists=!/var/lib/linknlink/eth0-mac.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/linknlink-eth0-mac

[Install]
WantedBy=NetworkManager.service
EOF

    if [[ -f /boot/armbianEnv.txt ]]; then
        if grep -q '^extraargs=' /boot/armbianEnv.txt; then
            sed -i '/^extraargs=/ {
                /net.ifnames=0/! s/$/ net.ifnames=0/
                /biosdevname=0/! s/$/ biosdevname=0/
            }' /boot/armbianEnv.txt
        else
            printf '%s\n' 'extraargs=net.ifnames=0 biosdevname=0' >>/boot/armbianEnv.txt
        fi
    fi

    mkdir -p /run/sshd
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable NetworkManager.service 2>/dev/null || true
        systemctl enable linknlink-eth0-mac.service 2>/dev/null || true
        systemctl enable systemd-resolved.service 2>/dev/null || true
        systemctl enable keyboard-setup.service console-setup.service 2>/dev/null || true
        systemctl enable bluetooth.service 2>/dev/null || systemctl enable bluetooth 2>/dev/null || true
        systemctl enable ssh.service 2>/dev/null || systemctl enable ssh 2>/dev/null || true
    fi

    install_home_assistant_setup_helpers
}

Main
