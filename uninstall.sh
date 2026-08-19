#!/usr/bin/env bash

CLASHCTL_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CLASHCTL_INSTALL_MODE=${CLASHCTL_INSTALL_MODE:-user}
uninstall_arg_index=1
while [ "${uninstall_arg_index}" -le "${#}" ]; do
    uninstall_arg=${!uninstall_arg_index}
    case "${uninstall_arg}" in
    --system)
        CLASHCTL_INSTALL_MODE=system
        ;;
    --prefix=*)
        CLASHCTL_ROOT=${uninstall_arg#*=}
        ;;
    --prefix)
        uninstall_arg_index=$((uninstall_arg_index + 1))
        [ "${uninstall_arg_index}" -le "${#}" ] || {
            printf '%s\n' '错误：--prefix 需要一个目录参数' >&2
            exit 1
        }
        CLASHCTL_ROOT=${!uninstall_arg_index}
        ;;
    esac
    uninstall_arg_index=$((uninstall_arg_index + 1))
done
export CLASHCTL_INSTALL_MODE
. "$CLASHCTL_SRC/scripts/preflight.sh"
. "$CLASHCTL_SRC/scripts/cmd/off.sh"

if [ "${CLASHCTL_INSTALL_MODE}" = system ]; then
    _is_root || _errorcat 'system 卸载必须以 root 执行' || exit 1
    if [ "${CLASHCTL_ROOT}" = /usr/local/lib/clashctl ] &&
        [ ! -e "${CLASHCTL_ROOT}/.clashctl-system" ]; then
        _validate_system_root true || exit 1
    else
        _validate_system_root || exit 1
    fi
    [ -f "${CLASHCTL_ROOT}/.clashctl-system" ] || {
        [ "${CLASHCTL_ROOT}" = /usr/local/lib/clashctl ] || {
            _errorcat "未找到受 clashctl 管理的 system 安装：${CLASHCTL_ROOT}"
            exit 1
        }
    }
    active_uids=()
    expected_kernel_exe=$(readlink -f -- "${BIN_KERNEL}" 2>/dev/null || printf '%s' "${BIN_KERNEL}")
    for proc_dir in /proc/[0-9]*; do
        proc_exe=$(readlink "${proc_dir}/exe" 2>/dev/null) || continue
        case "${proc_exe}" in
        "${expected_kernel_exe}" | "${expected_kernel_exe} (deleted)") ;;
        *) continue ;;
        esac
        active_uids+=("$(awk '/^Uid:/{print $2}' "${proc_dir}/status" 2>/dev/null)")
    done
    [ "${#active_uids[@]}" -eq 0 ] || {
        _errorcat "仍有用户实例运行，拒绝卸载；UID：${active_uids[*]}"
        exit 1
    }
    system_wrapper=${CLASHCTL_SYSTEM_BIN_DIR}/clashctl
    wrapper_target=
    if [ -L "${system_wrapper}" ]; then
        wrapper_target=$(readlink -f -- "${system_wrapper}" 2>/dev/null || true)
    fi
    /usr/bin/rm -rf -- "${CLASHCTL_ROOT}"

    if [ -L "${system_wrapper}" ]; then
        [ "${wrapper_target}" = "${CLASHCTL_ROOT}/bin/clashctl" ] &&
            /usr/bin/rm -f -- "${system_wrapper}"
    elif [ "${CLASHCTL_ROOT}" = /usr/local/lib/clashctl ]; then
        /usr/bin/rm -f -- "${system_wrapper}"
    fi
    if grep -Fq "ExecStart=${CLASHCTL_ROOT}/scripts/run-mihomo" \
        "${CLASHCTL_SYSTEM_USER_UNIT_DIR}/clashctl.service" 2>/dev/null; then
        /usr/bin/rm -f -- "${CLASHCTL_SYSTEM_USER_UNIT_DIR}/clashctl.service"
    fi
    /usr/bin/rm -f -- "${CLASHCTL_SYSTEM_PROFILE_FILE}" \
        /etc/fish/conf.d/clashctl.fish
    /usr/bin/rm -rf -- "${CLASHCTL_SYSTEM_SHARE_DIR}"
    _okcat '✨' 'system 程序已卸载；各用户数据保持不变'
    exit 0
fi

! _is_root && tunstatus >&/dev/null && {
    _errorcat "请先关闭 Tun 模式"
    exit
}
uninstall_service

# 清理旧版 sub update --auto 遗留的自管 crontab
command -v crontab >&/dev/null && {
    crontab -l 2>/dev/null | grep -Fv "$CLASHCTL_CRON_TAG" | crontab -
}

/usr/bin/rm -rf "$CLASHCTL_HOME"
revoke_rc

_okcat '✨' "已卸载，相关配置已清除"
[ -n "$http_proxy" ] && _failcat '❗' "当前终端仍残留代理环境变量，重开终端即可清除"
