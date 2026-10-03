# Keep every node and edge so slow, small leaks stay visible in the graph.
JEPROF_OPTS=${JEPROF_OPTS:---show_bytes --nodefraction=0 --edgefraction=0 --maxdegree=20}

# Lists heap dumps oldest first. Names follow jeprof-<start>.<pid>.<seq>.<kind>.heap
# and <seq> is not zero padded, so it is sorted numerically within each run.
list_heap_dumps() {
    ls "$DUMP_DIR"/jeprof/*.heap 2>/dev/null | sort -t. -k1,1 -k2,2n -k3,3n
}

# Prints the jeprof-<start>.<pid> part that identifies a single JVM run.
run_id() {
    printf '%s' "${1##*/}" | cut -d. -f1-2
}

render_gif() {
    # shellcheck disable=SC2086
    jeprof $JEPROF_OPTS --gif "$@"
}

# Converts every new jemalloc heap dump into a GIF in the background. With
# diff enabled, each dump is also rendered against the previous dump of the
# same JVM so only the growth between them shows up.
start_heap_profiler() {
    log_info "jemalloc profiling enabled (dumps → $DUMP_DIR)"
    if ! command -v jeprof >/dev/null 2>&1 || ! command -v dot >/dev/null 2>&1; then
        log_info "jeprof or dot not found, heap GIF conversion disabled."
        return
    fi

    diff_enabled=false
    if dprop_enabled diff; then
        diff_enabled=true
        log_info "jeprof diff GIFs enabled"
    fi

    (
        java_bin=$(readlink -f "$(command -v java)")
        [ -n "$java_bin" ] || exit 0
        previous=""
        while :; do
            for heap_file in $(list_heap_dumps); do
                name=${heap_file##*/}
                if [ ! -f "$DUMP_DIR/output/.done/$name" ]; then
                    if render_gif "$java_bin" "$heap_file" > "$DUMP_DIR/output/$name.gif"; then
                        : > "$DUMP_DIR/output/.done/$name" || true
                    fi
                    if [ "$diff_enabled" = true ] && [ -f "$previous" ] \
                        && [ "$(run_id "$previous")" = "$(run_id "$heap_file")" ]; then
                        render_gif --base="$previous" "$java_bin" "$heap_file" > "$DUMP_DIR/output/$name.diff.gif"
                    fi
                fi
                previous=$heap_file
            done
            [ -d "$DUMP_DIR" ] || exit 0
            sleep 10 || exit 0
        done
    ) >> "$DUMP_DIR/loop.log" 2>&1 &
}
