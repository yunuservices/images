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

DUMP_VALUE=$(to_lower "$(extract_dprop dump)")
DUMP_ENABLED=false
if is_true "$DUMP_VALUE"; then
    DUMP_ENABLED=true
    JEMALLOC_ENABLED=true
fi

ANALYSE_VALUE=$(to_lower "$(extract_dprop analyse)")
ANALYSE_ENABLED=false
if is_true "$ANALYSE_VALUE"; then
    ANALYSE_ENABLED=true
fi

KEYWORD=$(extract_dprop keyword)
if [ -z "$KEYWORD" ]; then
    KEYWORD="Can't"
fi
KEYWORD=$(printf '%s' "$KEYWORD" | tr '_' ' ')

INTERVAL=$(extract_dprop interval)
case "$INTERVAL" in
    ''|*[!0-9]*)
        INTERVAL=5
        ;;
esac
if [ "$INTERVAL" -lt 1 ] 2>/dev/null; then
    INTERVAL=5
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

if [ "$SELECTED_ALLOC" = "jemalloc" ]; then
    MALLOC_CONF_OPTS="background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0,tcache_max:1024"
    if [ "$DUMP_ENABLED" = true ]; then
        MALLOC_CONF_OPTS="$MALLOC_CONF_OPTS,prof:true,lg_prof_interval:31,lg_prof_sample:17,prof_prefix:/home/container/dumps/jeprof"
    fi
    if [ -n "${MALLOC_CONF:-}" ]; then
        export MALLOC_CONF="$MALLOC_CONF_OPTS,${MALLOC_CONF}"
    else
        export MALLOC_CONF="$MALLOC_CONF_OPTS"
    fi
    printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUsing allocator: jemalloc (RSS tuned)\n"
fi

NUMA_VALUE=$(to_lower "$(extract_dprop numa)")
NUMA_ENABLED=false
if is_true "$NUMA_VALUE"; then
    NUMA_ENABLED=true
fi

printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"

mkdir -p /home/container/dumps/jeprof /home/container/dumps/output /home/container/dumps/output/.done /home/container/dumps/traces

if [ "$DUMP_ENABLED" = true ] && [ "$SELECTED_ALLOC" = "jemalloc" ]; then
    printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mjemalloc profiling enabled (dumps → /home/container/dumps)\n"
    if command -v jeprof >/dev/null 2>&1 && command -v dot >/dev/null 2>&1; then
        (
            JAVA_BIN=$(command -v java)
            [ -n "$JAVA_BIN" ] || exit 0
            while :; do
                for heapfile in /home/container/dumps/jeprof/*.heap; do
                    [ -f "$heapfile" ] || continue
                    base=${heapfile##*/}
                    if [ ! -f "/home/container/dumps/output/.done/$base" ]; then
                        if jeprof --gif "$JAVA_BIN" "$heapfile" > "/home/container/dumps/output/$base.gif"; then
                            : > "/home/container/dumps/output/.done/$base" || true
                        fi
                    fi
                done
                [ -d /home/container/dumps ] || exit 0
                sleep 10 || exit 0
            done
        ) >> /home/container/dumps/loop.log 2>&1 &
    else
        printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mjeprof or dot not found, heap GIF conversion disabled.\n"
    fi
fi

if [ "$ANALYSE_ENABLED" = true ]; then
    if ! command -v jcmd >/dev/null 2>&1 && ! command -v jstack >/dev/null 2>&1; then
        printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mNeither jcmd nor jstack found, thread watcher disabled.\n"
    else
        printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mthread watcher enabled (keyword: %s)\n" "$KEYWORD"
        (
            WATCH_LOG="${LOG_FILE:-/home/container/logs/latest.log}"
            WATCH_OFFSET=0
            while :; do
                if [ -f "$WATCH_LOG" ]; then
                    FILE_SIZE=$(wc -c < "$WATCH_LOG" 2>/dev/null | tr -d ' ')
                    case "$FILE_SIZE" in
                        ''|*[!0-9]*)
                            FILE_SIZE=0
                            ;;
                    esac
                    if [ "$FILE_SIZE" -lt "$WATCH_OFFSET" ]; then
                        WATCH_OFFSET=0
                    fi
                    if [ "$FILE_SIZE" -gt "$WATCH_OFFSET" ]; then
                        if tail -c +$((WATCH_OFFSET + 1)) "$WATCH_LOG" 2>/dev/null | grep -F -q -- "$KEYWORD"; then
                            JVM_PID=$(pgrep -x java 2>/dev/null | head -n 1)
                            if [ -z "$JVM_PID" ]; then
                                JVM_PID=$(pgrep -f java 2>/dev/null | head -n 1)
                            fi
                            if [ -z "$JVM_PID" ]; then
                                for proc_dir in /proc/[0-9]*; do
                                    PROC_CMD=$(tr '\0' ' ' < "$proc_dir/cmdline" 2>/dev/null)
                                    case "${PROC_CMD%% *}" in
                                        */java|java)
                                            JVM_PID=${proc_dir#/proc/}
                                            break
                                            ;;
                                    esac
                                done
                            fi
                            if [ -n "$JVM_PID" ]; then
                                TRACE_FILE="/home/container/dumps/traces/trace-$(date -u +%Y%m%d-%H%M%S).txt"
                                if command -v jcmd >/dev/null 2>&1; then
                                    jcmd "$JVM_PID" Thread.print > "$TRACE_FILE" 2>/dev/null || true
                                elif command -v jstack >/dev/null 2>&1; then
                                    jstack "$JVM_PID" > "$TRACE_FILE" 2>/dev/null || true
                                fi
                            fi
                        fi
                        WATCH_OFFSET=$FILE_SIZE
                    fi
                fi
                sleep "$INTERVAL" || exit 0
            done
        ) >> /home/container/dumps/watcher.log 2>&1 &
    fi
fi

if [ "$NUMA_ENABLED" = true ]; then
    if command -v numactl >/dev/null 2>&1; then
        printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUsing NUMA policy: interleave=all\n"
        exec env numactl --interleave=all ${PARSED}
    else
        printf "\033[1m\033[31mcontainer@pterodactyl~ \033[0m-Dnuma=true set but numactl not found, running without NUMA policy.\n"
    fi
fi

exec env ${PARSED}