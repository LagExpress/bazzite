#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
variant="${1:-bazzite-kde}"
base="$(jq -er --arg name "$variant" '.images[] | select(.name == $name) | .base' images.json)"
registry="${IMAGE_REGISTRY:-ghcr.io/lagexpress}"
source_repo="${GITHUB_REPOSITORY:-LagExpress/bazzite}"
revision="$(git rev-parse HEAD)"
podman build --pull=always --platform linux/amd64 \
	--build-arg "BASE_IMAGE=$base" --build-arg "IMAGE_REGISTRY=$registry" \
	--label "org.opencontainers.image.title=$variant" \
	--label "org.opencontainers.image.description=Bazzite 45 with Brave Origin RPM" \
	--label "org.opencontainers.image.source=https://github.com/$source_repo" \
	--label "org.opencontainers.image.revision=$revision" \
	--label "org.opencontainers.image.base.name=$base" \
	--label "org.opencontainers.image.version=45.$(date -u +%Y%m%d)-${revision:0:7}" \
	--tag "localhost/$variant:45" --file Containerfile .
