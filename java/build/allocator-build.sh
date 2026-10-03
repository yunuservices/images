#!/bin/sh
set -eux

# Runs on Amazon Linux 2023 (glibc 2.34), the oldest glibc among the base
# images, so the resulting libraries load on every vendor image.
JEMALLOC_VERSION=5.3.0
MIMALLOC_VERSION=v3.4.5

dnf install -y ca-certificates git tar findutils gcc gcc-c++ make autoconf automake libtool cmake libatomic
dnf clean all

mkdir -p /out
CPU_COUNT="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

# jemalloc is built from source: distro packages lack jeprof and prof support.
git clone --depth 1 --branch "$JEMALLOC_VERSION" https://github.com/facebook/jemalloc.git /tmp/jemalloc
cd /tmp/jemalloc
./autogen.sh --enable-prof
make -j"$CPU_COUNT"
make install
cd /
JEMALLOC_LIB="$(find /usr/local/lib -type f -name 'libjemalloc.so*' | head -n1)"
[ -n "$JEMALLOC_LIB" ] || { echo "failed to resolve jemalloc shared library"; exit 1; }
cp "$JEMALLOC_LIB" /out/libjemalloc.so
cp /usr/local/bin/jeprof /out/jeprof

git clone --depth 1 --branch "$MIMALLOC_VERSION" https://github.com/microsoft/mimalloc.git /tmp/mimalloc
cmake -S /tmp/mimalloc -B /tmp/mimalloc/build -DMI_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/mimalloc/build -j"$CPU_COUNT"
MIMALLOC_LIB="$(find /tmp/mimalloc/build -type f -name 'libmimalloc.so*' | head -n1)"
[ -n "$MIMALLOC_LIB" ] || { echo "failed to resolve mimalloc shared library"; exit 1; }
cp "$MIMALLOC_LIB" /out/libmimalloc.so
