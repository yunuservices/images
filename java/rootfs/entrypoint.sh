#!/bin/sh

LIB_DIR=/usr/local/lib/entrypoint
. "$LIB_DIR/common.sh"
. "$LIB_DIR/allocator.sh"
. "$LIB_DIR/profiler.sh"
. "$LIB_DIR/watcher.sh"

TZ=${TZ:-UTC}
export TZ

if command -v ip >/dev/null 2>&1; then
    INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2); exit}')
else
    INTERNAL_IP=$(hostname -i 2>/dev/null | awk '{print $1}')
fi
export INTERNAL_IP

cd /home/container || exit 1

printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mjava -version\n"
java -version

PARSED=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

MIMALLOC_ENABLED=false
JEMALLOC_ENABLED=false
DUMP_ENABLED=false
dprop_enabled mimalloc && MIMALLOC_ENABLED=true
dprop_enabled jemalloc && JEMALLOC_ENABLED=true
if dprop_enabled dump; then
    DUMP_ENABLED=true
    JEMALLOC_ENABLED=true
fi

select_allocator

log_info "$PARSED"

mkdir -p "$DUMP_DIR/jeprof" "$DUMP_DIR/output/.done" "$DUMP_DIR/traces"

if [ "$DUMP_ENABLED" = true ] && [ "$SELECTED_ALLOC" = "jemalloc" ]; then
    start_heap_profiler
fi

if dprop_enabled analyse; then
    start_thread_watcher
fi

if dprop_enabled numa; then
    if command -v numactl >/dev/null 2>&1; then
        log_info "Using NUMA policy: interleave=all"
        exec env numactl --interleave=all ${PARSED}
    fi
    log_error "-Dnuma=true set but numactl not found, running without NUMA policy."
fi

exec env ${PARSED}
