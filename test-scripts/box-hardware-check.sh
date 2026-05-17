#!/usr/bin/env bash
set -euo pipefail

stamp="${1:-$(date -u +%Y%m%d%H%M%S)}"
root_dir="/tmp/hardware-check-${stamp}"
log_dir="${root_dir}/box-logs"
summary="${log_dir}/summary.txt"
steps="${log_dir}/steps.txt"

export LC_ALL=C
export SYSTEMD_COLORS=0
export SYSTEMD_PAGER=cat
export TERM=dumb

mkdir -p "$log_dir"

append_summary() {
  printf '%s=%s\n' "$1" "$2" >>"$summary"
}

run_capture_timeout() {
  local seconds name rc
  seconds="$1"
  name="$2"
  shift 2

  printf '%s start %s\n' "$(date -Is)" "$name" >>"$steps"
  set +e
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 2s "$seconds" "$@" >"${log_dir}/${name}" 2>&1
  else
    "$@" >"${log_dir}/${name}" 2>&1
  fi
  rc=$?
  set -e
  printf '%s done %s rc=%s\n' "$(date -Is)" "$name" "$rc" >>"$steps"
  return "$rc"
}

run_shell() {
  local seconds name script
  seconds="$1"
  name="$2"
  script="$3"
  run_capture_timeout "$seconds" "$name" sh -c "$script" || true
}

copy_if_exists() {
  local src dst
  src="$1"
  dst="$2"
  if [[ -e "$src" ]]; then
    cp -a "$src" "$dst" 2>/dev/null || true
  fi
}

append_summary timestamp "$stamp"
append_summary hostname "$(hostname 2>/dev/null || echo unknown)"
append_summary kernel "$(uname -r 2>/dev/null || echo unknown)"

run_capture_timeout 5s uname.txt uname -a || true
run_shell 5s os-release.txt "cat /etc/os-release 2>/dev/null || true"
run_shell 5s uptime.txt "uptime; cat /proc/uptime 2>/dev/null || true"
run_shell 5s cmdline.txt "cat /proc/cmdline 2>/dev/null || true"
run_shell 8s boot-files.txt "find /boot -maxdepth 2 -type f \\( -name 'armbianEnv.txt' -o -name '*.dtb' -o -name 'boot.scr' -o -name 'uInitrd' -o -name 'Image' \\) -printf '%s %p\n' 2>/dev/null | sort || true; echo '--- armbianEnv.txt ---'; cat /boot/armbianEnv.txt 2>/dev/null || true"
run_shell 8s modules.txt "lsmod 2>/dev/null || true"

run_shell 5s cpu-lscpu.txt "lscpu 2>/dev/null || cat /proc/cpuinfo 2>/dev/null || true"
run_shell 5s cpu-freq.txt "for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq /sys/devices/system/cpu/cpu*/cpufreq/scaling_available_frequencies /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do [ -e \"\$f\" ] && printf '%s: ' \"\$f\" && cat \"\$f\"; done"
run_shell 5s thermal.txt "for f in /sys/class/thermal/thermal_zone*/type /sys/class/thermal/thermal_zone*/temp; do [ -e \"\$f\" ] && printf '%s: ' \"\$f\" && cat \"\$f\"; done"
run_shell 5s memory.txt "free -h 2>/dev/null || true; cat /proc/meminfo 2>/dev/null || true"

run_shell 8s storage-lsblk.txt "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL 2>/dev/null || true"
run_shell 8s storage-df.txt "df -hT 2>/dev/null || true"
run_shell 8s storage-mounts.txt "findmnt 2>/dev/null || cat /proc/mounts 2>/dev/null || true"
run_shell 5s storage-mmc.txt "for d in /sys/block/mmcblk*; do [ -d \"\$d\" ] || continue; echo \"== \$d ==\"; for f in device/name device/type device/cid device/csd size queue/logical_block_size; do [ -e \"\$d/\$f\" ] && printf '%s: ' \"\$f\" && cat \"\$d/\$f\"; done; done"

run_shell 8s network-links.txt "ip -br link 2>/dev/null || ip link 2>/dev/null || true"
run_shell 8s network-addresses.txt "ip -br addr 2>/dev/null || ip addr 2>/dev/null || true"
run_shell 8s network-routes.txt "ip route 2>/dev/null || true"
run_shell 8s ethernet.txt "for i in /sys/class/net/e*; do [ -d \"\$i\" ] || continue; echo \"== \$(basename \"\$i\") ==\"; for f in address addr_assign_type carrier speed duplex operstate; do [ -e \"\$i/\$f\" ] && printf '%s: ' \"\$f\" && cat \"\$i/\$f\"; done; done; nmcli -f NAME,UUID,TYPE,DEVICE connection show 2>/dev/null || true; nmcli -f connection.id,connection.interface-name,ethernet.cloned-mac-address connection show eth0-dhcp 2>/dev/null || true"
run_shell 8s ethernet-ethtool.txt "for dev in \$(ls /sys/class/net 2>/dev/null | grep '^e' || true); do echo \"== \$dev ==\"; ethtool \"\$dev\" 2>/dev/null || true; ethtool -S \"\$dev\" 2>/dev/null || true; done"
run_shell 12s wifi.txt "iw dev 2>/dev/null || true; iw dev wlan0 link 2>/dev/null || true; nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null || true; rfkill list 2>/dev/null || true"
run_shell 12s bluetooth.txt "hciconfig -a 2>/dev/null || true; bluetoothctl list 2>/dev/null || true; bluetoothctl show 2>/dev/null || true; rfkill list bluetooth 2>/dev/null || true"

run_shell 8s usb.txt "lsusb 2>/dev/null || true; find /sys/bus/usb/devices -mindepth 1 -maxdepth 1 -type l -print 2>/dev/null | sort | while read -r d; do [ -d \"\$d\" ] || continue; echo \"== \$d ==\"; for f in product manufacturer serial speed idVendor idProduct; do [ -e \"\$d/\$f\" ] && printf '%s: ' \"\$f\" && cat \"\$d/\$f\"; done; done"
run_shell 8s display-drm.txt "ls -la /sys/class/drm 2>/dev/null || true; for f in /sys/class/drm/card*/status /sys/class/drm/card*/enabled /sys/class/drm/card*/modes; do [ -e \"\$f\" ] && echo \"== \$f ==\" && cat \"\$f\"; done"
run_shell 8s audio.txt "aplay -l 2>/dev/null || true; arecord -l 2>/dev/null || true; cat /proc/asound/cards 2>/dev/null || true; cat /proc/asound/devices 2>/dev/null || true"
run_shell 8s input.txt "cat /proc/bus/input/devices 2>/dev/null || true; for f in /sys/class/input/input*/name; do [ -e \"\$f\" ] && printf '%s: ' \"\$f\" && cat \"\$f\"; done"
run_shell 8s leds-gpio.txt "ls -la /sys/class/leds 2>/dev/null || true; for f in /sys/class/leds/*/trigger /sys/class/leds/*/brightness; do [ -e \"\$f\" ] && echo \"== \$f ==\" && cat \"\$f\"; done; gpioinfo 2>/dev/null || true"
run_shell 8s rtc.txt "timedatectl 2>/dev/null || true; hwclock -r 2>/dev/null || true; ls -la /sys/class/rtc 2>/dev/null || true"
run_shell 8s regulators-power.txt "for d in /sys/class/regulator/*; do [ -d \"\$d\" ] || continue; echo \"== \$d ==\"; for name in name state microvolts; do f=\"\$d/\$name\"; [ -e \"\$f\" ] && printf '%s: ' \"\$name\" && cat \"\$f\"; done; done"

run_shell 20s kernel-log.txt "journalctl -k -b --no-pager 2>/dev/null || dmesg 2>/dev/null || true"
run_shell 20s kernel-errors.txt "journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'fail|error|timeout|reset|warn|oops|panic|firmware|mmc|sdio|wifi|bluetooth|hci|usb|hdmi|drm|audio|thermal|regulator' || true"
run_shell 12s services.txt "systemctl --no-pager --failed 2>/dev/null || true; systemctl --no-pager --full status NetworkManager.service linknlink-eth0-mac.service bluetooth.service ssh.service console-setup.service keyboard-setup.service armbian-zram-config.service tmp.mount 2>/dev/null || true; echo '--- unit definitions ---'; systemctl --no-pager cat linknlink-eth0-mac.service console-setup.service keyboard-setup.service armbian-zram-config.service tmp.mount 2>/dev/null || true; echo '--- setup journals ---'; journalctl -b --no-pager -u linknlink-eth0-mac.service -u console-setup.service -u keyboard-setup.service -u armbian-zram-config.service -u tmp.mount 2>/dev/null || true"

if grep -q '^hci0:' "${log_dir}/bluetooth.txt"; then
  append_summary bluetooth_hci0 yes
else
  append_summary bluetooth_hci0 no
fi

if grep -q '^Connected to' "${log_dir}/wifi.txt" || grep -q '^wlan0:wifi:connected:' "${log_dir}/wifi.txt"; then
  append_summary wifi_connected yes
else
  append_summary wifi_connected no
fi

if grep -q 'carrier: 1' "${log_dir}/ethernet.txt" || grep -Eq '^(eth|end)[0-9]+[[:space:]]+UP[[:space:]]' "${log_dir}/network-links.txt"; then
  append_summary ethernet_link yes
else
  append_summary ethernet_link no
fi

if grep -q -- '--- no soundcards ---' "${log_dir}/audio.txt"; then
  append_summary audio_card no
else
  append_summary audio_card yes
fi

if grep -A1 'HDMI.*status' "${log_dir}/display-drm.txt" 2>/dev/null | grep -q '^connected$'; then
  append_summary hdmi_connected yes
else
  append_summary hdmi_connected no
fi

if grep -q '^Bus ' "${log_dir}/usb.txt"; then
  append_summary usb_root_hubs yes
else
  append_summary usb_root_hubs no
fi

if grep -q '0 loaded units listed' "${log_dir}/services.txt"; then
  append_summary failed_services no
else
  append_summary failed_services yes
fi

copy_if_exists /etc/modules-load.d "${root_dir}/modules-load-copy"

tarball="/tmp/hardware-check-${stamp}.tar.gz"
tar -C "/tmp" -czf "$tarball" "hardware-check-${stamp}"
printf '%s\n' "$tarball"
