#!/bin/sh
set -eux

# Install runtime dependencies for the detected package manager.
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends lsof ca-certificates openssl git tar sqlite3 fontconfig libfreetype6 tzdata iproute2 numactl libnuma1 libstdc++6 passwd graphviz binutils libatomic1 perl procps
    rm -rf /var/lib/apt/lists/*
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz binutils libatomic perl procps || dnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils
    dnf upgrade -y ca-certificates
    dnf clean all
elif command -v yum >/dev/null 2>&1; then
    yum install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz binutils libatomic perl procps || yum install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils
    yum clean all
elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils graphviz binutils libatomic perl procps || microdnf install -y lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute numactl libstdc++ shadow-utils
    microdnf clean all
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache lsof ca-certificates openssl git tar sqlite fontconfig freetype tzdata iproute2 numactl libstdc++ shadow libatomic perl procps graphviz binutils
fi

if command -v ldconfig >/dev/null 2>&1; then ldconfig || true; fi

# CVE-2026-91403: block the compromised eMudhra intermediates and their
# Sectigo cross-signs until every vendor ships a JDK that does.
java_home=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
blocked="$java_home/lib/security/blocked.certs"
[ -f "$blocked" ] || echo "Algorithm=SHA-256" > "$blocked"
grep -qx 'Algorithm=SHA-256' "$blocked"
[ -z "$(tail -c 1 "$blocked")" ] || echo >> "$blocked"
grep -v '^Algorithm=' /tmp/emudhra-blocked.certs | grep -vxF -f "$blocked" >> "$blocked" || true

# Amazon Linux 2023 still ships emSign ECC Root CA - G3 (CVE-2026-113470 is
# pending), so curl, git and openssl trust the same intermediates through it.
if command -v update-ca-trust >/dev/null 2>&1; then
    blocklist=/etc/pki/ca-trust/source/blocklist
    [ -d "$blocklist" ] || blocklist=/etc/pki/ca-trust/source/blacklist
    cp /tmp/emsign-ecc-root-ca-g3.pem "$blocklist/"
    update-ca-trust extract
elif command -v update-ca-certificates >/dev/null 2>&1; then
    sed -i 's|^mozilla/emSign_ECC_Root_CA_-_G3\.crt$|!&|' /etc/ca-certificates.conf
    update-ca-certificates
fi
for bundle in /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
    if [ -f "$bundle" ] && openssl verify -CAfile "$bundle" /tmp/emsign-ecc-root-ca-g3.pem >/dev/null 2>&1; then
        echo "emSign ECC Root CA - G3 is still trusted by $bundle" >&2
        exit 1
    fi
done

mkdir -p /home/container
if command -v useradd >/dev/null 2>&1; then
    useradd -d /home/container -m -u 1000 container || true
elif command -v adduser >/dev/null 2>&1; then
    adduser -D -h /home/container -u 1000 container || true
fi

chown -R 1000:1000 /home/container
chmod +x /entrypoint.sh