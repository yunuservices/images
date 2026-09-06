#!/bin/sh
set -eux

# Install runtime dependencies for the detected package manager.
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends lsof ca-certificates openssl git tar sqlite3 fontconfig libfreetype6 tzdata iproute2 numactl libnuma1 libstdc++6 passwd graphviz libatomic1 perl procps
    rm -rf /var/lib/apt/lists/*
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz libatomic perl procps || dnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils
    dnf clean all
elif command -v yum >/dev/null 2>&1; then
    yum install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz libatomic perl procps || yum install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils
    yum clean all
elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz libatomic perl procps || microdnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils
    microdnf clean all
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute2 numactl libstdc++ shadow libatomic perl procps graphviz
fi

if command -v ldconfig >/dev/null 2>&1; then ldconfig || true; fi

mkdir -p /home/container
if command -v useradd >/dev/null 2>&1; then
    useradd -d /home/container -m -u 1000 container || true
elif command -v adduser >/dev/null 2>&1; then
    adduser -D -h /home/container -u 1000 container || true
fi

chown -R 1000:1000 /home/container
chmod +x /entrypoint.sh