#!/usr/bin/env bash

# shellcheck disable=SC2034
CLASHCTL_INSTALL_MODE=${CLASHCTL_INSTALL_MODE:-user}
CLASHCTL_UID=$(id -u)

if [ "${CLASHCTL_INSTALL_MODE}" = system ]; then
    CLASHCTL_ROOT=${CLASHCTL_ROOT:-/usr/local/lib/clashctl}
    CLASHCTL_CONFIG_DIR=${XDG_CONFIG_HOME:-${HOME}/.config}/clashctl
    CLASHCTL_DATA_DIR=${XDG_DATA_HOME:-${HOME}/.local/share}/clashctl
    CLASHCTL_STATE_DIR=${XDG_STATE_HOME:-${HOME}/.local/state}/clashctl
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        CLASHCTL_RUNTIME_DIR=${XDG_RUNTIME_DIR}/clashctl
    elif [ -d "/run/user/${CLASHCTL_UID}" ] && [ -w "/run/user/${CLASHCTL_UID}" ]; then
        CLASHCTL_RUNTIME_DIR=/run/user/${CLASHCTL_UID}/clashctl
    else
        CLASHCTL_RUNTIME_DIR=${TMPDIR:-/tmp}/clashctl-${CLASHCTL_UID}
    fi
    CLASHCTL_STATIC_DIR=${CLASHCTL_ROOT}/resources
    CLASHCTL_ENV_FILE=${CLASHCTL_CONFIG_DIR}/env
    BIN_BASE_DIR=${CLASHCTL_ROOT}/bin
else
    CLASHCTL_ROOT=${CLASHCTL_HOME}
    CLASHCTL_CONFIG_DIR=${CLASHCTL_HOME}/resources
    CLASHCTL_DATA_DIR=${CLASHCTL_HOME}/resources
    CLASHCTL_STATE_DIR=${CLASHCTL_HOME}/resources
    CLASHCTL_RUNTIME_DIR=${CLASHCTL_HOME}/resources
    CLASHCTL_STATIC_DIR=${CLASHCTL_HOME}/resources
    CLASHCTL_ENV_FILE=${CLASHCTL_HOME}/.env
    BIN_BASE_DIR=${CLASHCTL_HOME}/bin
fi

CLASH_RESOURCES_DIR=${CLASHCTL_DATA_DIR}
CLASH_CONFIG_BASE=${CLASHCTL_DATA_DIR}/config.yaml
CLASH_CONFIG_MIXIN=${CLASHCTL_CONFIG_DIR}/mixin.yaml
CLASH_CONFIG_RUNTIME=${CLASHCTL_DATA_DIR}/runtime.yaml
CLASH_CONFIG_TEMP=${CLASHCTL_RUNTIME_DIR}/temp.yaml
# 订阅下载/校验失败时保留的调试产物（稳定路径，便于排障）
CLASH_CONFIG_DEBUG=${CLASHCTL_STATE_DIR}/last-failed.yaml
CLASH_CONFIG_DEBUG_RAW=${CLASHCTL_STATE_DIR}/last-failed.raw

BIN_KERNEL=${BIN_BASE_DIR}/${CLASHCTL_KERNEL}
BIN_YQ="${BIN_BASE_DIR}/yq"
BIN_SUBCONVERTER_DIR="${BIN_BASE_DIR}/subconverter"
BIN_SUBCONVERTER="${BIN_SUBCONVERTER_DIR}/subconverter"
if [ "${CLASHCTL_INSTALL_MODE}" = system ]; then
    BIN_SUBCONVERTER_WORK_DIR=${CLASHCTL_DATA_DIR}/subconverter
    BIN_SUBCONVERTER_CONFIG=${CLASHCTL_CONFIG_DIR}/subconverter/pref.yml
    BIN_SUBCONVERTER_LOG=${CLASHCTL_STATE_DIR}/subconverter.log
else
    BIN_SUBCONVERTER_WORK_DIR=${BIN_SUBCONVERTER_DIR}
    BIN_SUBCONVERTER_CONFIG=${BIN_SUBCONVERTER_DIR}/pref.yml
    BIN_SUBCONVERTER_LOG=${BIN_SUBCONVERTER_DIR}/latest.log
fi

CLASH_PROFILES_DIR=${CLASHCTL_DATA_DIR}/profiles
CLASH_PROFILES_META=${CLASHCTL_DATA_DIR}/profiles.yaml
CLASH_PROFILES_LOG=${CLASHCTL_STATE_DIR}/profiles.log
CLASH_PROFILES_LOCK=${CLASHCTL_RUNTIME_DIR}/profiles.lock

CLASH_PID_FILE=${CLASHCTL_RUNTIME_DIR}/${CLASHCTL_KERNEL}.pid
CLASH_START_LOCK=${CLASHCTL_RUNTIME_DIR}/start.lock
CLASH_SERVICE_LOG=${CLASHCTL_STATE_DIR}/${CLASHCTL_KERNEL}.log
CLASH_SUBCONVERTER_PID_FILE=${CLASHCTL_RUNTIME_DIR}/subconverter.pid

CLASHCTL_CRON_TAG="# clashctl-auto-update"

_is_port_used() {
    local port=${1}
    if command -v ss >/dev/null 2>&1; then
        ss -H -lntu 2>/dev/null | awk -v suffix=":${port}" '$5 ~ suffix "$" { found=1 } END { exit !found }'
        return
    fi
    netstat -lntu 2>/dev/null | awk -v suffix=":${port}" '$4 ~ suffix "$" { found=1 } END { exit !found }'
}

_is_root() {
    [ "$(id -u)" -eq 0 ]
}

_path_owned_by_current_user() {
    [ ! -L "${1}" ] || return 1
    [ -e "${1}" ] || return 0
    [ "$(stat -c %u "${1}" 2>/dev/null)" = "${CLASHCTL_UID}" ]
}

_path_contains_symlink() {
    local path=${1} component prefix=/ remainder=${1#/}
    case "${path}" in
    /*) ;;
    *) return 0 ;;
    esac
    while [ -n "${remainder}" ]; do
        component=${remainder%%/*}
        [ "${remainder}" = "${component}" ] && remainder= || remainder=${remainder#*/}
        prefix="${prefix%/}/${component}"
        [ ! -L "${prefix}" ] || return 0
    done
    return 1
}

_path_safe_for_user_cleanup() {
    local path=${1} current parent owner mode
    [ -n "${path}" ] || return 1
    case "${path}" in
    *'//'|*/../*|*/..|*/./*|*/.) return 1 ;;
    esac
    _path_contains_symlink "${path}" && return 1

    current=${path}
    while [ ! -e "${current}" ]; do
        parent=${current%/*}
        [ "${parent}" != "${current}" ] || return 1
        [ -n "${parent}" ] || parent=/
        current=${parent}
    done
    _path_contains_symlink "${current}" && return 1
    owner=$(stat -c %u "${current}" 2>/dev/null) || return 1
    [ "${owner}" = "${CLASHCTL_UID}" ] && return 0

    mode=$(stat -c %a "${current}" 2>/dev/null) || return 1
    (( 8#${mode} & 01000 )) && (( 8#${mode} & 0002 ))
}

_install_private_file() {
    local source=${1}
    local target=${2}
    [ -e "${target}" ] && return 0
    /usr/bin/install -m 600 "${source}" "${target}"
}

_link_static_resource() {
    local name=${1}
    local source=${CLASHCTL_STATIC_DIR}/${name}
    local target=${CLASHCTL_DATA_DIR}/${name}
    [ -e "${source}" ] || return 0
    [ -e "${target}" ] && [ ! -L "${target}" ] && return 0
    ln -snf "${source}" "${target}"
}

_initialize_subconverter_workdir() {
    [ "${CLASHCTL_INSTALL_MODE}" = system ] || return 0
    /usr/bin/install -d -m 700 "${BIN_SUBCONVERTER_WORK_DIR}"
    local item name
    for item in "${BIN_SUBCONVERTER_DIR}"/*; do
        [ -e "${item}" ] || continue
        name=${item##*/}
        case "${name}" in
        subconverter | pref.yml | pref.example.yml | latest.log) continue ;;
        esac
        ln -snf "${item}" "${BIN_SUBCONVERTER_WORK_DIR}/${name}" || return 1
    done
    ln -snf "${BIN_SUBCONVERTER_CONFIG}" "${BIN_SUBCONVERTER_WORK_DIR}/pref.yml"
}

_ensure_user_home() {
    [ "${CLASHCTL_INSTALL_MODE}" = system ] || return 0
    (
        umask 077
        _ensure_user_home_locked
    )
}

_ensure_user_home_locked() {
    local directory
    for directory in "${CLASHCTL_CONFIG_DIR}" "${CLASHCTL_DATA_DIR}" \
        "${CLASHCTL_STATE_DIR}" "${CLASHCTL_RUNTIME_DIR}" \
        "${CLASH_PROFILES_DIR}" "${CLASHCTL_CONFIG_DIR}/subconverter"; do
        _path_owned_by_current_user "${directory}" || {
            _errorcat "不安全的用户目录：${directory}"
            return 1
        }
        /usr/bin/install -d -m 700 "${directory}" || return 1
    done

    _install_private_file "${CLASHCTL_ROOT}/.env" "${CLASHCTL_ENV_FILE}" || return 1
    _install_private_file "${CLASHCTL_STATIC_DIR}/mixin.yaml" "${CLASH_CONFIG_MIXIN}" || return 1
    _install_private_file "${CLASHCTL_STATIC_DIR}/profiles.yaml" "${CLASH_PROFILES_META}" || return 1
    _install_private_file "${BIN_SUBCONVERTER_DIR}/pref.example.yml" "${BIN_SUBCONVERTER_CONFIG}" || return 1
    [ -e "${CLASH_CONFIG_BASE}" ] || /usr/bin/install -m 600 /dev/null "${CLASH_CONFIG_BASE}"
    chmod 600 "${CLASHCTL_ENV_FILE}" "${CLASH_CONFIG_MIXIN}" "${CLASH_PROFILES_META}" \
        "${BIN_SUBCONVERTER_CONFIG}" "${CLASH_CONFIG_BASE}" 2>/dev/null || return 1

    _link_static_resource Country.mmdb
    _link_static_resource geosite.dat
    _link_static_resource dist
    _initialize_subconverter_workdir
}

_get_random_port() {
    local fail_count=0
    while [ "$fail_count" -lt 100 ]; do
        local random_port
        random_port=$(shuf -i 1024-65535 -n 1)
        ! _is_port_used "$random_port" && {
            printf '%s\n' "$random_port"
            return 0
        }
        fail_count=$((fail_count + 1))
    done
    _errorcat "未找到可用的代理端口"
}

_get_local_ip() {
    local local_ip
    local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    [ -z "$local_ip" ] && local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    printf '%s\n' "$local_ip"
}

_get_random_val() {
    local length=6
    [ "${CLASHCTL_INSTALL_MODE}" = system ] && length=32
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "${length}"
}

_color_log() {
    local color="$1"
    local msg="$2"

    # 输出目标非终端（cron / 管道 / 重定向）时不加颜色码，避免污染日志与 cron 邮件。
    # fd1 已随调用方的 >&2 重定向，故此判断对 _okcat 与 _failcat/_errorcat 均成立。
    [ -t 1 ] || {
        printf '%s\n' "$msg"
        return
    }

    local hex="${color#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))

    local color_code="\033[38;2;${r};${g};${b}m"
    local reset_code="\033[0m"

    printf "%b%s%b\n" "$color_code" "$msg" "$reset_code"
}

_okcat() {
    local color=#c8d6e5
    local emoji=😼
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _color_log "$color" "$msg"
    return 0
}

_failcat() {
    local color=#fd79a8
    local emoji=😾
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _color_log "$color" "$msg" >&2
    return 1
}

_errorcat() {
    [ $# -gt 0 ] && {
        local color=#f92f60
        local emoji=📢
        [ $# -gt 1 ] && emoji=$1 && shift
        local msg="${emoji} $1"
        _color_log "$color" "$msg" >&2
    }
    return 1
}

# 估算字符串终端显示宽度：CJK/emoji 计 2 列，旗帜按对各计 1（合 2），
# VS16(FE0F) 把前一字符提升为宽。依赖 UTF-8 locale 下的逐字符索引。
_dispwidth() {
    local s=$1 w=0 i c cp
    for ((i = 0; i < ${#s}; i++)); do
        c=${s:i:1}
        printf -v cp '%d' "'$c"
        if ((cp == 0xFE0F)); then
            ((w += 1)) # 变体选择符：补足前一字符到宽
        elif ((cp >= 0x1100 && cp <= 0x115F)) ||
            ((cp >= 0x2E80 && cp <= 0xA4CF)) ||
            ((cp >= 0xAC00 && cp <= 0xD7A3)) ||
            ((cp >= 0xF900 && cp <= 0xFAFF)) ||
            ((cp >= 0xFE30 && cp <= 0xFE4F)) ||
            ((cp >= 0xFF00 && cp <= 0xFF60)) ||
            ((cp >= 0xFFE0 && cp <= 0xFFE6)) ||
            ((cp >= 0x1F300 && cp <= 0x1FAFF)) ||
            ((cp >= 0x20000 && cp <= 0x3FFFD)); then
            ((w += 2))
        else
            ((w += 1))
        fi
    done
    printf '%d' "$w"
}

# 按显示宽度右侧补空格，使字符串占满 target 列
_pad() {
    local s=$1 target=$2 w pad
    w=$(_dispwidth "$s")
    pad=$((target - w))
    ((pad < 0)) && pad=0
    printf '%s%*s' "$s" "$pad" ''
}

_set_env() {
    local key=${1}
    local value=${2}
    local env_path=${CLASHCTL_ENV_FILE}

    grep -qE "^${key}=" "$env_path" && {
        value=${value//\\/\\\\}
        value=${value//&/\\&}
        value=${value//|/\\|}
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_path"
        return $?
    }
    printf '%s=%s\n' "$key" "$value" >>"$env_path"
}
