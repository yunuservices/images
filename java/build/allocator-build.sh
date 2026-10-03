#!/bin/sh
set -eux

# Runs on Amazon Linux 2023 (glibc 2.34), the oldest glibc among the base
# images, so the resulting libraries load on every vendor image.
JEMALLOC_VERSION=5.4.0
MIMALLOC_VERSION=v3.5.3
GPERFTOOLS_VERSION=gperftools-2.18.1
ASYNC_PROFILER_VERSION=4.5
ASYNC_PROFILER_SHA256_X64=89546fbb9ee0fc5496c7edd4099b0709489bc78b0d8057ccbb4b801f6b032b62
ASYNC_PROFILER_SHA256_ARM64=64c41d1465d60097439c50d7e924b4946f1f62b1cbd21ce5b034fad09c0d6979

dnf install -y ca-certificates git tar gzip findutils gcc gcc-c++ make autoconf automake libtool cmake libatomic
dnf clean all

mkdir -p /out
CPU_COUNT="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

# jemalloc is built from source: distro packages lack jeprof and prof support.
git clone --depth 1 --branch "$JEMALLOC_VERSION" https://github.com/jemalloc/jemalloc.git /tmp/jemalloc
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

# Only tcmalloc_minimal is built; heap profiling is covered by jemalloc.
git clone --depth 1 --branch "$GPERFTOOLS_VERSION" https://github.com/gperftools/gperftools.git /tmp/gperftools
cd /tmp/gperftools
./autogen.sh
./configure --enable-minimal --disable-static
make -j"$CPU_COUNT"
cd /
TCMALLOC_LIB="$(find /tmp/gperftools/.libs -type f -name 'libtcmalloc_minimal.so*' | head -n1)"
[ -n "$TCMALLOC_LIB" ] || { echo "failed to resolve tcmalloc shared library"; exit 1; }
cp "$TCMALLOC_LIB" /out/libtcmalloc_minimal.so

# async-profiler ships portable Linux builds, so the release archive is used
# after checking its published checksum.
case "$(uname -m)" in
    x86_64)
        ASYNC_PROFILER_ARCH=x64
        ASYNC_PROFILER_SHA256=$ASYNC_PROFILER_SHA256_X64
        ;;
    aarch64)
        ASYNC_PROFILER_ARCH=arm64
        ASYNC_PROFILER_SHA256=$ASYNC_PROFILER_SHA256_ARM64
        ;;
    *)
        echo "unsupported architecture for async-profiler: $(uname -m)"
        exit 1
        ;;
esac
ASYNC_PROFILER_NAME="async-profiler-$ASYNC_PROFILER_VERSION-linux-$ASYNC_PROFILER_ARCH"
curl -fsSL -o /tmp/async-profiler.tar.gz \
    "https://github.com/async-profiler/async-profiler/releases/download/v$ASYNC_PROFILER_VERSION/$ASYNC_PROFILER_NAME.tar.gz"
echo "$ASYNC_PROFILER_SHA256  /tmp/async-profiler.tar.gz" | sha256sum -c -
tar -xzf /tmp/async-profiler.tar.gz -C /tmp
mv "/tmp/$ASYNC_PROFILER_NAME" /out/async-profiler
