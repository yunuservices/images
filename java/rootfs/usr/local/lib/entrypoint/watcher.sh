find_jvm_pid() {
    pid=$(pgrep -x java 2>/dev/null | head -n 1)
    if [ -z "$pid" ]; then
        pid=$(pgrep -f java 2>/dev/null | head -n 1)
    fi
    if [ -z "$pid" ]; then
        for proc_dir in /proc/[0-9]*; do
            cmdline=$(tr '\0' ' ' < "$proc_dir/cmdline" 2>/dev/null)
            case "${cmdline%% *}" in
                */java|java)
                    pid=${proc_dir#/proc/}
                    break
                    ;;
            esac
        done
    fi
    printf '%s' "$pid"
}

write_thread_dump() {
    pid=$(find_jvm_pid)
    [ -n "$pid" ] || return
    trace_file="$DUMP_DIR/traces/trace-$(date -u +%Y%m%d-%H%M%S).txt"
    if command -v jcmd >/dev/null 2>&1; then
        jcmd "$pid" Thread.print > "$trace_file" 2>/dev/null || true
    elif command -v jstack >/dev/null 2>&1; then
        jstack "$pid" > "$trace_file" 2>/dev/null || true
    fi
}

# Writes a thread dump whenever the keyword shows up in new log output.
start_thread_watcher() {
    if ! command -v jcmd >/dev/null 2>&1 && ! command -v jstack >/dev/null 2>&1; then
        log_info "Neither jcmd nor jstack found, thread watcher disabled."
        return
    fi

    keyword=$(extract_dprop keyword)
    keyword=$(printf '%s' "${keyword:-Can't}" | tr '_' ' ')

    interval=$(extract_dprop interval)
    case "$interval" in
        ''|*[!0-9]*|0)
            interval=5
            ;;
    esac

    log_info "thread watcher enabled (keyword: $keyword)"
    (
        log_file="${LOG_FILE:-/home/container/logs/latest.log}"
        offset=0
        while :; do
            if [ -f "$log_file" ]; then
                size=$(wc -c < "$log_file" 2>/dev/null | tr -d ' ')
                case "$size" in
                    ''|*[!0-9]*)
                        size=0
                        ;;
                esac
                # The log was rotated or truncated.
                if [ "$size" -lt "$offset" ]; then
                    offset=0
                fi
                if [ "$size" -gt "$offset" ]; then
                    if tail -c +$((offset + 1)) "$log_file" 2>/dev/null | grep -F -q -- "$keyword"; then
                        write_thread_dump
                    fi
                    offset=$size
                fi
            fi
            sleep "$interval" || exit 0
        done
    ) >> "$DUMP_DIR/watcher.log" 2>&1 &
}
