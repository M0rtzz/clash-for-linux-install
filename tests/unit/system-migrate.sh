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
LEGACY_HOME=${TEST_ROOT}/legacy
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
export HOME=${TEST_ROOT}/home
export XDG_CONFIG_HOME=${TEST_ROOT}/config
export XDG_DATA_HOME=${TEST_ROOT}/data
export XDG_STATE_HOME=${TEST_ROOT}/state
export XDG_RUNTIME_DIR=${TEST_ROOT}/runtime
export CLASHCTL_LEGACY_HOME=${LEGACY_HOME}

bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" init >/dev/null
bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" uninit --yes >/dev/null

/usr/bin/install -d -m 700 "${LEGACY_HOME}/resources" "${LEGACY_HOME}/resources/profiles"
cat >"${LEGACY_HOME}/resources/config.yaml" <<'EOF'
mixed-port: 7890
EOF
cat >"${LEGACY_HOME}/resources/runtime.yaml" <<'EOF'
mixed-port: 17890
external-controller: 127.0.0.1:19090
allow-lan: false
bind-address: 127.0.0.1
secret: runtime-secret
tun:
  enable: false
EOF
cat >"${LEGACY_HOME}/resources/mixin.yaml" <<'EOF'
mixed-port: 7890
external-controller: 0.0.0.0:*
secret:
allow-lan: true
bind-address: '*'
tun:
  enable: true
EOF
cat >"${LEGACY_HOME}/resources/profiles.yaml" <<'EOF'
profiles:
  - name: Legacy
    path: LEGACY_PROFILE_PATH
    url: file:///legacy.yaml
use: Legacy
EOF
sed -i "s|LEGACY_PROFILE_PATH|${LEGACY_HOME}/resources/profiles/Legacy.yaml|" \
    "${LEGACY_HOME}/resources/profiles.yaml"
cat >"${LEGACY_HOME}/resources/profiles/Legacy.yaml" <<'EOF'
proxies:
  - {name: LegacyNode, type: socks5, server: 127.0.0.1, port: 9}
proxy-groups:
  - {name: PROXY, type: select, proxies: [LegacyNode, DIRECT]}
rules:
  - MATCH,DIRECT
EOF

bash "${REPOSITORY_ROOT}/scripts/clashctl-exec" migrate >/dev/null
MIXIN_CONFIG=${XDG_CONFIG_HOME}/clashctl/mixin.yaml
"${INSTALL_ROOT}/bin/yq" -e '
    (."external-controller" | test("^127\\.0\\.0\\.1:[0-9]+$")) and
    ((.secret // "") | length > 0) and
    (."allow-lan" == false) and
    (."bind-address" == "127.0.0.1") and
    (.tun.enable == false)
' "${MIXIN_CONFIG}" >/dev/null
MIGRATED_PROFILE_PATH=$(
    "${INSTALL_ROOT}/bin/yq" -r '.profiles[0].path' "${XDG_DATA_HOME}/clashctl/profiles.yaml"
)
[ "${MIGRATED_PROFILE_PATH}" = "${XDG_DATA_HOME}/clashctl/profiles/Legacy.yaml" ]
[ -s "${MIGRATED_PROFILE_PATH}" ]
"${INSTALL_ROOT}/bin/yq" -e '.profiles[0].name == "Legacy" and .use == "Legacy"' \
    "${XDG_DATA_HOME}/clashctl/profiles.yaml" >/dev/null
printf '%s\n' 'system migration normalization: ok'
