function pre_package_kernel_image__build_isg_seekwave_driver() {
	local src_dir="${USERPATCHES_PATH}/drivers/seekwave-swt6621s-recon/sources/seekwave-swt6621s"
	local platform_header_src="${USERPATCHES_PATH}/drivers/seekwave-swt6621s-recon/include/linux/platform_data/skw_platform_data.h"
	local platform_header_dst="${kernel_work_dir}/include/linux/platform_data/skw_platform_data.h"
	local module_dir="${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}/lib/modules/${kernel_version_family}/extra/seekwave"
	local module_arch="${ARCHITECTURE:-${ARCH}}"
	local cross_compile="${KERNEL_COMPILER:-}"
	local wifi_module="${src_dir}/swt6621s_wifi/swt6621s_wifi.ko"
	local bsp_module="${src_dir}/seekwaveplatform_lite/skw_sdio_lite.ko"
	local bt_module="${src_dir}/swtbt4l/skwbt.ko"
	local built_module

	if [[ ! -f "${src_dir}/Makefile" ]]; then
		display_alert "Extension: ${EXTENSION}: missing SWT6621S driver" "${src_dir}" "warn"
		return 0
	fi

	if [[ ! -f "${platform_header_src}" ]]; then
		display_alert "Extension: ${EXTENSION}: missing platform header" "${platform_header_src}" "err"
		exit 1
	fi

	display_alert "Extension: ${EXTENSION}: staging SeekWave platform header" "$(basename "${platform_header_dst}")" "info"
	mkdir -p "$(dirname "${platform_header_dst}")"
	cp "${platform_header_src}" "${platform_header_dst}"

	display_alert "Extension: ${EXTENSION}: building SWT6621S driver" "${kernel_version_family}" "info"
	run_host_command_logged make -C "${kernel_work_dir}" M="${src_dir}" \
		ARCH="${module_arch}" CROSS_COMPILE="${cross_compile}" \
		CONFIG_BT=m CONFIG_BT_RFCOMM=m CONFIG_SKW_BT=m CONFIG_SEEKWAVE_BSP_DRIVERS=m CONFIG_SKW_SDIOHAL=m CONFIG_WLAN_VENDOR_SWT6621S=m CONFIG_SWT6621S_LOG_DEBUG=y \
		clean
	run_host_command_logged make -C "${kernel_work_dir}" M="${src_dir}" \
		ARCH="${module_arch}" CROSS_COMPILE="${cross_compile}" \
		CONFIG_BT=m CONFIG_BT_RFCOMM=m CONFIG_SKW_BT=m CONFIG_SEEKWAVE_BSP_DRIVERS=m CONFIG_SKW_SDIOHAL=m CONFIG_WLAN_VENDOR_SWT6621S=m CONFIG_SWT6621S_LOG_DEBUG=y \
		modules

	if [[ ! -f "${wifi_module}" ]]; then
		display_alert "Extension: ${EXTENSION}: missing built Wi-Fi module" "${wifi_module}" "err"
		exit 1
	fi

	if [[ ! -f "${bsp_module}" ]]; then
		display_alert "Extension: ${EXTENSION}: missing built SDIO module" "${bsp_module}" "err"
		exit 1
	fi

	if [[ ! -f "${bt_module}" ]]; then
		display_alert "Extension: ${EXTENSION}: missing built Bluetooth module" "${bt_module}" "err"
		exit 1
	fi

	if ! strings "${wifi_module}" | grep -q 'swt6621s_dev'; then
		display_alert "Extension: ${EXTENSION}: built stale swt6621s_wifi.ko" "${wifi_module}" "err"
		exit 1
	fi

	if ! strings "${wifi_module}" | grep -q 'SKW_EVENT_SCAN_REPORT'; then
		display_alert "Extension: ${EXTENSION}: built stale swt6621s_wifi.ko" "${wifi_module}" "err"
		exit 1
	fi

	if ! strings "${wifi_module}" | grep -q 'SWT6621S probe: drv_probe enter'; then
		display_alert "Extension: ${EXTENSION}: built stale swt6621s_wifi.ko" "${wifi_module}" "err"
		exit 1
	fi

	if ! strings "${bsp_module}" | grep -q 'skw_sdio_lite'; then
		display_alert "Extension: ${EXTENSION}: built stale skw_sdio_lite.ko" "${bsp_module}" "err"
		exit 1
	fi

	if ! strings "${bsp_module}" | grep -q 'SWT6621S probe: bind wifi pdev_name='; then
		display_alert "Extension: ${EXTENSION}: built stale skw_sdio_lite.ko" "${bsp_module}" "err"
		exit 1
	fi

	if ! strings "${bt_module}" | grep -q 'Seekwave Bluetooth driver ver'; then
		display_alert "Extension: ${EXTENSION}: built stale skwbt.ko" "${bt_module}" "err"
		exit 1
	fi

	if ! strings "${bt_module}" | grep -q 'btseekwave'; then
		display_alert "Extension: ${EXTENSION}: built stale skwbt.ko" "${bt_module}" "err"
		exit 1
	fi

	install -d "${module_dir}"
	find "${module_dir}" -maxdepth 1 -type f \( -name 'skw*.ko' -o -name 'swt*.ko' \) -delete
	install -m 0644 "${wifi_module}" "${module_dir}/"
	install -m 0644 "${bsp_module}" "${module_dir}/"
	install -m 0644 "${bt_module}" "${module_dir}/"

	for built_module in "${module_dir}/swt6621s_wifi.ko" "${module_dir}/skw_sdio_lite.ko" "${module_dir}/skwbt.ko"; do
		[[ -f "${built_module}" ]] || {
			display_alert "Extension: ${EXTENSION}: failed to stage module" "${built_module}" "err"
			exit 1
		}
	done

	if command -v depmod >/dev/null 2>&1; then
		depmod -b "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}" "${kernel_version_family}" || true
	fi
}

function pre_customize_image__enable_isg_seekwave_modules() {
	local modules_load_dir="${SDCARD}/etc/modules-load.d"
	local modules_load_file="${modules_load_dir}/swt6621s-wifi.conf"
	local firmware_dir="${SDCARD}/lib/firmware"
	local seekwave_firmware_dir="${firmware_dir}/seekwave-swt6621s"
	local seekwave_firmware_src="${USERPATCHES_PATH}/firmware/seekwave-swt6621s"
	local firmware_name
	local firmware_path

	display_alert "Extension: ${EXTENSION}: enabling SeekWave autoload" "swt6621s_wifi + skw_sdio_lite + skwbt" "info"
	install -d -m 0755 "${modules_load_dir}"
	cat >"${modules_load_file}" <<'EOF'
skw_sdio_lite
swt6621s_wifi
skwbt
EOF
	chmod 0644 "${modules_load_file}"

	if [[ ! -d "${seekwave_firmware_dir}" && -d "${seekwave_firmware_src}" ]]; then
		install -d -m 0755 "${seekwave_firmware_dir}"
		find "${seekwave_firmware_src}" -maxdepth 1 -type f -exec install -m 0644 {} "${seekwave_firmware_dir}/" \;
	fi

	if [[ -d "${seekwave_firmware_dir}" ]]; then
		install -d -m 0755 "${firmware_dir}" "${seekwave_firmware_dir}"
		for firmware_name in \
			SWT6621S_DRAM_SDIO.bin \
			SWT6621S_IRAM_SDIO.bin \
			SWT6621S_NV_SDIO.bin \
			sv6160lite.nvbin; do
			if [[ -f "${seekwave_firmware_dir}/${firmware_name}" ]]; then
				install -m 0644 "${seekwave_firmware_dir}/${firmware_name}" "${firmware_dir}/${firmware_name}"
			fi
		done
		for firmware_path in \
			"${seekwave_firmware_dir}"/SWT6621S_SEEKWAVE_R*.bin; do
			if [[ -f "${firmware_path}" ]]; then
				install -m 0644 "${firmware_path}" "${firmware_dir}/$(basename "${firmware_path}")"
			fi
		done
	fi
}
