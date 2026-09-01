#!/usr/bin/env bash

set -euo pipefail

command -v zsh >/dev/null 2>&1 || {
    printf '%s\n' 'SKIP: zsh is unavailable'
    exit 0
}

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d)
trap '/usr/bin/rm -rf -- "${TEST_ROOT}"' EXIT
FAKE_BIN=${TEST_ROOT}/bin
CALL_LOG=${TEST_ROOT}/calls.log
/usr/bin/install -d -m 700 "${FAKE_BIN}"
/bin/ln -s "${REPOSITORY_ROOT}/tests/fixtures/user-hook-bash" "${FAKE_BIN}/bash"

CLASHCTL_FAKE_LOG=${CALL_LOG} PATH=${FAKE_BIN}:/usr/bin:/bin zsh -fc '
    export CLASHCTL_HOME=$1
    export CLASHCTL_FAKE_LOG=$2
    source $1/scripts/cmd/clashctl.sh

    clashsub ls
    clashnode ls
    clashctl on
    test "$http_proxy" = http://127.0.0.1:17890
    test "$all_proxy" = socks5h://127.0.0.1:17890
    clashctl off
    test -z "${http_proxy:-}"
' -- "${REPOSITORY_ROOT}" "${CALL_LOG}"

grep -Fxq 'sub ls' "${CALL_LOG}"
grep -Fxq 'node ls' "${CALL_LOG}"
grep -Fxq 'on --service-only' "${CALL_LOG}"
grep -Fxq 'env --shell=zsh' "${CALL_LOG}"
grep -Fxq 'on --env-only' "${CALL_LOG}"
grep -Fxq 'off --service-only' "${CALL_LOG}"
grep -Fxq 'off --env-only' "${CALL_LOG}"
printf '%s\n' 'user zsh hook: ok'
