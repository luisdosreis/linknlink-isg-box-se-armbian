# Home Assistant Container Setup

This repository includes optional Home Assistant setup helpers for the LinknLink
iSG Box SE. It is not Home Assistant OS, does not install Home Assistant
Supervised, does not use the supervised installer, and does not edit
`/etc/os-release`.

The image remains clean: `./build.sh` does not install Docker packages, Docker
services, Home Assistant containers, or `/opt/ha-stack`.

The image adds only lightweight setup helpers:

- `ha-setup`
- `ha-app`
- `ha-stack-check`
- a first-login prompt
- setup templates under `/usr/share/ha-stack`

Docker Engine, Docker Compose, the Home Assistant stack, systemd service, and
`/opt/ha-stack` are provisioned only after first boot when the user chooses to
run `ha-setup`.

## Build

Build the image:

```bash
./build.sh
```

The raw image is written under `build/output/images/`. Repack it the same way
as the base image:

```bash
image-tools/repack-afptool-rs.sh
```

## First Boot

Complete the normal Armbian first-login setup first. After Armbian creates the
regular user, timezone, locale, and password changes, the image shows a prompt
explaining the Home Assistant setup and asks whether to run it.

If you answer yes, `ha-setup` installs Docker, creates `/opt/ha-stack`, enables
`ha-stack.service`, pulls the baseline containers, and starts Home Assistant and
Mosquitto.

If you answer no, nothing is provisioned. You can run setup later:

```bash
sudo ha-setup
```

If setup ever needs to create a fallback local user because no regular user
exists, it creates:

```text
user: home
password: assistant
```

Change that password immediately.

## Provisioned Stack

After `ha-setup` runs, files are installed under `/opt/ha-stack`:

```text
/opt/ha-stack/
├── compose.yaml
├── .env
├── .env.example
├── homeassistant/
├── mosquitto/
│   ├── config/
│   ├── data/
│   └── log/
├── zigbee2mqtt/
├── esphome/
├── matter/
├── zwave-js-ui/
└── backups/
```

These services start by default through `ha-stack.service`:

- `homeassistant`
- `mosquitto`

These optional services use Docker Compose profiles:

- `zigbee`: Zigbee2MQTT
- `esphome`: ESPHome dashboard
- `matter`: Python Matter Server
- `zwave`: Z-Wave JS UI

Home Assistant is available at:

```text
http://<device-ip>:8123
```

## Management

Use `ha-app` after setup. State-changing commands require `sudo`:

```bash
ha-app status
ha-app logs
ha-app logs mosquitto
sudo ha-app enable zigbee
sudo ha-app disable zigbee
sudo ha-app restart homeassistant
sudo ha-app update
sudo ha-app backup --safe
```

`backup --safe` is the default. It briefly stops running containers so the
Home Assistant database is captured consistently, then restarts them. Use
`sudo ha-app backup --live` only when avoiding that brief interruption matters
more than database consistency. Backups are written to
`/opt/ha-stack/backups` as `.tar.gz` archives with a SHA-256 digest.

The iSG Box defaults to the low-latency Wi-Fi policy, which disables SeekWave
firmware deep sleep. Check or change it with:

```bash
ha-app wifi-power status
sudo ha-app wifi-power performance
sudo ha-app wifi-power powersave
```

The validation helper checks Docker, Compose, systemd services, DBus, Avahi,
IPv6, cgroups, overlayfs, and USB serial path availability:

```bash
ha-stack-check
```

## MQTT

Mosquitto listens on port `1883` and is enabled by default.

The default config allows anonymous access for first-boot simplicity. For a
production network, enable Mosquitto password authentication and update the
Home Assistant and Zigbee2MQTT MQTT settings accordingly.

To start Mosquitto manually:

```bash
sudo ha-app enable mqtt
```

## Zigbee2MQTT

Find the persistent USB path for a Zigbee dongle:

```bash
ls -l /dev/serial/by-id/
```

Edit `/opt/ha-stack/.env` and set:

```text
ZIGBEE_DEVICE=/dev/serial/by-id/usb-YOUR_ZIGBEE_DONGLE
```

Then enable Zigbee2MQTT:

```bash
sudo ha-app enable zigbee
```

The Zigbee2MQTT frontend is available at:

```text
http://<device-ip>:8080
```

## ESPHome

Enable ESPHome:

```bash
sudo ha-app enable esphome
```

ESPHome uses host networking and stores config under `/opt/ha-stack/esphome`.
Compiling firmware on Cortex-A53 class CPUs can be slow; use another build host
for large projects if needed.

## Matter Server

Enable Matter Server:

```bash
sudo ha-app enable matter
```

Matter requires IPv6, mDNS, and host networking to work correctly. The
websocket URL for Home Assistant is:

```text
ws://127.0.0.1:5580/ws
```

## Z-Wave JS UI

Find the persistent USB path for a Z-Wave dongle:

```bash
ls -l /dev/serial/by-id/
```

Edit `/opt/ha-stack/.env` and set:

```text
ZWAVE_DEVICE=/dev/serial/by-id/usb-YOUR_ZWAVE_DONGLE
ZWAVE_SESSION_SECRET=replace-this-with-random-text
```

Then enable Z-Wave JS UI:

```bash
sudo ha-app enable zwave
```

The Z-Wave JS UI web interface is available at:

```text
http://<device-ip>:8091
```

The websocket URL for Home Assistant is:

```text
ws://127.0.0.1:3000
```

## Notes

The RK3528 with 4 GB RAM is suitable for Home Assistant, MQTT, Zigbee2MQTT,
ESPHome dashboard, Matter Server, and Z-Wave JS UI.

Keep the system lightweight. Do not enable heavy services such as Frigate,
local AI, local voice pipelines, InfluxDB, Grafana, or MariaDB by default.

Use Ethernet where possible. Use persistent USB paths from
`/dev/serial/by-id/`, not `/dev/ttyUSB0`, for long-term radio configuration.
