#!/usr/bin/env bash

clashmigrate() {
    [ "${CLASHCTL_INSTALL_MODE}" = system ] || {
        _errorcat 'migrate 仅用于迁移到 system 安装模式'
        return 1
    }
    local legacy_home=${CLASHCTL_LEGACY_HOME:-${HOME}/Programs/clashctl}
    local legacy_resources=${legacy_home}/resources
    [ -d "${legacy_resources}" ] || {
        _errorcat "未找到旧安装数据：${legacy_resources}"
        return 1
    }
    service_is_active >/dev/null 2>&1 && {
        _errorcat '迁移前请先执行 clashctl off'
        return 1
    }
    local profile_count
    profile_count=$("${BIN_YQ}" '.profiles // [] | length' "${CLASH_PROFILES_META}" 2>/dev/null) || return 1
    [ "${profile_count}" -eq 0 ] || {
        _errorcat '当前用户目录已经包含订阅，拒绝覆盖'
        return 1
    }

    _ensure_user_home || return 1
    local name
    for name in config.yaml runtime.yaml profiles.yaml; do
        [ -f "${legacy_resources}/${name}" ] || continue
        /usr/bin/install -m 600 "${legacy_resources}/${name}" "${CLASHCTL_DATA_DIR}/${name}" || return 1
    done
    if [ -d "${legacy_resources}/profiles" ]; then
        /bin/cp -a "${legacy_resources}/profiles/." "${CLASH_PROFILES_DIR}/" || return 1
        chmod -R go-rwx "${CLASH_PROFILES_DIR}"
        PROFILES_DIR=${CLASH_PROFILES_DIR} "${BIN_YQ}" -i \
            '(.profiles[]? | .path) |= strenv(PROFILES_DIR) + "/" + (. | split("/") | .[-1])' \
            "${CLASH_PROFILES_META}" || return 1
    fi
    if [ -f "${legacy_resources}/mixin.yaml" ]; then
        /usr/bin/install -m 600 "${legacy_resources}/mixin.yaml" "${CLASH_CONFIG_MIXIN}" || return 1
    fi

    local runtime_controller mixin_controller controller_port secret
    runtime_controller=$("${BIN_YQ}" '.external-controller // ""' "${CLASH_CONFIG_RUNTIME}" 2>/dev/null) || return 1
    mixin_controller=$("${BIN_YQ}" '.external-controller // ""' "${CLASH_CONFIG_MIXIN}" 2>/dev/null) || return 1
    controller_port=${runtime_controller##*:}
    [ -n "${controller_port}" ] || controller_port=${mixin_controller##*:}
    if ! [[ ${controller_port} =~ ^[0-9]+$ ]] ||
        ((10#${controller_port} < 1 || 10#${controller_port} > 65535)); then
        controller_port=9090
    fi

    secret=$("${BIN_YQ}" '.secret // ""' "${CLASH_CONFIG_RUNTIME}" 2>/dev/null) || return 1
    [ -n "${secret}" ] || secret=$("${BIN_YQ}" '.secret // ""' "${CLASH_CONFIG_MIXIN}" 2>/dev/null) || return 1
    [ -n "${secret}" ] || secret=$(_get_random_val) || return 1

    # system 模式必须恢复安全监听策略和禁用 TUN。
    CONTROLLER_ADDR="127.0.0.1:${controller_port}" SECRET="${secret}" \
        "${BIN_YQ}" -i '
        ."external-controller" = strenv(CONTROLLER_ADDR) |
        .secret = strenv(SECRET) |
        ."allow-lan" = false |
        ."bind-address" = "127.0.0.1" |
        .tun.enable = false
    ' "${CLASH_CONFIG_MIXIN}" || return 1
    clashinit >/dev/null || return 1
    _valid_config "${CLASH_CONFIG_RUNTIME}" || return 1
    _okcat "迁移完成；旧目录已保留：${legacy_home}"
}
