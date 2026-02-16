FROM eclipse-temurin:25 AS allocator-builder

RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      apt-get install -y --no-install-recommends ca-certificates git tar findutils build-essential autoconf automake libtool pkg-config cmake; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v dnf >/dev/null 2>&1; then \
      dnf install -y ca-certificates git tar findutils gcc gcc-c++ make autoconf automake libtool pkgconf-pkg-config cmake; \
      dnf clean all; \
    elif command -v yum >/dev/null 2>&1; then \
      yum install -y ca-certificates git tar findutils gcc gcc-c++ make autoconf automake libtool pkgconfig cmake; \
      yum clean all; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y ca-certificates git tar findutils gcc gcc-c++ make autoconf automake libtool pkgconf-pkg-config cmake; \
      microdnf clean all; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache ca-certificates git tar findutils build-base autoconf automake libtool pkgconf cmake; \
    fi

RUN set -eux; \
    mkdir -p /out; \
    git clone --depth 1 https://github.com/facebook/jemalloc.git /tmp/jemalloc; \
    cd /tmp/jemalloc; \
    ./autogen.sh --enable-prof; \
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc || echo 1)"; \
    make install; \
    JEMALLOC_LIB="$(find /usr/local/lib /tmp/jemalloc -type f -name 'libjemalloc.so*' 2>/dev/null | head -n1 || true)"; \
    [ -n "$JEMALLOC_LIB" ] || { echo 'failed to build jemalloc shared library'; exit 1; }; \
    cp "$JEMALLOC_LIB" /out/libjemalloc.so; \
    git clone --depth 1 https://github.com/microsoft/mimalloc.git /tmp/mimalloc; \
    mkdir -p /tmp/mimalloc/build; \
    cd /tmp/mimalloc/build; \
    cmake .. -DMI_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release; \
    cmake --build . --config Release -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc || echo 1)"; \
    cd /; \
    MIMALLOC_LIB="$(find /tmp/mimalloc /usr/local/lib /usr/lib /lib -type f -name 'libmimalloc.so*' 2>/dev/null | head -n1 || true)"; \
    [ -n "$MIMALLOC_LIB" ] || { echo 'failed to build mimalloc shared library'; exit 1; }; \
    cp "$MIMALLOC_LIB" /out/libmimalloc.so

FROM eclipse-temurin:25
MAINTAINER "yunuservices"

COPY ./entrypoint.sh /entrypoint.sh
COPY --from=allocator-builder /out/libjemalloc.so /usr/local/lib/libjemalloc.so
COPY --from=allocator-builder /out/libmimalloc.so /usr/local/lib/libmimalloc.so

RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      apt-get install -y --no-install-recommends lsof ca-certificates openssl git tar sqlite3 fontconfig libfreetype6 tzdata iproute2 numactl libnuma1 libstdc++6 passwd graphviz libjemalloc-dev; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v dnf >/dev/null 2>&1; then \
      dnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz jemalloc-devel || dnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils; \
      dnf clean all; \
    elif command -v yum >/dev/null 2>&1; then \
      yum install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz jemalloc-devel || yum install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils; \
      yum clean all; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz jemalloc-devel || microdnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils; \
      microdnf clean all; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute2 numactl libstdc++ shadow; \
    fi; \
    if command -v ldconfig >/dev/null 2>&1; then ldconfig || true; fi; \
    mkdir -p /home/container; \
    if command -v useradd >/dev/null 2>&1; then \
      useradd -d /home/container -m -u 1000 container || true; \
    elif command -v adduser >/dev/null 2>&1; then \
      adduser -D -h /home/container -u 1000 container || true; \
    fi; \
    chown -R 1000:1000 /home/container; \
    chmod +x /entrypoint.sh

USER 1000:1000
ENV USER=container HOME=/home/container
WORKDIR /home/container

CMD ["/bin/sh", "/entrypoint.sh"]
