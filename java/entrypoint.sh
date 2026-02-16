#!/bin/sh

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

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
    case "$(to_lower "$1")" in
        1|true|yes|on)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

extract_dprop() {
    key="$1"
    printf '%s' "$PARSED" | sed -n "s/.*-D${key}=\([^ ]*\).*/\1/p" | tail -n1
}

MIMALLOC_VALUE=$(to_lower "$(extract_dprop mimalloc)")
JEMALLOC_VALUE=$(to_lower "$(extract_dprop jemalloc)")

MIMALLOC_ENABLED=false
if is_true "$MIMALLOC_VALUE"; then
    MIMALLOC_ENABLED=true
fi

JEMALLOC_ENABLED=false
if is_true "$JEMALLOC_VALUE"; then
    JEMALLOC_ENABLED=true
fi

SELECTED_ALLOC=""
SELECTED_LIB=""

if [ "$MIMALLOC_ENABLED" = true ] && [ "$JEMALLOC_ENABLED" = true ]; then
    printf "\033[1m\033[31mcontainer@pterodactyl~ \033[0mBoth -Dmimalloc=true and -Djemalloc=true are set. Choose only one allocator.\n"
elif [ "$MIMALLOC_ENABLED" = true ]; then
    if [ -f /usr/local/lib/libmimalloc.so ]; then
        SELECTED_ALLOC="mimalloc"
        SELECTED_LIB="/usr/local/lib/libmimalloc.so"
    else
        printf "\033[1m\033[31mcontainer@pterodactyl~ \033[0m-Dmimalloc=true set but libmimalloc.so not found.\n"
    fi
elif [ "$JEMALLOC_ENABLED" = true ]; then
    if [ -f /usr/local/lib/libjemalloc.so ]; then
        SELECTED_ALLOC="jemalloc"
        SELECTED_LIB="/usr/local/lib/libjemalloc.so"
    else
        printf "\033[1m\033[31mcontainer@pterodactyl~ \033[0m-Djemalloc=true set but libjemalloc.so not found.\n"
    fi
else
    printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUsing default(malloc) allocator\n"
fi

if [ -n "$SELECTED_LIB" ]; then
    if [ -n "${LD_PRELOAD:-}" ]; then
        export LD_PRELOAD="$SELECTED_LIB:${LD_PRELOAD}"
    else
        export LD_PRELOAD="$SELECTED_LIB"
    fi
    printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUsing allocator: %s\n" "$SELECTED_ALLOC"
fi

NUMA_VALUE=$(to_lower "$(extract_dprop numa)")
NUMA_ENABLED=false
if is_true "$NUMA_VALUE"; then
    NUMA_ENABLED=true
fi

printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"

if [ "$NUMA_ENABLED" = true ]; then
    if command -v numactl >/dev/null 2>&1; then
        printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUsing NUMA policy: interleave=all\n"
        exec env numactl --interleave=all ${PARSED}
    else
        printf "\033[1m\033[31mcontainer@pterodactyl~ \033[0m-Dnuma=true set but numactl not found, running without NUMA policy.\n"
    fi
fi

exec env ${PARSED}