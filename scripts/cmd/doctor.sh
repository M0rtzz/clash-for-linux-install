#!/usr/bin/env bash

clashdoctor() {
    local initialized=no pid=- mixed_port=- controller=- active=- subscription=-
    [ -f "${CLASH_CONFIG_RUNTIME}" ] && initialized=yes
    if [ "${initialized}" = yes ]; then
        mixed_port=$("${BIN_YQ}" '.mixed-port // .port // .socks-port // "-"' "${CLASH_CONFIG_RUNTIME}" 2>/dev/null)
        controller=$("${BIN_YQ}" '.external-controller // "-"' "${CLASH_CONFIG_RUNTIME}" 2>/dev/null)
    fi
    service_is_active >/dev/null 2>&1 && active=yes || active=no
    detect_service_manager
    # shellcheck disable=SC2154 # service_manager is initialized by detect_service_manager.
    if [ "${service_manager}" = systemd-user ]; then
        pid=$(systemctl --user show -p MainPID --value clashctl.service 2>/dev/null)
        [[ ${pid} =~ ^[1-9][0-9]*$ ]] || pid=-
    elif service_valid_pid >/dev/null 2>&1; then
        pid=${SERVICE_VALID_PID}
    fi
    [ -f "${CLASH_PROFILES_META}" ] &&
        subscription=$("${BIN_YQ}" '.use // "-"' "${CLASH_PROFILES_META}" 2>/dev/null)

    printf '%-18s %s\n' \
        'User:' "$(id -un)" \
        'UID:' "${CLASHCTL_UID}" \
        'Mode:' "${CLASHCTL_INSTALL_MODE}" \
        'Initialized:' "${initialized}" \
        'Install:' "${CLASHCTL_ROOT}" \
        'Config:' "${CLASHCTL_CONFIG_DIR}" \
        'Data:' "${CLASHCTL_DATA_DIR}" \
        'State:' "${CLASHCTL_STATE_DIR}" \
        'Runtime:' "${CLASHCTL_RUNTIME_DIR}" \
        'Service:' "${service_manager:-unknown}" \
        'Active:' "${active}" \
        'PID:' "${pid}" \
        'Mixed port:' "${mixed_port}" \
        'Controller:' "${controller}" \
        'Subscription:' "${subscription}"
}
