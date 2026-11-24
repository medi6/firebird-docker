FROM --platform=$BUILDPLATFORM debian:bookworm-slim as build

LABEL maintainer="jacob.alberty@foundigital.com"

ARG TARGETPLATFORM
ARG BUILDPLATFORM

ENV PREFIX=/usr/local/firebird
ENV VOLUME=/firebird
ENV DEBIAN_FRONTEND noninteractive
ENV FBURL=https://github.com/FirebirdSQL/firebird/releases/download/v4.0.7/Firebird-4.0.7.3271-0.tar.xz
ENV DBPATH=/firebird/data

COPY fixes /home/fixes
RUN chmod -R +x /home/fixes

COPY build.sh ./build.sh

RUN chmod +x ./build.sh && \
    sync && \
    ./build.sh && \
    rm -f ./build.sh

# ICU 67 (bullseye) : les bases existantes ont été créées avec ICU 67
# (COLL-VERSION=153.14 sur UNICODE/UNICODE_CI/UNICODE_CI_AI). Sans cette lib,
# Firebird sur bookworm (ICU 72) renvoie "COLLATION UNICODE_CI_AI ... is not installed".
FROM --platform=$TARGETPLATFORM debian:bullseye-slim as icu67
RUN apt-get update \
    && apt-get install -y --no-install-recommends libicu67=67.1-7 \
    && mkdir /icu67 \
    && cp -a /usr/lib/*-linux-gnu/libicu*.so.67* /icu67/

FROM --platform=$TARGETPLATFORM debian:bookworm-slim

ENV PREFIX=/usr/local/firebird
ENV VOLUME=/firebird
ENV DEBIAN_FRONTEND noninteractive
ENV DBPATH=/firebird/data

VOLUME ["/firebird"]

EXPOSE 3050/tcp

COPY --from=build /home/firebird/firebird.tar.gz /home/firebird/firebird.tar.gz

COPY install.sh ./install.sh

RUN chmod +x ./install.sh && \
    sync && \
    ./install.sh && \
    rm -f ./install.sh

COPY --from=icu67 /icu67/ /usr/local/lib/
RUN ldconfig \
    && sed -i 's/icu_versions = default/icu_versions = 67 default/' ${PREFIX}/intl/fbintl.conf

COPY docker-entrypoint.sh ${PREFIX}/docker-entrypoint.sh
RUN chmod +x ${PREFIX}/docker-entrypoint.sh

COPY docker-healthcheck.sh ${PREFIX}/docker-healthcheck.sh
RUN chmod +x ${PREFIX}/docker-healthcheck.sh \
    && apt-get update \
    && apt-get -qy install netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*
HEALTHCHECK CMD ${PREFIX}/docker-healthcheck.sh || exit 1

ENTRYPOINT ["/usr/local/firebird/docker-entrypoint.sh"]

CMD ["firebird"]
