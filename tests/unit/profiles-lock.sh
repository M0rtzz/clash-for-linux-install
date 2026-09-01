#!/usr/bin/env bash

set -euo pipefail

command -v flock >/dev/null 2>&1 || {
    printf '%s\n' 'SKIP: flock is unavailable'
    exit 0
}

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d)
CHILD_PID=
cleanup() {
    [ -z "${CHILD_PID}" ] || kill "${CHILD_PID}" 2>/dev/null || true
    /usr/bin/rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

CLASH_PROFILES_LOCK=${TEST_ROOT}/profiles.lock
CHILD_PID_FILE=${TEST_ROOT}/child.pid
_errorcat() {
    printf '%s\n' "${*}" >&2
    return 1
}
. "${REPOSITORY_ROOT}/scripts/cmd/sub.sh"

spawn_long_lived_child() {
    sleep 30 &
    printf '%s\n' "${!}" >"${CHILD_PID_FILE}"
}

_with_profiles_lock spawn_long_lived_child
read -r CHILD_PID <"${CHILD_PID_FILE}"
kill -0 "${CHILD_PID}"
flock -n "${CLASH_PROFILES_LOCK}" true || {
    printf '%s\n' 'child process inherited the profiles lock' >&2
    exit 1
}
if [ "$(readlink "/proc/${CHILD_PID}/fd/9" 2>/dev/null || true)" = "${CLASH_PROFILES_LOCK}" ]; then
    printf '%s\n' 'child process retained profiles lock fd 9' >&2
    exit 1
fi

DOWNLOAD_FILE=${TEST_ROOT}/download.yaml
_sub_validate_name() { return 0; }
_sub_has() { return 1; }
_sub_url_exists() { return 1; }
_sub_download() {
    /usr/bin/install -m 600 /dev/null "${DOWNLOAD_FILE}"
    _SUB_DL_FILE=${DOWNLOAD_FILE}
    FETCH_USERINFO=
    FETCH_FILENAME=
}
_with_profiles_lock() { return 1; }
if sub_add -n Test https://example.invalid/subscription; then
    printf '%s\n' 'subscription add unexpectedly succeeded without the lock' >&2
    exit 1
fi
[ ! -e "${DOWNLOAD_FILE}" ] || {
    printf '%s\n' 'download file remained after lock failure' >&2
    exit 1
}

printf '%s\n' 'profiles lock descriptor isolation: ok'
