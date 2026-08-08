#!/bin/sh

[ "$(id -u)" -eq 0 ] || return 0
[ -n "$(tty 2>/dev/null)" ] || return 0
[ -x /usr/local/bin/ha-setup ] || return 0
[ ! -e /root/.not_logged_in_yet ] || return 0
[ ! -e /var/lib/ha-stack/setup.done ] || return 0
[ ! -e /var/lib/ha-stack/setup-prompted ] || return 0

mkdir -p /var/lib/ha-stack

printf '\n'
printf 'Home Assistant Container setup is available for this image.\n'
printf 'It will install Docker Engine, Docker Compose, Home Assistant Container,\n'
printf 'Mosquitto, and optional companion-service templates under /opt/ha-stack.\n'
printf '\n'
printf 'You can run it later with: sudo ha-setup\n'
printf 'Run Home Assistant setup now? [y/N] '

read answer
case "$answer" in
    y|Y|yes|YES)
        /usr/local/bin/ha-setup
        ;;
    *)
        date -u +%Y-%m-%dT%H:%M:%SZ >/var/lib/ha-stack/setup-prompted
        printf 'Skipped. Run sudo ha-setup when you are ready.\n'
        ;;
esac
