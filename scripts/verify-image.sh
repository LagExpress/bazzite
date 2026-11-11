#!/usr/bin/env bash
set -euo pipefail
variant="${1:-bazzite-kde}"
podman run --rm --entrypoint /usr/bin/bash "localhost/$variant:45" -euc '
    test "$(rpm -E "%fedora")" = 45
    rpm -q brave-origin
    test -x /usr/lib/opt/brave.com/brave-origin/brave
    systemd-tmpfiles --create /usr/lib/tmpfiles.d/brave-origin.conf
    test -x /usr/bin/brave-origin
    test -s /etc/pki/containers/lagexpress-bazzite.pub
    jq -e '\''.transports.docker | to_entries | any(.value[]; .type == "sigstoreSigned" and .keyPath == "/etc/pki/containers/lagexpress-bazzite.pub")'\'' /etc/containers/policy.json
'
