# shellcheck shell=bash

function extension_prepare_config__install_home_assistant_launcher_packages() {
	add_packages_to_image ca-certificates curl git
}

function pre_customize_image__install_home_assistant_launcher() {
	local source_dir="${USERPATCHES_PATH}/flavors/home-assistant/install-home-assistant"
	local destination

	if [[ ! -x "${source_dir}/install.sh" ]]; then
		display_alert "Extension: ${EXTENSION}: missing Home Assistant launcher" "${source_dir}/install.sh" "err"
		exit 1
	fi

	display_alert "Extension: ${EXTENSION}: installing external HA launcher" "root and /etc/skel" "info"
	for destination in \
		"${SDCARD}/root/install-home-assistant" \
		"${SDCARD}/etc/skel/install-home-assistant"; do
		install -d -m 0755 "$destination"
		install -m 0755 "${source_dir}/install.sh" "${destination}/install.sh"
	done
}
