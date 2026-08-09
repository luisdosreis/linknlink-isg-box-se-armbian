# shellcheck shell=bash

function host_pre_docker_launch__isg_build_network_defaults() {
	if [[ "${DOCKER_ARMBIAN_HOST_OS_UNAME:-}" == "Linux" ]]; then
		display_alert "Extension: ${EXTENSION}: using host networking for Docker build" "--network=host" "info"
		DOCKER_EXTRA_ARGS+=("--network=host")
	fi

	if [[ -n "${ISG_DOCKER_DNS:-}" ]]; then
		local dns_server
		for dns_server in ${ISG_DOCKER_DNS}; do
			display_alert "Extension: ${EXTENSION}: adding Docker DNS server" "${dns_server}" "info"
			DOCKER_EXTRA_ARGS+=("--dns" "${dns_server}")
		done
	fi
}
