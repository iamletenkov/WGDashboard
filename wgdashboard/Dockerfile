# WGDashboard with amneziawg-tools 3.x.
# The upstream image ships 2.0-era `awg`; an AmneziaWG 3.x kernel module rejects its
# netlink requests with "Invalid argument". Build the matching tools and replace them.
ARG WGD_IMAGE=ghcr.io/wgdashboard/wgdashboard:v4.3.3

FROM alpine:3.21 AS awg-tools
ARG AWG_TOOLS_REF=v3.1.20260812
RUN apk add --no-cache build-base linux-headers git
RUN git clone --depth 1 --branch "${AWG_TOOLS_REF}" https://github.com/amnezia-vpn/amneziawg-tools /src \
 && make -C /src/src wg LDFLAGS=-static \
 && strip /src/src/wg \
 && /src/src/wg --version

FROM ${WGD_IMAGE}
COPY --from=awg-tools /src/src/wg /usr/bin/awg
COPY --from=awg-tools /src/src/wg-quick/linux.bash /usr/bin/awg-quick
RUN chmod 0755 /usr/bin/awg /usr/bin/awg-quick && awg --version
