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

trace_file_name() {
    printf '%s' "$DUMP_DIR/traces/trace-$(date -u +%Y%m%d-%H%M%S).txt"
}

# Writes a thread dump of the JVM to the given file.
write_thread_dump() {
    pid=$(find_jvm_pid)
    [ -n "$pid" ] || return 1
    if command -v jcmd >/dev/null 2>&1; then
        jcmd "$pid" Thread.print > "$1" 2>/dev/null
    else
        jstack "$pid" > "$1" 2>/dev/null
    fi
}

# Writes a thread dump whenever the keyword shows up in new log output.
watch_log() {
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
                    write_thread_dump "$(trace_file_name)" || true
                fi
                offset=$size
            fi
        fi
        sleep "$interval" || exit 0
    done
}

# Takes a thread dump every interval and keeps it only when a stack frame
# contains the keyword, e.g. a native method such as java.util.zip.Inflater.
watch_stacks() {
    pending="$DUMP_DIR/traces/.pending"
    while :; do
        sleep "$interval" || exit 0
        write_thread_dump "$pending" || continue
        if grep -F -q -- "$keyword" "$pending"; then
            mv "$pending" "$(trace_file_name)"
        fi
    done
}

# Starts the thread watcher in "log" or "stack" mode.
start_thread_watcher() {
    mode=$1
    if ! command -v jcmd >/dev/null 2>&1 && ! command -v jstack >/dev/null 2>&1; then
        log_info "Neither jcmd nor jstack found, thread watcher disabled."
        return
    fi

    keyword=$(extract_dprop keyword | tr '_' ' ')
    interval=$(extract_dprop interval)

    if [ "$mode" = stack ]; then
        if [ -z "$keyword" ]; then
            log_error "-Danalyse=stack needs -Dkeyword=X, thread watcher disabled."
            return
        fi
        default_interval=30
    else
        [ -n "$keyword" ] || keyword="Can't"
        default_interval=5
    fi

    case "$interval" in
        ''|*[!0-9]*|0)
            interval=$default_interval
            ;;
    esac

    log_info "thread watcher enabled (mode: $mode, keyword: $keyword)"
    if [ "$mode" = stack ]; then
        watch_stacks >> "$DUMP_DIR/watcher.log" 2>&1 &
    else
        watch_log >> "$DUMP_DIR/watcher.log" 2>&1 &
    fi
}
