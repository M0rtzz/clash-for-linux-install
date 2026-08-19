#!/usr/bin/env bash

clashuninit() {
    [ "${CLASHCTL_INSTALL_MODE}" = system ] || {
        _errorcat 'user 安装请继续使用 uninstall.sh'
        return 1
    }
    local assume_yes=false
    case "${1:-}" in
    -y | --yes) assume_yes=true ;;
    -h | --help)
        printf '%s\n' 'Usage: clashctl uninit [-y|--yes]'
        return 0
        ;;
    '') ;;
    *)
        _errorcat "未知 uninit 选项：${1}"
        return 1
        ;;
    esac

    if [ "${assume_yes}" = false ]; then
        [ -t 0 ] || {
            _errorcat '非交互环境请使用 clashctl uninit --yes'
            return 1
        }
        local answer
        read -r -p '将删除当前用户的 clashctl 配置、订阅和日志，继续？[y/N] ' answer
        [[ ${answer} =~ ^[Yy]$ ]] || return 0
    fi

    service_stop >/dev/null 2>&1 || true
    local target
    for target in "${CLASHCTL_CONFIG_DIR}" "${CLASHCTL_DATA_DIR}" \
        "${CLASHCTL_STATE_DIR}"; do
        if [ -z "${target}" ] || [ "${target##*/}" != clashctl ]; then
            _errorcat "拒绝删除不安全路径：${target}"
            return 1
        fi
    done
    case "${CLASHCTL_RUNTIME_DIR##*/}" in
    clashctl | clashctl-"${CLASHCTL_UID}") ;;
    *)
        _errorcat "拒绝删除不安全路径：${CLASHCTL_RUNTIME_DIR}"
        return 1
        ;;
    esac
    /usr/bin/rm -rf -- "${CLASHCTL_CONFIG_DIR}" "${CLASHCTL_DATA_DIR}" \
        "${CLASHCTL_STATE_DIR}" "${CLASHCTL_RUNTIME_DIR}"
    _okcat '当前用户的 clashctl 数据已清理'
}
