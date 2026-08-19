#!/usr/bin/env bash

clashctl() {
    local command_name=${1:-help}
    case "${command_name}" in
    on)
        shift
        case "${1:-}" in
        -s | --service-only) command clashctl on "${@}" ;;
        -h | --help) command clashctl on "${@}" ;;
        -e | --env-only)
            command clashctl status >/dev/null || return
            eval "$(command clashctl env --shell=bash)"
            ;;
        *)
            command clashctl on --service-only "${@}" || return
            eval "$(command clashctl env --shell=bash)"
            ;;
        esac
        ;;
    off)
        shift
        case "${1:-}" in
        -s | --service-only) command clashctl off "${@}" ;;
        -h | --help) command clashctl off "${@}" ;;
        -e | --env-only) unset_system_proxy_hook ;;
        *)
            command clashctl off --service-only "${@}" || return
            unset_system_proxy_hook
            ;;
        esac
        ;;
    *) command clashctl "${@}" ;;
    esac
}

unset_system_proxy_hook() {
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
}

clashon() { clashctl on "$@"; }
clashoff() { clashctl off "$@"; }
clashstatus() { clashctl status "$@"; }
clashui() { clashctl ui "$@"; }
clashsub() { clashctl sub "$@"; }
clashnode() { clashctl node "$@"; }
clashtun() { clashctl tun "$@"; }
clashmixin() { clashctl mixin "$@"; }
clashsecret() { clashctl secret "$@"; }
clashlog() { clashctl log "$@"; }
clashupgrade() { clashctl upgrade "$@"; }
clashinit() { clashctl init "$@"; }
clashenv() { clashctl env "$@"; }
clashdoctor() { clashctl doctor "$@"; }
clashmigrate() { clashctl migrate "$@"; }
clashuninit() { clashctl uninit "$@"; }
clashhelp() { clashctl help "$@"; }
