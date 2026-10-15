# WGDashboard with AmneziaWG 3.x support.
# 1. amneziawg-tools 3.x: the upstream image ships 2.0-era `awg`, and an AmneziaWG 3.x
#    kernel module rejects its netlink requests with "Invalid argument".
# 2. Panel patches (patches/): AWG 3.x interface options (upstream PR #1360) in the
#    configuration forms, saved files and downloaded peer configs; unset options are
#    never written, so AWG 1.0/2.0 configurations keep working.
# The patched Python modules and the rebuilt admin UI are copied over the upstream image
# of the same version, so WGD_VERSION must name both the image tag and the source tag.
ARG WGD_VERSION=v4.3.3

FROM alpine:3.21 AS awg-tools
ARG AWG_TOOLS_REF=v3.1.20260812
RUN apk add --no-cache build-base linux-headers git
RUN git clone --depth 1 --branch "${AWG_TOOLS_REF}" https://github.com/amnezia-vpn/amneziawg-tools /src \
 && make -C /src/src wg LDFLAGS=-static \
 && strip /src/src/wg \
 && /src/src/wg --version

FROM alpine:3.21 AS wgd-src
ARG WGD_VERSION
RUN apk add --no-cache git
COPY patches/ /patches/
RUN git clone --depth 1 --branch "${WGD_VERSION}" https://github.com/WGDashboard/WGDashboard /wgd \
 && cd /wgd && for p in /patches/*.patch; do git apply --verbose "$p"; done

FROM node:22-alpine AS ui
COPY --from=wgd-src /wgd/src/static /wgd/src/static
WORKDIR /wgd/src/static/app
RUN npm ci --no-audit --no-fund && npx vite build --emptyOutDir

FROM ghcr.io/wgdashboard/wgdashboard:${WGD_VERSION}
COPY --from=awg-tools /src/src/wg /usr/bin/awg
COPY --from=awg-tools /src/src/wg-quick/linux.bash /usr/bin/awg-quick
COPY --from=wgd-src /wgd/src/modules/ /opt/wgdashboard/src/modules/
COPY --from=ui /wgd/src/static/dist/WGDashboardAdmin/ /opt/wgdashboard/src/static/dist/WGDashboardAdmin/
RUN chmod 0755 /usr/bin/awg /usr/bin/awg-quick && awg --version \
 && grep -q IsUnsetAwg3Value /opt/wgdashboard/src/modules/Utilities.py
