#!/usr/bin/env bash

_ensure_system_shell_hook() {
    [ "${CLASHCTL_INSTALL_MODE}" = system ] || return 0

    local hook=${CLASHCTL_SYSTEM_SHARE_DIR}/shell/clashctl.sh
    [ -r "${hook}" ] || return 0

    local shell_name rc source_line
    shell_name=${SHELL##*/}
    case "${shell_name}" in
    bash) rc=${HOME}/.bashrc ;;
    zsh) rc=${HOME}/.zshrc ;;
    *) return 0 ;;
    esac

    _path_owned_by_current_user "${rc}" || return 1
    [ -e "${rc}" ] || /usr/bin/install -m 600 /dev/null "${rc}" || return 1
    source_line=". ${hook}"
    grep -Fqx -- "${source_line}" "${rc}" 2>/dev/null || {
        [ ! -s "${rc}" ] || [ "$(tail -c 1 -- "${rc}" | wc -l)" -gt 0 ] || printf '\n' >>"${rc}"
        printf '%s\n' "${source_line}" >>"${rc}" || return 1
    }
    CLASHCTL_SHELL_HOOK_RC=${rc}
}

clashinit() {
    [ "${CLASHCTL_INSTALL_MODE}" = system ] || {
        _okcat "当前 user 安装已初始化：${CLASHCTL_HOME}"
        return 0
    }

    _ensure_user_home || return 1
    _ensure_system_shell_hook || return 1
    [ -n "${CLASHCTL_SHELL_HOOK_RC:-}" ] &&
        _okcat "已写入 shell hook；当前终端请执行：source ${CLASHCTL_SHELL_HOOK_RC}"

    if [ -s "${CLASH_CONFIG_RUNTIME}" ] &&
        "${BIN_YQ}" -e '
            ."allow-lan" == false and
            ."bind-address" == "127.0.0.1" and
            (."external-controller" | test("^0\\.0\\.0\\.0:")) and
            ((.secret // "") | length > 0) and
            ((."mixed-port" // .port // ."socks-port" // 0) > 0) and
            (.tun.enable != true)
        ' "${CLASH_CONFIG_RUNTIME}" >/dev/null 2>&1; then
        chmod 600 "${CLASH_CONFIG_RUNTIME}" "${CLASH_CONFIG_MIXIN}" 2>/dev/null
        if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
            systemctl --user daemon-reload >/dev/null 2>&1 || true
        fi
        _okcat "用户环境已初始化：${CLASHCTL_DATA_DIR}"
        return 0
    fi

    local mixed_port controller_port secret
    mixed_port=$("${BIN_YQ}" '.mixed-port // 7890' "${CLASH_CONFIG_MIXIN}")
    if _is_port_used "${mixed_port}"; then
        mixed_port=$(_get_random_port) || return 1
    fi

    controller_port=$("${BIN_YQ}" '.external-controller // "127.0.0.1:9090" | split(":")[-1]' "${CLASH_CONFIG_MIXIN}")
    if [ "${controller_port}" = "${mixed_port}" ] || _is_port_used "${controller_port}"; then
        controller_port=$(_get_random_port) || return 1
        while [ "${controller_port}" = "${mixed_port}" ]; do
            controller_port=$(_get_random_port) || return 1
        done
    fi

    secret=$("${BIN_YQ}" '.secret // ""' "${CLASH_CONFIG_MIXIN}")
    [ -n "${secret}" ] || secret=$(_get_random_val)
    MIXED_PORT=${mixed_port} CONTROLLER_ADDR="0.0.0.0:${controller_port}" SECRET=${secret} \
        "${BIN_YQ}" -i '
            ."mixed-port" = env(MIXED_PORT) |
            ."mixed-port" = (."mixed-port" | tonumber) |
            ."external-controller" = strenv(CONTROLLER_ADDR) |
            ."allow-lan" = false |
            ."bind-address" = "127.0.0.1" |
            .secret = strenv(SECRET) |
            .tun.enable = false
        ' "${CLASH_CONFIG_MIXIN}" || return 1

    _merge_config || return 1
    chmod 600 "${CLASH_CONFIG_RUNTIME}" "${CLASH_CONFIG_MIXIN}" 2>/dev/null
    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
    _okcat "用户环境已初始化：${CLASHCTL_DATA_DIR}"
}
