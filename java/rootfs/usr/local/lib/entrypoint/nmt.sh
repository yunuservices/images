# shellcheck shell=sh
enable_native_memory_tracking() {
    if ! add_jvm_options -XX:NativeMemoryTracking=summary; then
        log_error "-Dnmt=true needs the startup command to start with java, NMT disabled."
        return 1
    fi
}

# Takes an NMT baseline once the JVM is up, then writes a summary diff against
# it every interval.
start_nmt_reporter() {
    if ! command -v jcmd >/dev/null 2>&1; then
        log_info "jcmd not found, NMT reports disabled."
        return
    fi

    interval=$(extract_dprop nmtinterval)
    case "$interval" in
        ''|*[!0-9]*|0)
            interval=300
            ;;
    esac

    mkdir -p "$DUMP_DIR/nmt"
    log_info "native memory tracking enabled (report every ${interval}s → $DUMP_DIR/nmt)"
    (
        pid=""
        while [ -z "$pid" ]; do
            sleep 5 || exit 0
            pid=$(find_jvm_pid)
        done
        until jcmd "$pid" VM.native_memory baseline >/dev/null 2>&1; do
            [ -d "/proc/$pid" ] || exit 0
            sleep 5 || exit 0
        done
        while :; do
            sleep "$interval" || exit 0
            [ -d "/proc/$pid" ] || exit 0
            jcmd "$pid" VM.native_memory summary.diff > "$DUMP_DIR/nmt/nmt-$(date -u +%Y%m%d-%H%M%S).txt" 2>&1
        done
    ) >> "$DUMP_DIR/nmt.log" 2>&1 &
}
