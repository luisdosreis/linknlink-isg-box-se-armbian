function extension_prepare_config__isg_fast_kernel_config() {
	display_alert "${EXTENSION}: reducing kernel surface" "drop unused wifi, media, and staging drivers for faster iSG Box SE builds" "warn"
}

function custom_kernel_config__isg_fast_kernel_config() {
	declare -a enable_opts=(
		BACKLIGHT_CLASS_DEVICE
		CFG80211
		CFG80211_WEXT
		MAC80211
		MEDIA_SUPPORT
		MEDIA_CONTROLLER
		VIDEO_DEV
		VIDEO_V4L2_SUBDEV_API
	)
	declare -a module_opts=(
		SEEKWAVE_BSP_DRIVERS
		SEEKWAVE_PLD_RELEASE
		SKW_BSP_BOOT
		SKW_BSP_UCOM
		SKW_SDIOHAL
		WLAN_VENDOR_SEEKWAVE
	)
	declare -a disable_opts=(
		AW_BIND_VERIFY
		AW_WIFI_DEVICE_UWE5622
		RK_WIFI_DEVICE_UWE5621
		RK_WIFI_DEVICE_UWE5622
		SPARD_WLAN_SUPPORT
		SPRDWL_NG
		TTY_OVERY_SDIO
		UNISOC_WIFI_PS
		RC_CORE
		STAGING
		FB_TFT
		ATH10K
		ATH10K_PCI
		ATH10K_AHB
		ATH10K_SDIO
		ATH10K_USB
		ATH11K
		ATH11K_PCI
		AT76C50X_USB
		BRCMSMAC
		BRCMFMAC
		IWLWIFI
		IWLDVM
		IWLMVM
		HOSTAP
		LIBERTAS_THINFIRM
		MWIFIEX
		MWIFIEX_SDIO
		MWIFIEX_USB
		MT7601U
		MT76x0U
		MT76x0E
		MT76x2E
		MT76x2U
		MT7603E
		MT7615E
		MT7663U
		MT7663S
		MT7915E
		RT2X00
		RT2800PCI
		RT2500USB
		RT73USB
		RT2800USB
		RTL8187
		RTL_CARDS
		RTL8723BE
		RTL8192CU
		RTL8XXXU
		RTW88
		RTW88_8822CE
		RTW88_8821CE
		RTL8723DU
		RTL8723DS
		RTL8822BU
		RTL8188EU
		RTL8821CU
		88XXAU
		RTL8192EU
		RTL8189ES
		WL_ROCKCHIP
		WIFI_BUILD_MODULE
		AP6XXX
		BCMDHD_PCIE
		RTL8852BE
		RTL8852BU
		RTL8821CS
		AIC_WLAN_SUPPORT
		AIC8800_WLAN_SUPPORT
		AIC8800_BTLPM_SUPPORT
		USB_NET_RNDIS_WLAN
		WLAN_UWE5621
		WLAN_UWE5622
	)
	declare opt

	kernel_config_modifying_hashes+=("isg-fast-kernel-config-v8")
	[[ -f .config ]] || return 0

	for opt in "${enable_opts[@]}"; do
		opts_y+=("${opt}")
	done

	for opt in "${module_opts[@]}"; do
		opts_m+=("${opt}")
	done

	for opt in "${disable_opts[@]}"; do
		opts_n+=("${opt}")
	done
}
