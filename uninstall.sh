#!/usr/bin/env bash

CLASHCTL_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
for uninstall_arg in "${@}"; do
    [ "${uninstall_arg}" = --system ] && CLASHCTL_INSTALL_MODE=system
done
export CLASHCTL_INSTALL_MODE
. "$CLASHCTL_SRC/scripts/preflight.sh"
. "$CLASHCTL_SRC/scripts/cmd/off.sh"

if [ "${CLASHCTL_INSTALL_MODE}" = system ]; then
    _is_root || _errorcat 'system 卸载必须以 root 执行' || exit 1
    [ "${CLASHCTL_ROOT}" = /usr/local/lib/clashctl ] || {
        _errorcat '拒绝卸载非标准 system 路径'
        exit 1
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
    /usr/bin/rm -rf -- "${CLASHCTL_ROOT}"
    /usr/bin/rm -f -- /usr/local/bin/clashctl /usr/local/lib/systemd/user/clashctl.service \
        /etc/profile.d/clashctl.sh /etc/fish/conf.d/clashctl.fish
    /usr/bin/rm -rf -- /usr/local/share/clashctl
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
