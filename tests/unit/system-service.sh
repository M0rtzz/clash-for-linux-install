#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
YQ_ARCHIVE=${REPOSITORY_ROOT}/archives/yq_linux_amd64.tar.gz
SUBCONVERTER_ARCHIVE=${REPOSITORY_ROOT}/archives/subconverter_linux64.tar.gz
MIHOMO_ARCHIVE=$(find "${REPOSITORY_ROOT}/archives" -maxdepth 1 -name 'mihomo*.gz' -print -quit 2>/dev/null)
if [ ! -f "${YQ_ARCHIVE}" ] || [ ! -f "${SUBCONVERTER_ARCHIVE}" ] || [ -z "${MIHOMO_ARCHIVE}" ]; then
    printf '%s\n' 'SKIP: local dependency archives are unavailable'
    exit 0
fi

TEST_ROOT=$(mktemp -d)
INSTALL_ROOT=${TEST_ROOT}/install
export CLASHCTL_TEST_ROOT=${INSTALL_ROOT}
export HOME=${TEST_ROOT}/home
export XDG_CONFIG_HOME=${TEST_ROOT}/config
export XDG_DATA_HOME=${TEST_ROOT}/data
export XDG_STATE_HOME=${TEST_ROOT}/state
export XDG_RUNTIME_DIR=${TEST_ROOT}/runtime
export CLASHCTL_SERVICE_MANAGER=nohup

cleanup() {
    bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" off --service-only >/dev/null 2>&1 || true
    if [ "${KEEP_TEST_ROOT:-0}" = 1 ]; then
        printf 'kept test root: %s\n' "${TEST_ROOT}" >&2
    else
        /usr/bin/rm -rf -- "${TEST_ROOT}"
    fi
}
trap cleanup EXIT

/usr/bin/install -d -m 755 "${INSTALL_ROOT}/bin" "${INSTALL_ROOT}/resources/dist"
/bin/cp "${REPOSITORY_ROOT}/.env" "${INSTALL_ROOT}/.env"
sed -i 's/^CLASHCTL_KERNEL=.*/CLASHCTL_KERNEL=mihomo/' "${INSTALL_ROOT}/.env"
ln -s "${REPOSITORY_ROOT}/scripts" "${INSTALL_ROOT}/scripts"
/bin/cp "${REPOSITORY_ROOT}/resources/mixin.yaml" "${INSTALL_ROOT}/resources/mixin.yaml"
/bin/cp "${REPOSITORY_ROOT}/resources/profiles.yaml" "${INSTALL_ROOT}/resources/profiles.yaml"
/bin/cp "${REPOSITORY_ROOT}/resources/Country.mmdb" "${INSTALL_ROOT}/resources/Country.mmdb"
/bin/cp "${REPOSITORY_ROOT}/resources/geosite.dat" "${INSTALL_ROOT}/resources/geosite.dat"
tar -xf "${YQ_ARCHIVE}" -C "${INSTALL_ROOT}/bin"
/bin/mv "${INSTALL_ROOT}/bin/yq_linux_amd64" "${INSTALL_ROOT}/bin/yq"
tar -xf "${SUBCONVERTER_ARCHIVE}" -C "${INSTALL_ROOT}/bin"
/usr/bin/install -m 755 <(gzip -dc "${MIHOMO_ARCHIVE}") "${INSTALL_ROOT}/bin/mihomo"

SUBSCRIPTION=${TEST_ROOT}/subscription.yaml
{
    printf '%s\n' 'proxies:'
    printf '%s\n' '  - {name: TestNode, type: socks5, server: 127.0.0.1, port: 9}'
    printf '%s\n' 'proxy-groups:'
    printf '%s\n' '  - {name: PROXY, type: select, proxies: [TestNode, DIRECT]}'
    printf '%s\n' 'rules:' '  - MATCH,DIRECT'
} >"${SUBSCRIPTION}"
SECOND_SUBSCRIPTION=${TEST_ROOT}/subscription-second.yaml
cp "${SUBSCRIPTION}" "${SECOND_SUBSCRIPTION}"

bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" init >/dev/null
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" sub add --use "file://${SUBSCRIPTION}" >/dev/null
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" sub add --name Secondary "file://${SECOND_SUBSCRIPTION}" >/dev/null
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" sub ls | grep -Fq Secondary
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" on --service-only >/dev/null
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" status >/dev/null
env_output=$(bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" env)
[[ ${env_output} == *'export http_proxy='* ]]
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" off --service-only >/dev/null
if bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" status >/dev/null 2>&1; then
    printf '%s\n' 'service remained active after stop' >&2
    exit 1
fi

CLASHCTL_INSTALL_MODE=system
CLASHCTL_ROOT=${INSTALL_ROOT}
. "${INSTALL_ROOT}/.env"
. "${REPOSITORY_ROOT}/scripts/lib/common.sh"
. "${REPOSITORY_ROOT}/scripts/lib/config.sh"
RECOVERY_ROOT=${TEST_ROOT}/recovery
/usr/bin/install -d -m 700 "${RECOVERY_ROOT}"
CLASH_CONFIG_BASE=${RECOVERY_ROOT}/base.yaml
CLASH_CONFIG_MIXIN=${RECOVERY_ROOT}/mixin.yaml
CLASH_CONFIG_RUNTIME=${RECOVERY_ROOT}/runtime.yaml
CLASH_CONFIG_TEMP=${RECOVERY_ROOT}/temp.yaml
BIN_KERNEL=/usr/bin/true
cat >"${CLASH_CONFIG_BASE}" <<'EOF'
port: 7890
external-controller: 0.0.0.0:9090
EOF
cat >"${CLASH_CONFIG_MIXIN}" <<'EOF'
port: 7890
external-controller: 0.0.0.0:9090
EOF
cat >"${CLASH_CONFIG_RUNTIME}" <<'EOF'
port: 7890
external-controller: 0.0.0.0:9090
EOF
CLASHCTL_INSTALL_MODE=user
_reallocate_conflicting_ports 'address already in use: 7890'
[ "$("${INSTALL_ROOT}/bin/yq" '.mixed-port // ""' "${CLASH_CONFIG_MIXIN}")" = '' ]
[ "$("${INSTALL_ROOT}/bin/yq" '.port' "${CLASH_CONFIG_MIXIN}")" != 7890 ]
[ "$("${INSTALL_ROOT}/bin/yq" '.external-controller' "${CLASH_CONFIG_MIXIN}")" = 0.0.0.0:9090 ]

cat >"${CLASH_CONFIG_BASE}" <<'EOF'
external-controller: 0.0.0.0:9090
EOF
cat >"${CLASH_CONFIG_MIXIN}" <<'EOF'
external-controller: 0.0.0.0:9090
EOF
cat >"${CLASH_CONFIG_RUNTIME}" <<'EOF'
external-controller: 0.0.0.0:9090
EOF
CLASHCTL_INSTALL_MODE=system
_reallocate_conflicting_ports 'address already in use: 9090'
[ "$("${INSTALL_ROOT}/bin/yq" '.mixed-port // ""' "${CLASH_CONFIG_MIXIN}")" = '' ]
[ "$("${INSTALL_ROOT}/bin/yq" '.external-controller' "${CLASH_CONFIG_MIXIN}")" != 127.0.0.1:9090 ]
printf '%s\n' 'conflict recovery: ok'
printf '%s\n' 'system nohup lifecycle: ok'
