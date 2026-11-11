ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable-45
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY cosign.pub /cosign.pub
COPY images.json /images.json

FROM ${BASE_IMAGE}
ARG IMAGE_REGISTRY=ghcr.io/lagexpress

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Official OpenCode Desktop and Hex RPMs, pinned in desktop-apps.json.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/run \
    /ctx/install-desktop-apps.sh

RUN bootc container lint
