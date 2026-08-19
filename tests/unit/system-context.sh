#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d)
trap '/usr/bin/rm -rf -- "${TEST_ROOT}"' EXIT

export CLASHCTL_INSTALL_MODE=system
export CLASHCTL_ROOT=${TEST_ROOT}/install
export HOME=${TEST_ROOT}/home
export XDG_CONFIG_HOME=${TEST_ROOT}/xdg/config
export XDG_DATA_HOME=${TEST_ROOT}/xdg/data
export XDG_STATE_HOME=${TEST_ROOT}/xdg/state
export XDG_RUNTIME_DIR=${TEST_ROOT}/xdg/runtime
CLASHCTL_KERNEL=mihomo
export CLASHCTL_KERNEL

. "${REPOSITORY_ROOT}/scripts/lib/common.sh"
. "${REPOSITORY_ROOT}/scripts/lib/service.sh"

[ "${CLASHCTL_CONFIG_DIR}" = "${XDG_CONFIG_HOME}/clashctl" ]
[ "${CLASHCTL_DATA_DIR}" = "${XDG_DATA_HOME}/clashctl" ]
[ "${CLASHCTL_STATE_DIR}" = "${XDG_STATE_HOME}/clashctl" ]
[ "${CLASHCTL_RUNTIME_DIR}" = "${XDG_RUNTIME_DIR}/clashctl" ]
[ "${BIN_KERNEL}" = "${CLASHCTL_ROOT}/bin/mihomo" ]

/usr/bin/install -d -m 700 "${CLASHCTL_RUNTIME_DIR}" "${CLASHCTL_DATA_DIR}"
/usr/bin/install -m 600 /dev/null "${CLASH_CONFIG_RUNTIME}"
BIN_KERNEL=$(readlink -f /usr/bin/tail)
export BIN_KERNEL

"${BIN_KERNEL}" -f "${CLASH_CONFIG_RUNTIME}" >/dev/null 2>&1 &
test_pid=${!}
printf '%s\n' "${test_pid}" >"${CLASH_PID_FILE}"
chmod 600 "${CLASH_PID_FILE}"
service_valid_pid
[ "${SERVICE_VALID_PID}" = "${test_pid}" ]

printf '%s\n' "${test_pid}" >"${CLASH_PID_FILE}.wrong"
CLASH_PID_FILE=${CLASH_PID_FILE}.wrong
CLASH_CONFIG_RUNTIME=${CLASH_CONFIG_RUNTIME}.wrong
if service_valid_pid; then
    printf '%s\n' 'invalid PID unexpectedly passed validation' >&2
    exit 1
fi

kill "${test_pid}" 2>/dev/null || true
wait "${test_pid}" 2>/dev/null || true

(
    CLASHCTL_INSTALL_MODE=user
    CLASHCTL_HOME=${TEST_ROOT}/legacy
    CLASHCTL_KERNEL=mihomo
    export CLASHCTL_INSTALL_MODE CLASHCTL_HOME CLASHCTL_KERNEL
    # shellcheck disable=SC1090
    . "${REPOSITORY_ROOT}/scripts/lib/common.sh"
    [ "${CLASHCTL_ROOT}" = "${CLASHCTL_HOME}" ]
    [ "${CLASHCTL_DATA_DIR}" = "${CLASHCTL_HOME}/resources" ]
    [ "${CLASH_CONFIG_RUNTIME}" = "${CLASHCTL_HOME}/resources/runtime.yaml" ]
)
printf '%s\n' 'system context and PID validation: ok'
