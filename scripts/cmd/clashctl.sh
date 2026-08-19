#!/usr/bin/env bash

CLASHCTL_INSTALL_MODE=${CLASHCTL_INSTALL_MODE:-user}
if [ "${CLASHCTL_INSTALL_MODE}" = system ]; then
    CLASHCTL_ROOT=${CLASHCTL_ROOT:-/usr/local/lib/clashctl}
else
    CLASHCTL_ROOT=${CLASHCTL_HOME}
fi

. "${CLASHCTL_ROOT}/.env"

for lib_file in "${CLASHCTL_ROOT}"/scripts/lib/*.sh; do
    # shellcheck disable=SC1090
    . "${lib_file}"
done

for cmd_file in "${CLASHCTL_ROOT}"/scripts/cmd/*.sh; do
    case "${cmd_file}" in *clashctl.*) continue ;; esac
    # shellcheck disable=SC1090
    . "${cmd_file}"
done

clashctl() {
    local sub_cmd
    sub_cmd=${1:-help}
    shift

    case $sub_cmd in
    -h | --help | help) sub_cmd=help ;;
    esac

    case "${sub_cmd}" in
    help | init | doctor | uninit) ;;
    *)
        if [ "${CLASHCTL_INSTALL_MODE}" = system ]; then
            if [ "${sub_cmd}" = migrate ]; then
                _ensure_user_home || return 1
            else
                clashinit >/dev/null || return 1
            fi
        else
            _ensure_user_home || return 1
        fi
        if [ -f "${CLASHCTL_ENV_FILE}" ]; then
            local installed_kernel=${CLASHCTL_KERNEL}
            # shellcheck disable=SC1090
            . "${CLASHCTL_ENV_FILE}"
            [ "${CLASHCTL_INSTALL_MODE}" = system ] && CLASHCTL_KERNEL=${installed_kernel}
        fi
        ;;
    esac

    local target="clash${sub_cmd}"
    declare -F "$target" >&/dev/null || {
        _failcat "Unknown subcommand: $target"
        _failcat "Use 'clashctl help' for usage information."
        return
    }
    "$target" "$@"
}
