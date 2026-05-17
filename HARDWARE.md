# Hardware

## Board Hardware

The port targets the LinknLink iSG Box SE variant identified as a Rockchip
RK3528 board with a SeekWave SWT6621S SDIO Wi-Fi/Bluetooth combo.

- SoC: Rockchip RK3528.
- CPU: quad-core Arm, product specs list up to 2.0 GHz.
- RAM: 4 GB.
- Internal storage: 64 GB eMMC.
- Power input: DC 5 V / 2 A, 5.5 x 2.1 mm barrel jack.
- External ports: DC power, AV/headphone jack, HDMI, RJ45 Ethernet, USB1, USB2.
- Ethernet: 100M RJ45, wired to RK3528 `gmac0` RMII.
- Wireless: SeekWave SWT6621S SDIO Wi-Fi/Bluetooth combo.
- Product wireless spec: 2.4 GHz / 5 GHz Wi-Fi, Bluetooth 5.4.

Device-tree aliases use kernel binding names, such as `ethernet0` and `mmc0`.
Linux userspace names use the normal names exposed by the kernel and udev, such
as `eth0`, `wlan0`, `hci0`, and `HDMI-A-1`. The image adds
`net.ifnames=0 biosdevname=0` so Ethernet and Wi-Fi use classic interface
names.

| Hardware | Device tree | Linux name | Status |
| --- | --- | --- | --- |
| eMMC | `mmc0 = &sdhci` | usually `/dev/mmcblk0` | Working - internal boot storage |
| SDIO Wi-Fi/Bluetooth host | `mmc1 = &sdio0` | MMC host `mmc1` | Working |
| Ethernet | `ethernet0 = &gmac0` | `eth0` | Working |
| Wi-Fi | SDIO child device | `wlan0` | Working |
| Bluetooth | `seekwcn-boot`, `skwbt` | `hci0` | Working |
| Serial debug console | `serial2 = &uart2` | `ttyS2` | Working - 1,500,000 baud 8N1 |
| HDMI video | `&hdmi`, `&hdmiphy` | `HDMI-A-1` | Working |
| HDMI audio | `hdmi-sound` | ALSA `rockchip,hdmi` | Working |
| Analog audio / AV jack | `acodec-sound`, `&acodec`, `&sai2` | ALSA `rk3528-acodec` | Working |
| USB host | RK3528 USB host nodes | `usb1`, `usb2`, etc. | Root hubs enumerate |
| Loader button / ADC key | `adc-keys` | `/dev/input/event*` | Exposed as ADC key input; also used for Loader mode |
| Power LED | Not controlled by Linux | red LED | Fixed power indicator |
| Blue user LED | GPIO4 PC1 | `/sys/class/leds/blue:user` | Working |

## Supported External Hardware

| Hardware | USB ID | Linux driver | Linux name | Status |
| --- | --- | --- | --- | --- |
| LinknLink RD1100+ USB Zigbee 3.0 dongle | `1a86:7523` | `ch341`, `usbserial` | `/dev/ttyUSB0`, `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0` | Working - USB serial adapter detected |
| SONOFF Zigbee 3.0 USB Dongle Plus V2 / ZBDongle-E | `1a86:55d4` | `cdc_acm` | `/dev/ttyACM0`, `/dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_<serial>-if00` | Working - USB ACM serial adapter detected |

Home Assistant ZHA serial paths:

```text
LinknLink RD1100+:
  /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0

SONOFF ZBDongle-E:
  /dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_<serial>-if00
```

Zigbee2MQTT serial examples:

```yaml
# LinknLink RD1100+
serial:
  port: /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
  adapter: ember

# SONOFF ZBDongle-E
serial:
  port: /dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_<serial>-if00
  adapter: ember
```
