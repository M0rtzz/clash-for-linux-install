#!/usr/bin/env bash

clashenv() {
    local shell_name=bash
    case "${1:-}" in
    --shell=fish) shell_name=fish ;;
    --shell=bash | --shell=zsh | '') shell_name=bash ;;
    -h | --help)
        printf '%s\n' 'Usage: clashctl env [--shell=bash|zsh|fish]'
        return 0
        ;;
    *)
        _errorcat "未知 env 选项：${1}"
        return 1
        ;;
    esac

    service_is_active >/dev/null 2>&1 || {
        _errorcat "${CLASHCTL_KERNEL} 未运行"
        return 1
    }
    set_system_proxy
    if [ "${shell_name}" = fish ]; then
        _dump_proxy_env_fish
        return 0
    fi

    local name value quoted
    for name in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY; do
        value=${!name}
        printf -v quoted '%q' "${value}"
        printf 'export %s=%s\n' "${name}" "${quoted}"
    done
}
