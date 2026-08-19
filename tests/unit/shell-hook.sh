#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d)
trap '/usr/bin/rm -rf -- "${TEST_ROOT}"' EXIT
export CLASHCTL_FAKE_LOG=${TEST_ROOT}/calls.log
export PATH=${REPOSITORY_ROOT}/tests/fixtures:/usr/bin:/bin
unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY || true

. "${REPOSITORY_ROOT}/scripts/shell/clashctl.sh"
clashctl on
[ "${http_proxy}" = http://127.0.0.1:17890 ]
[ "${all_proxy}" = socks5h://127.0.0.1:17890 ]
grep -Fxq 'on --service-only' "${CLASHCTL_FAKE_LOG}"

clashctl off
[ -z "${http_proxy:-}" ]
[ -z "${all_proxy:-}" ]
grep -Fxq 'off --service-only' "${CLASHCTL_FAKE_LOG}"
printf '%s\n' 'bash shell hook: ok'

if command -v fish >/dev/null 2>&1; then
    fish -c '
        set -gx CLASHCTL_FAKE_LOG $argv[1]
        set -gx PATH $argv[2] $PATH
        source $argv[3]
        clashctl on
        test "$http_proxy" = "http://127.0.0.1:17890"; or exit 1
        clashctl off
        not set -q http_proxy; or exit 1
        clashctl on --env-only
        test "$all_proxy" = "socks5h://127.0.0.1:17890"; or exit 1
    ' "${CLASHCTL_FAKE_LOG}" "${REPOSITORY_ROOT}/tests/fixtures" \
        "${REPOSITORY_ROOT}/scripts/shell/clashctl.fish"
    grep -Fxq 'status' "${CLASHCTL_FAKE_LOG}"
    grep -Fxq 'env --shell=fish' "${CLASHCTL_FAKE_LOG}"
    printf '%s\n' 'fish shell hook: ok'
fi
