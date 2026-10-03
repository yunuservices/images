# Keep every node and edge so slow, small leaks stay visible in the graph.
JEPROF_OPTS=${JEPROF_OPTS:---show_bytes --nodefraction=0 --edgefraction=0 --maxdegree=20}

# Converts every new jemalloc heap dump into a GIF in the background.
start_heap_profiler() {
    log_info "jemalloc profiling enabled (dumps → $DUMP_DIR)"
    if ! command -v jeprof >/dev/null 2>&1 || ! command -v dot >/dev/null 2>&1; then
        log_info "jeprof or dot not found, heap GIF conversion disabled."
        return
    fi

    (
        java_bin=$(readlink -f "$(command -v java)")
        [ -n "$java_bin" ] || exit 0
        while :; do
            for heap_file in "$DUMP_DIR"/jeprof/*.heap; do
                [ -f "$heap_file" ] || continue
                name=${heap_file##*/}
                if [ ! -f "$DUMP_DIR/output/.done/$name" ]; then
                    # shellcheck disable=SC2086
                    if jeprof $JEPROF_OPTS --gif "$java_bin" "$heap_file" > "$DUMP_DIR/output/$name.gif"; then
                        : > "$DUMP_DIR/output/.done/$name" || true
                    fi
                fi
            done
            [ -d "$DUMP_DIR" ] || exit 0
            sleep 10 || exit 0
        done
    ) >> "$DUMP_DIR/loop.log" 2>&1 &
}
