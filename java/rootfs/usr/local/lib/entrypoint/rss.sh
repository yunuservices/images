# shellcheck shell=sh

RSS_CSV="$DUMP_DIR/rss.csv"

# Prints one CSV row with the memory, thread and file descriptor counts of a process.
rss_sample() {
    awk -v time="$(date -u +%Y-%m-%dT%H:%M:%SZ)" -v fds="$2" '
        /^VmRSS:/ { rss = $2 }
        /^RssAnon:/ { anon = $2 }
        /^RssFile:/ { file = $2 }
        /^Threads:/ { threads = $2 }
        END { printf "%s,%s,%s,%s,%s,%s\n", time, rss, anon, file, threads, fds }
    ' "/proc/$1/status"
}

# Appends a sample of the JVM process to rss.csv every interval.
start_rss_recorder() {
    interval=$(extract_dprop rssinterval)
    case "$interval" in
        ''|*[!0-9]*|0)
            interval=60
            ;;
    esac

    log_info "RSS recording enabled (every ${interval}s → $RSS_CSV)"
    (
        reset_allocator_env
        [ -f "$RSS_CSV" ] || echo "time,vm_rss_kb,rss_anon_kb,rss_file_kb,threads,open_fds" > "$RSS_CSV"
        pid=""
        while [ -z "$pid" ]; do
            sleep 1 || exit 0
            pid=$(find_jvm_pid)
        done
        while [ -d "/proc/$pid" ]; do
            fds=$(ls "/proc/$pid/fd" 2>/dev/null | wc -l)
            rss_sample "$pid" "$fds" >> "$RSS_CSV"
            sleep "$interval" || exit 0
        done
    ) >> "$DUMP_DIR/rss.log" 2>&1 &
}
