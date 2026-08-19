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
    [ "$(_sub_count)" -eq 0 ] || {
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
    fi
    [ -f "${legacy_resources}/mixin.yaml" ] &&
        /usr/bin/install -m 600 "${legacy_resources}/mixin.yaml" "${CLASH_CONFIG_MIXIN}"

    # system 模式必须恢复安全监听策略和禁用 TUN。
    "${BIN_YQ}" -i '
        ."allow-lan" = false |
        ."bind-address" = "127.0.0.1" |
        .tun.enable = false
    ' "${CLASH_CONFIG_MIXIN}" || return 1
    clashinit >/dev/null || return 1
    _valid_config "${CLASH_CONFIG_RUNTIME}" || return 1
    _okcat "迁移完成；旧目录已保留：${legacy_home}"
}
