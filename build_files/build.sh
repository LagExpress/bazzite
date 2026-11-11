#!/usr/bin/env bash
set -euo pipefail

# Never silently change Fedora releases with an upstream tag.
test "$(rpm -E '%fedora')" = 45
cp -avf /ctx/system_files/. /

# Recent RPM versions refuse to unpack through /opt when it is a symlink.
# Temporarily use a real directory; preserve the existing mutable target and
# restore the original link after relocating only Brave's new payload.
opt_link=''
if [[ -L /opt ]]; then
	opt_link="$(readlink /opt)"
	rm /opt
	mkdir /opt
fi

# Official Brave Origin release RPM repository; retain RPM signature checks.
curl --fail --silent --show-error --location --retry 3 \
	https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
	--output /etc/yum.repos.d/brave-browser.repo
dnf5 --setopt=install_weak_deps=False install -y brave-origin
rpm -q brave-origin

# /opt normally points into mutable /var/opt. Store the RPM payload in /usr
# and recreate its expected /opt path when booting an installed system.
install -d /usr/lib/opt/brave.com /usr/lib/tmpfiles.d
test -x /opt/brave.com/brave-origin/brave
test ! -e /usr/lib/opt/brave.com/brave-origin
mv /opt/brave.com/brave-origin /usr/lib/opt/brave.com/brave-origin
if [[ -n "$opt_link" ]]; then
	rmdir /opt/brave.com /opt
	ln -s "$opt_link" /opt
	mkdir -p "$(readlink -m /opt)"
	install -d /opt/brave.com
fi
ln -s /usr/lib/opt/brave.com/brave-origin /opt/brave.com/brave-origin
cat >/usr/lib/tmpfiles.d/brave-origin.conf <<'EOF'
d /opt/brave.com 0755 root root -
L /opt/brave.com/brave-origin - - - - /usr/lib/opt/brave.com/brave-origin
EOF
test -x /usr/bin/brave-origin

# Add policies for all fork variants, preserving the upstream policies.
install -Dm644 /ctx/cosign.pub /etc/pki/containers/lagexpress-bazzite.pub
install -d /etc/containers/registries.d
printf 'docker:\n  %s:\n    use-sigstore-attachments: true\n' "$IMAGE_REGISTRY" \
	>/etc/containers/registries.d/lagexpress-bazzite.yaml
jq --arg registry "$IMAGE_REGISTRY" --slurpfile matrix /ctx/images.json '
  reduce $matrix[0].images[].name as $name (. ;
    .transports.docker[($registry + "/" + $name)] = [{
      type: "sigstoreSigned",
      keyPath: "/etc/pki/containers/lagexpress-bazzite.pub",
      signedIdentity: {type: "matchRepository"}
    }])
' /etc/containers/policy.json >/tmp/policy.json
install -m644 /tmp/policy.json /etc/containers/policy.json
dnf5 clean all
