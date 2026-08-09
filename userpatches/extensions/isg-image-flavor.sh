# shellcheck shell=bash
# shellcheck disable=SC2154 # Armbian initializes EXTRA_IMAGE_SUFFIXES.

function extension_prepare_config__set_linknlink_image_flavor() {
	case "${LINKNLINK_IMAGE_FLAVOR:-}" in
		server|desktop)
			EXTRA_IMAGE_SUFFIXES+=("-${LINKNLINK_IMAGE_FLAVOR}")
			;;
		*)
			display_alert "Extension: ${EXTENSION}: invalid image flavor" "${LINKNLINK_IMAGE_FLAVOR:-unset}" "err"
			exit 1
			;;
	esac
}
