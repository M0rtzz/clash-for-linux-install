#!/usr/bin/env bash

CLASHCTL_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# valid_env runs before parse_args, so detect system mode and prefix here as well.
CLASHCTL_INSTALL_MODE=${CLASHCTL_INSTALL_MODE:-user}
CLASHCTL_PREFIX_ARG=0
install_arg_index=1
while [ "${install_arg_index}" -le "${#}" ]; do
    install_arg=${!install_arg_index}
    case "${install_arg}" in
    --system)
        CLASHCTL_INSTALL_MODE=system
        ;;
    --prefix=*)
        CLASHCTL_PREFIX_ARG=1
        CLASHCTL_ROOT=${install_arg#*=}
        ;;
    --prefix)
        CLASHCTL_PREFIX_ARG=1
        install_arg_index=$((install_arg_index + 1))
        [ "${install_arg_index}" -le "${#}" ] || {
            printf '%s\n' '错误：--prefix 需要一个目录参数' >&2
            exit 1
        }
        CLASHCTL_ROOT=${!install_arg_index}
        ;;
    esac
    install_arg_index=$((install_arg_index + 1))
done
if [ "${CLASHCTL_INSTALL_MODE}" != system ] && [ "${CLASHCTL_PREFIX_ARG}" -eq 1 ]; then
    printf '%s\n' '错误：--prefix 仅在 --system 模式下有效' >&2
    exit 1
fi
export CLASHCTL_INSTALL_MODE
. "$CLASHCTL_SRC/scripts/preflight.sh"

valid_env
parse_args "$@"

if [ "${CLASHCTL_INSTALL_MODE}" = system ] && [ "${CLASHCTL_KERNEL}" != mihomo ]; then
    _errorcat 'system 安装模式当前仅支持 mihomo 内核'
    exit 1
fi

_okcat "安装内核：$CLASHCTL_KERNEL"
_okcat '📦' "安装路径：${CLASHCTL_ROOT}"

if [ "${CLASHCTL_INSTALL_MODE}" = system ]; then
    install_system_directories
    prepare_zip
    install_system_clashctl
    _okcat '🎉' 'system 安装完成；普通用户可执行 clashctl init'
    exit 0
fi

prepare_zip

install_service
install_clashctl

_merge_config
_detect_proxy_port
clashui
[ -z "$(_get_secret)" ] && clashsecret "$(_get_random_val)" >/dev/null
clashsecret

_valid_config "$CLASH_CONFIG_BASE" && {
    CLASHCTL_SUB_URL="file://$CLASH_CONFIG_BASE"
}
clashsub add --use "$CLASHCTL_SUB_URL"
_okcat '🎉' "请执行 source ~/.bashrc 为当前 SHELL 加载 clashctl 命令"
