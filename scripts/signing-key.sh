#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
key_dir="${BAZZITE_SECRETS_DIR:-/home/mateo/Documents/dev/secrets/bazzite}"
case "${1:-check}" in
check)
	test -s "$key_dir/cosign.key"
	COSIGN_PASSWORD="" cosign public-key --key "$key_dir/cosign.key" | cmp cosign.pub -
	echo 'Private key matches the repository public key.'
	;;
upload)
	bash scripts/signing-key.sh check
	gh secret set SIGNING_SECRET --repo LagExpress/bazzite <"$key_dir/cosign.key"
	;;
*)
	echo 'Usage: bash scripts/signing-key.sh [check|upload]' >&2
	exit 2
	;;
esac
