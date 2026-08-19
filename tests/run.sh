#!/usr/bin/env bash

set -euo pipefail
TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

bash "${TEST_ROOT}/unit/system-context.sh"
bash "${TEST_ROOT}/unit/system-init.sh"
bash "${TEST_ROOT}/unit/system-migrate.sh"
bash "${TEST_ROOT}/unit/system-service.sh"
bash "${TEST_ROOT}/unit/shell-hook.sh"
printf '%s\n' 'unit tests: ok'
printf '%s\n' 'run tests/integration/multi-user.sh as root after a system install for integration coverage'
