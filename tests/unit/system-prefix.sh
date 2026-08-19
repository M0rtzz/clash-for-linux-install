#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d)
trap '/usr/bin/rm -rf -- "${TEST_ROOT}"' EXIT

export CLASHCTL_SRC=${REPOSITORY_ROOT}
export CLASHCTL_INSTALL_MODE=system
export CLASHCTL_ROOT=${TEST_ROOT}/default

# shellcheck disable=SC1090
. "${REPOSITORY_ROOT}/scripts/preflight.sh"

parse_args --system --prefix "${TEST_ROOT}/custom"
[ "${CLASHCTL_ROOT}" = "${TEST_ROOT}/custom" ]
_validate_system_root

CLASHCTL_INSTALL_MODE=user
if parse_args --prefix "${TEST_ROOT}/user-prefix" >/dev/null 2>&1; then
    printf '%s\n' 'user mode unexpectedly accepted --prefix' >&2
    exit 1
fi
CLASHCTL_INSTALL_MODE=system

mkdir -p "${TEST_ROOT}/occupied"
touch "${TEST_ROOT}/occupied/unrelated"
CLASHCTL_ROOT=${TEST_ROOT}/occupied
if _validate_system_root >/dev/null 2>&1; then
    printf '%s\n' 'occupied system prefix unexpectedly accepted' >&2
    exit 1
fi

printf '%s\n' 'clashctl system installation' >"${TEST_ROOT}/occupied/.clashctl-system"
_validate_system_root

rm -f "${TEST_ROOT}/occupied/.clashctl-system"
_validate_system_root true

CLASHCTL_ROOT=relative-prefix
if _validate_system_root >/dev/null 2>&1; then
    printf '%s\n' 'relative system prefix unexpectedly accepted' >&2
    exit 1
fi

ln -s "${TEST_ROOT}/custom" "${TEST_ROOT}/symlink"
CLASHCTL_ROOT=${TEST_ROOT}/symlink
if _validate_system_root >/dev/null 2>&1; then
    printf '%s\n' 'symlink system prefix unexpectedly accepted' >&2
    exit 1
fi

CLASHCTL_ROOT=${TEST_ROOT}/custom
rendered_unit=$(sed -e "s|@CLASHCTL_ROOT@|${CLASHCTL_ROOT}|g" \
    -e 's|@CLASHCTL_KERNEL@|mihomo|g' \
    "${REPOSITORY_ROOT}/scripts/init/clashctl-user.service")
grep -Fq "ExecStart=${CLASHCTL_ROOT}/scripts/run-mihomo" <<<"${rendered_unit}"
grep -Fq 'ExecStopPost=/usr/bin/rm -f %t/clashctl/mihomo.pid' <<<"${rendered_unit}"
printf '%s\n' 'system prefix parsing and validation: ok'
