#!/usr/bin/env bash
set -euo pipefail
variant="${1:-bazzite-kde}"
podman run --rm --entrypoint /usr/bin/bash "localhost/$variant:45" -euc '
    test "$(rpm -E "%fedora")" = 45
    rpm -q brave-origin opencode hex chatgpt orca-ide
    test -x /usr/lib/opt/brave.com/brave-origin/brave
    systemd-tmpfiles --create /usr/lib/tmpfiles.d/brave-origin.conf
    systemd-tmpfiles --create /usr/lib/tmpfiles.d/opencode-desktop.conf
    test -x /usr/bin/brave-origin
    test -x /usr/bin/opencode-desktop
    test -x /opt/OpenCode/ai.opencode
    test -x /usr/lib/opt/OpenCode/resources/opencode-cli
    test -x /usr/bin/hex
    test -f /usr/share/applications/ai.opencode.desktop.desktop
    test -f /usr/share/applications/anomaly.hex.desktop
    test -f /usr/lib/systemd/user/hex.service
    test -x /usr/bin/chatgpt
    test -x /usr/lib/chatgpt/resources/codex
    test -x /usr/bin/orca-ide
    test -x /opt/Orca/orca-ide
    test -f /usr/share/applications/chatgpt.desktop
    test -f /usr/share/applications/orca-ide.desktop
    for package in opencode hex chatgpt orca-ide; do
        expected=$(jq -er --arg package "$package" '\''"\(.[$package].version)-\(.[$package].release)"'\'' /usr/share/lagexpress/desktop-apps.json)
        test "$(rpm -q --qf "%{VERSION}-%{RELEASE}" "$package")" = "$expected"
    done
    hex --version
    codex --version
    opencode --version
    test -s /etc/pki/containers/lagexpress-bazzite.pub
    jq -e '\''[.transports.docker[][] | select(.type == "sigstoreSigned" and .keyPath == "/etc/pki/containers/lagexpress-bazzite.pub")] | length == 11'\'' /etc/containers/policy.json
'
