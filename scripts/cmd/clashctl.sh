#!/usr/bin/env bash

if [ -n "${ZSH_VERSION:-}" ]; then
    _clashctl_user_exec() {
        CLASHCTL_INSTALL_MODE=user CLASHCTL_HOME="${CLASHCTL_HOME}" command bash -c \
            '. "${CLASHCTL_HOME}/scripts/cmd/clashctl.sh" && clashctl "${@}"' -- "${@}"
    }

    clashctl() {
        local command_name=${1:-help}
        case "${command_name}" in
        on)
            shift
            case "${1:-}" in
            -s | --service-only | -h | --help)
                _clashctl_user_exec on "${@}"
                ;;
            -e | --env-only)
                _clashctl_user_exec status >/dev/null || return
                eval "$(_clashctl_user_exec env --shell=zsh)" || return
                _clashctl_user_exec on --env-only
                ;;
            *)
                _clashctl_user_exec on --service-only "${@}" || return
                eval "$(_clashctl_user_exec env --shell=zsh)" || return
                _clashctl_user_exec on --env-only
                ;;
            esac
            ;;
        off)
            shift
            case "${1:-}" in
            -s | --service-only | -h | --help)
                _clashctl_user_exec off "${@}"
                ;;
            -e | --env-only)
                unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
                _clashctl_user_exec off --env-only
                ;;
            *)
                _clashctl_user_exec off --service-only "${@}" || return
                unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
                _clashctl_user_exec off --env-only
                ;;
            esac
            ;;
        *)
            _clashctl_user_exec "${@}"
            ;;
        esac
    }

    clashon() { clashctl on "${@}"; }
    clashoff() { clashctl off "${@}"; }
    clashstatus() { clashctl status "${@}"; }
    clashui() { clashctl ui "${@}"; }
    clashsub() { clashctl sub "${@}"; }
    clashnode() { clashctl node "${@}"; }
    clashtun() { clashctl tun "${@}"; }
    clashmixin() { clashctl mixin "${@}"; }
    clashsecret() { clashctl secret "${@}"; }
    clashlog() { clashctl log "${@}"; }
    clashupgrade() { clashctl upgrade "${@}"; }
    clashinit() { clashctl init "${@}"; }
    clashenv() { clashctl env "${@}"; }
    clashdoctor() { clashctl doctor "${@}"; }
    clashmigrate() { clashctl migrate "${@}"; }
    clashuninit() { clashctl uninit "${@}"; }
    clashhelp() { clashctl help "${@}"; }
    return 0
fi

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
    case "${cmd_file##*/}" in clashctl.*) continue ;; esac
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
