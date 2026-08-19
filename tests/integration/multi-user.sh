#!/usr/bin/env bash

set -euo pipefail

[ "$(id -u)" -eq 0 ] || {
    printf '%s\n' 'SKIP: multi-user integration test requires root'
    exit 0
}
[ -x /usr/local/bin/clashctl ] || {
    printf '%s\n' 'SKIP: run sudo bash install.sh --system first'
    exit 0
}

TEST_ROOT=$(mktemp -d /tmp/clashctl-multi-user.XXXXXX)
ALICE_USER=ctla${$}
BOB_USER=ctlb${$}
ALICE_HOME=${TEST_ROOT}/alice
BOB_HOME=${TEST_ROOT}/bob

cleanup() {
    [ -z "${ALICE_MARKER_PID:-}" ] || kill "${ALICE_MARKER_PID}" >/dev/null 2>&1 || true
    [ -z "${BOB_MARKER_PID:-}" ] || kill "${BOB_MARKER_PID}" >/dev/null 2>&1 || true
    for user_name in "${ALICE_USER}" "${BOB_USER}"; do
        id "${user_name}" >/dev/null 2>&1 || continue
        as_user "${user_name}" clashctl off --service-only >/dev/null 2>&1 || true
        as_user "${user_name}" clashctl uninit --yes >/dev/null 2>&1 || true
        userdel "${user_name}" >/dev/null 2>&1 || true
    done
    /usr/bin/rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

useradd --home-dir "${ALICE_HOME}" --create-home --shell /bin/bash "${ALICE_USER}"
useradd --home-dir "${BOB_HOME}" --create-home --shell /bin/bash "${BOB_USER}"
ALICE_UID=$(id -u "${ALICE_USER}")
BOB_UID=$(id -u "${BOB_USER}")
ALICE_GID=$(id -g "${ALICE_USER}")
BOB_GID=$(id -g "${BOB_USER}")
/usr/bin/install -d -o "${ALICE_UID}" -g "${ALICE_GID}" -m 700 "${ALICE_HOME}/run"
/usr/bin/install -d -o "${BOB_UID}" -g "${BOB_GID}" -m 700 "${BOB_HOME}/run"

as_user() {
    local user_name=${1}
    shift
    local user_home
    user_home=$(getent passwd "${user_name}" | cut -d: -f6)
    runuser -u "${user_name}" -- env -u DBUS_SESSION_BUS_ADDRESS \
        HOME="${user_home}" \
        XDG_CONFIG_HOME="${user_home}/.config" \
        XDG_DATA_HOME="${user_home}/.local/share" \
        XDG_STATE_HOME="${user_home}/.local/state" \
        XDG_RUNTIME_DIR="${user_home}/run" \
        PATH=/usr/local/bin:/usr/bin:/bin "${@}"
}

create_subscription() {
    local path=${1} node_name=${2} upstream_port=${3}
    /usr/bin/install -m 644 /dev/null "${path}"
    {
        printf '%s\n' 'proxies:'
        printf '  - {name: "%s", type: socks5, server: 127.0.0.1, port: %s}\n' "${node_name}" "${upstream_port}"
        printf '%s\n' 'proxy-groups:'
        printf '  - {name: PROXY, type: select, proxies: ["%s", DIRECT]}\n' "${node_name}"
        printf '%s\n' 'rules:' '  - MATCH,PROXY'
    } >"${path}"
}

python3 "$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/socks-marker.py" ALICE \
    "${TEST_ROOT}/alice-marker.port" & ALICE_MARKER_PID=${!}
python3 "$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/socks-marker.py" BOB \
    "${TEST_ROOT}/bob-marker.port" & BOB_MARKER_PID=${!}
for marker_file in "${TEST_ROOT}/alice-marker.port" "${TEST_ROOT}/bob-marker.port"; do
    for _attempt in {1..50}; do
        [ -s "${marker_file}" ] && break
        sleep 0.1
    done
    [ -s "${marker_file}" ]
done
ALICE_MARKER_PORT=$(<"${TEST_ROOT}/alice-marker.port")
BOB_MARKER_PORT=$(<"${TEST_ROOT}/bob-marker.port")

create_subscription "${TEST_ROOT}/alice.yaml" AliceNode "${ALICE_MARKER_PORT}"
create_subscription "${TEST_ROOT}/alice-two.yaml" AliceNodeTwo "${ALICE_MARKER_PORT}"
create_subscription "${TEST_ROOT}/bob.yaml" BobNode "${BOB_MARKER_PORT}"
chmod 755 "${TEST_ROOT}"

as_user "${ALICE_USER}" clashctl init
as_user "${BOB_USER}" clashctl init
as_user "${ALICE_USER}" clashctl sub add --use "file://${TEST_ROOT}/alice.yaml"
as_user "${ALICE_USER}" clashctl sub add --name AliceTwo "file://${TEST_ROOT}/alice-two.yaml"
as_user "${BOB_USER}" clashctl sub add --use "file://${TEST_ROOT}/bob.yaml"

as_user "${ALICE_USER}" clashctl on --service-only & alice_start=${!}
as_user "${BOB_USER}" clashctl on --service-only & bob_start=${!}
wait "${alice_start}"
wait "${bob_start}"

alice_doctor=$(as_user "${ALICE_USER}" clashctl doctor)
bob_doctor=$(as_user "${BOB_USER}" clashctl doctor)
alice_pid=$(awk '/^PID:/{print $2}' <<<"${alice_doctor}")
bob_pid=$(awk '/^PID:/{print $2}' <<<"${bob_doctor}")
alice_port=$(awk '/^Mixed port:/{print $3}' <<<"${alice_doctor}")
bob_port=$(awk '/^Mixed port:/{print $3}' <<<"${bob_doctor}")
[ "${alice_pid}" != "${bob_pid}" ]
[ "${alice_port}" != "${bob_port}" ]
alice_egress=$(as_user "${ALICE_USER}" curl --silent --fail --max-time 5 \
    --proxy "http://127.0.0.1:${alice_port}" http://marker.invalid/)
bob_egress=$(as_user "${BOB_USER}" curl --silent --fail --max-time 5 \
    --proxy "http://127.0.0.1:${bob_port}" http://marker.invalid/)
[ "${alice_egress}" = ALICE ]
[ "${bob_egress}" = BOB ]

bob_runtime=${BOB_HOME}/.local/share/clashctl/runtime.yaml
bob_hash_before=$(sha256sum "${bob_runtime}" | awk '{print $1}')
bob_pid_before=${bob_pid}
bob_port_before=${bob_port}
bob_subscription_before=$(awk '/^Subscription:/{print $2}' <<<"${bob_doctor}")

as_user "${ALICE_USER}" clashctl node use PROXY DIRECT >/dev/null
as_user "${ALICE_USER}" clashctl sub use AliceTwo >/dev/null
as_user "${ALICE_USER}" clashctl sub update --all >/dev/null
as_user "${ALICE_USER}" clashctl off --service-only
as_user "${BOB_USER}" clashctl status >/dev/null
bob_doctor_after=$(as_user "${BOB_USER}" clashctl doctor)
bob_hash_after=$(sha256sum "${bob_runtime}" | awk '{print $1}')
[ "${bob_hash_before}" = "${bob_hash_after}" ]
[ "$(awk '/^PID:/{print $2}' <<<"${bob_doctor_after}")" = "${bob_pid_before}" ]
[ "$(awk '/^Mixed port:/{print $3}' <<<"${bob_doctor_after}")" = "${bob_port_before}" ]
[ "$(awk '/^Subscription:/{print $2}' <<<"${bob_doctor_after}")" = "${bob_subscription_before}" ]

if as_user "${ALICE_USER}" cat "${BOB_HOME}/.local/share/clashctl/profiles.yaml" >/dev/null 2>&1; then
    printf '%s\n' 'alice unexpectedly read bob profile metadata' >&2
    exit 1
fi
if as_user "${ALICE_USER}" clashctl tun on >/dev/null 2>&1; then
    printf '%s\n' 'TUN unexpectedly succeeded in system mode' >&2
    exit 1
fi
printf '%s\n' 'multi-user isolation: ok'
