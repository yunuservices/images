# shellcheck shell=sh

ASYNC_PROFILER_DIR=/opt/async-profiler
NATIVEMEM_DIR="$DUMP_DIR/nativemem"

# Loads async-profiler as an agent that records native allocations, starting a
# new recording file every interval.
enable_nativemem_profiler() {
    if [ ! -f "$ASYNC_PROFILER_DIR/lib/libasyncProfiler.so" ]; then
        log_error "-Dnativemem=true set but async-profiler not found."
        return 1
    fi

    interval=$(extract_dprop nativememinterval)
    case "$interval" in
        ''|*[!0-9]*|0)
            interval=3600
            ;;
    esac

    mkdir -p "$NATIVEMEM_DIR"
    agent="$ASYNC_PROFILER_DIR/lib/libasyncProfiler.so=start,event=nativemem,nativemem=128k,loop=${interval}s,file=$NATIVEMEM_DIR/nativemem-%t.jfr"
    if ! add_jvm_options "-agentpath:$agent"; then
        log_error "-Dnativemem=true needs the startup command to start with java, native memory profiling disabled."
        return 1
    fi
    log_info "native memory profiling enabled (new recording every ${interval}s → $NATIVEMEM_DIR)"
}

# Converts finished recordings into leak flame graphs. The newest recording is
# still being written, so it is skipped until a newer one exists.
start_nativemem_converter() {
    (
        reset_allocator_env
        while :; do
            newest=$(ls "$NATIVEMEM_DIR"/*.jfr 2>/dev/null | sort | tail -n 1)
            for recording in "$NATIVEMEM_DIR"/*.jfr; do
                [ -f "$recording" ] || continue
                [ "$recording" != "$newest" ] || continue
                report="${recording%.jfr}-leaks.html"
                [ -f "$report" ] && continue
                "$ASYNC_PROFILER_DIR/bin/jfrconv" --nativemem --leak "$recording" "$report"
            done
            sleep 60 || exit 0
        done
    ) >> "$NATIVEMEM_DIR/converter.log" 2>&1 &
}
