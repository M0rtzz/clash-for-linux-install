#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
YQ_ARCHIVE=${REPOSITORY_ROOT}/archives/yq_linux_amd64.tar.gz
SUBCONVERTER_ARCHIVE=${REPOSITORY_ROOT}/archives/subconverter_linux64.tar.gz
if [ ! -f "${YQ_ARCHIVE}" ] || [ ! -f "${SUBCONVERTER_ARCHIVE}" ]; then
    printf '%s\n' 'SKIP: local dependency archives are unavailable'
    exit 0
fi

TEST_ROOT=$(mktemp -d)
trap '/usr/bin/rm -rf -- "${TEST_ROOT}"' EXIT
INSTALL_ROOT=${TEST_ROOT}/install
USER_HOME=${TEST_ROOT}/home
/usr/bin/install -d -m 755 "${INSTALL_ROOT}/bin" "${INSTALL_ROOT}/resources"
/bin/cp "${REPOSITORY_ROOT}/.env" "${INSTALL_ROOT}/.env"
sed -i 's/^CLASHCTL_KERNEL=.*/CLASHCTL_KERNEL=mihomo/' "${INSTALL_ROOT}/.env"
ln -s "${REPOSITORY_ROOT}/scripts" "${INSTALL_ROOT}/scripts"
/bin/cp "${REPOSITORY_ROOT}/resources/mixin.yaml" "${INSTALL_ROOT}/resources/mixin.yaml"
/bin/cp "${REPOSITORY_ROOT}/resources/profiles.yaml" "${INSTALL_ROOT}/resources/profiles.yaml"
tar -xf "${YQ_ARCHIVE}" -C "${INSTALL_ROOT}/bin"
/bin/mv "${INSTALL_ROOT}/bin/yq_linux_amd64" "${INSTALL_ROOT}/bin/yq"
tar -xf "${SUBCONVERTER_ARCHIVE}" -C "${INSTALL_ROOT}/bin"
/usr/bin/install -m 755 /usr/bin/true "${INSTALL_ROOT}/bin/mihomo"

export CLASHCTL_TEST_ROOT=${INSTALL_ROOT}
export HOME=${USER_HOME}
export XDG_CONFIG_HOME=${TEST_ROOT}/config
export XDG_DATA_HOME=${TEST_ROOT}/data
export XDG_STATE_HOME=${TEST_ROOT}/state
export XDG_RUNTIME_DIR=${TEST_ROOT}/runtime

bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" init >/dev/null
RUNTIME_CONFIG=${XDG_DATA_HOME}/clashctl/runtime.yaml
MIXIN_CONFIG=${XDG_CONFIG_HOME}/clashctl/mixin.yaml
[ -s "${RUNTIME_CONFIG}" ]
[ "$(stat -c %a "${RUNTIME_CONFIG}")" = 600 ]
[ "$(stat -c %a "${XDG_DATA_HOME}/clashctl")" = 700 ]
"${INSTALL_ROOT}/bin/yq" -e '
    ."allow-lan" == false and
    ."bind-address" == "127.0.0.1" and
    (."external-controller" | test("^127\\.0\\.0\\.1:")) and
    ((.secret // "") | length > 0) and
    (.tun.enable == false)
' "${RUNTIME_CONFIG}" >/dev/null

ports_before=$("${INSTALL_ROOT}/bin/yq" '[."mixed-port", ."external-controller"] | join("|")' "${MIXIN_CONFIG}")
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" init >/dev/null
ports_after=$("${INSTALL_ROOT}/bin/yq" '[."mixed-port", ."external-controller"] | join("|")' "${MIXIN_CONFIG}")
[ "${ports_before}" = "${ports_after}" ]
runtime_hash=$(sha256sum "${RUNTIME_CONFIG}" | awk '{print $1}')
if bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" tun on >/dev/null 2>&1; then
    printf '%s\n' 'TUN unexpectedly succeeded in system mode' >&2
    exit 1
fi
[ "$(sha256sum "${RUNTIME_CONFIG}" | awk '{print $1}')" = "${runtime_hash}" ]
if bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" upgrade >/dev/null 2>&1; then
    printf '%s\n' 'shared kernel upgrade unexpectedly succeeded as a user command' >&2
    exit 1
fi
UNSAFE_CONFIG_HOME=${TEST_ROOT}/unsafe-config
/usr/bin/install -d -m 700 "${UNSAFE_CONFIG_HOME}"
ln -s "${TEST_ROOT}/outside" "${UNSAFE_CONFIG_HOME}/clashctl"
if XDG_CONFIG_HOME=${UNSAFE_CONFIG_HOME} \
    bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" uninit --yes >/dev/null 2>&1; then
    printf '%s\n' 'unsafe uninit path unexpectedly accepted' >&2
    exit 1
fi
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" uninit --yes >/dev/null
[ ! -e "${XDG_CONFIG_HOME}/clashctl" ]
[ ! -e "${XDG_DATA_HOME}/clashctl" ]
[ ! -e "${XDG_STATE_HOME}/clashctl" ]
[ ! -e "${XDG_RUNTIME_DIR}/clashctl" ]
printf '%s\n' 'system initialization and permissions: ok'
