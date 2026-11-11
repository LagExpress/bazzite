#!/usr/bin/env bash
set -euo pipefail

test "$(rpm -E '%fedora')" = 45
test "$(rpm -E '%_arch')" = x86_64
package_dir="$(mktemp -d /tmp/desktop-rpms.XXXXXXXX)"
trap 'rm -rf "$package_dir"' EXIT

for package in opencode hex; do
	url="$(jq -er --arg package "$package" '.[$package].url' /ctx/desktop-apps.json)"
	checksum="$(jq -er --arg package "$package" '.[$package].sha256' /ctx/desktop-apps.json)"
	expected="$(jq -er --arg package "$package" '"\($package) \(.[$package].version)-\(.[$package].release) x86_64"' /ctx/desktop-apps.json)"
	curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
		--retry 3 --retry-all-errors --connect-timeout 30 --max-time 600 \
		"$url" --output "$package_dir/$package.rpm"
	printf '%s  %s\n' "$checksum" "$package_dir/$package.rpm" | sha256sum --check --strict -
	test "$(rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}' "$package_dir/$package.rpm")" = "$expected"
done

# RPM cannot unpack through a symlinked /opt. Preserve its existing target.
opt_link=''
if [[ -L /opt ]]; then
	opt_link="$(readlink /opt)"
	rm /opt
	mkdir /opt
fi

# These vendor RPMs have no RPM signing key. Their bytes are authenticated by
# the reviewed SHA-256 pins above; repository dependency GPG checks stay enabled.
dnf5 --setopt=install_weak_deps=False --setopt=localpkg_gpgcheck=False \
	--setopt=timeout=30 --setopt=retries=3 install -y \
	"$package_dir/opencode.rpm" "$package_dir/hex.rpm"

# Keep OpenCode's Electron payload immutable across bootc deployments.
install -d /usr/lib/opt /usr/lib/tmpfiles.d
test -x /opt/OpenCode/ai.opencode
test ! -e /usr/lib/opt/OpenCode
mv /opt/OpenCode /usr/lib/opt/OpenCode
if [[ -n "$opt_link" ]]; then
	rmdir /opt
	ln -s "$opt_link" /opt
	mkdir -p "$(readlink -m /opt)"
fi
ln -s /usr/lib/opt/OpenCode /opt/OpenCode
printf 'L /opt/OpenCode - - - - /usr/lib/opt/OpenCode\n' >/usr/lib/tmpfiles.d/opencode-desktop.conf
ln -s /usr/lib/opt/OpenCode/ai.opencode /usr/bin/opencode-desktop
install -Dm644 /ctx/desktop-apps.json /usr/share/lagexpress/desktop-apps.json

rpm -q opencode hex
test -x /usr/bin/opencode-desktop
test -x /usr/bin/hex
dnf5 clean all
