#!/usr/bin/env bash
set -euo pipefail

test "$(rpm -E '%fedora')" = 45
test "$(rpm -E '%_arch')" = x86_64
package_dir="$(mktemp -d /tmp/desktop-rpms.XXXXXXXX)"
trap 'rm -rf "$package_dir"' EXIT

for package in opencode hex chatgpt orca-ide; do
	url="$(jq -er --arg package "$package" '.[$package].url' /ctx/desktop-apps.json)"
	checksum="$(jq -er --arg package "$package" '.[$package].sha256' /ctx/desktop-apps.json)"
	artifact="$package_dir/$package.rpm"
	curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
		--retry 3 --retry-all-errors --connect-timeout 30 --max-time 600 \
		"$url" --output "$artifact"
	printf '%s  %s\n' "$checksum" "$artifact" | sha256sum --check --strict -
	expected="$(jq -er --arg package "$package" '"\($package) \(.[$package].version)-\(.[$package].release) x86_64"' /ctx/desktop-apps.json)"
	test "$(rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}' "$artifact")" = "$expected"
done

# OpenAI's RPM is vendor-signed. Verify it using the pinned public key before
# allowing the mixed transaction containing other vendors' unsigned RPMs.
rpm --import /ctx/keys/chatgpt.asc
rpm --checksig "$package_dir/chatgpt.rpm"

# RPM cannot unpack through a symlinked /opt. Preserve its existing target.
opt_link=''
if [[ -L /opt ]]; then
	opt_link="$(readlink /opt)"
	rm /opt
	mkdir /opt
fi

# OpenCode, Hex and Orca use the per-run SHA-256 snapshot. OpenAI's signature
# was checked separately. Repository dependency GPG checks stay enabled.
dnf5 --setopt=install_weak_deps=False --setopt=localpkg_gpgcheck=False \
	--setopt=timeout=30 --setopt=retries=3 install -y \
	"$package_dir/opencode.rpm" "$package_dir/hex.rpm" \
	"$package_dir/chatgpt.rpm" "$package_dir/orca-ide.rpm"

# Keep the Electron payloads immutable across bootc deployments.
install -d /usr/lib/opt /usr/lib/tmpfiles.d
test -x /opt/OpenCode/ai.opencode
test -x /opt/Orca/orca-ide
for application in OpenCode Orca; do
	test ! -e "/usr/lib/opt/$application"
	mv "/opt/$application" "/usr/lib/opt/$application"
done
if [[ -n "$opt_link" ]]; then
	rmdir /opt
	ln -s "$opt_link" /opt
	mkdir -p "$(readlink -m /opt)"
fi
for application in OpenCode Orca; do
	ln -s "/usr/lib/opt/$application" "/opt/$application"
done
printf 'L /opt/OpenCode - - - - /usr/lib/opt/OpenCode\nL /opt/Orca - - - - /usr/lib/opt/Orca\n' >/usr/lib/tmpfiles.d/opencode-desktop.conf
ln -s /usr/lib/opt/OpenCode/ai.opencode /usr/bin/opencode-desktop
ln -sfn /usr/lib/opt/Orca/orca-ide /usr/bin/orca-ide

# Make the officially bundled coding agents discoverable by Orca.
if [[ ! -e /usr/bin/codex ]]; then
	ln -s /usr/lib/chatgpt/resources/codex /usr/bin/codex
fi
if [[ ! -e /usr/bin/opencode ]]; then
	ln -s /usr/lib/opt/OpenCode/resources/opencode-cli /usr/bin/opencode
fi
install -Dm644 /ctx/desktop-apps.json /usr/share/lagexpress/desktop-apps.json

rpm -q opencode hex chatgpt orca-ide
test -x /usr/bin/opencode-desktop
test -x /usr/bin/hex
test -x /usr/bin/chatgpt
test -x /usr/bin/orca-ide
dnf5 clean all
