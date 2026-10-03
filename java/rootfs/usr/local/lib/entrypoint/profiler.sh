# shellcheck shell=sh
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

# Deletes all but the newest $1 converted dumps together with their reports.
prune_heap_dumps() {
    count=$(list_heap_dumps | wc -l)
    [ "$count" -gt "$1" ] || return 0
    list_heap_dumps | head -n $((count - $1)) | while read -r heap_file; do
        name=${heap_file##*/}
        [ -f "$DUMP_DIR/output/.done/$name" ] || continue
        rm -f "$heap_file" "$DUMP_DIR/output/$name".* "$DUMP_DIR/output/.done/$name"
    done
}

# Renders one heap dump into every requested format. Arguments: output path
# without extension, then the jeprof arguments.
render_reports() {
    output=$1
    shift
    status=0
    for format in $JEPROF_FORMATS; do
        case "$format" in
            txt)
                flag=--text
                ;;
            *)
                flag=--$format
                ;;
        esac
        # shellcheck disable=SC2086
        jeprof $JEPROF_OPTS "$flag" "$@" > "$output.$format" || status=1
    done
    return "$status"
}

# Reads -Djeprof_format=svg,gif,txt into JEPROF_FORMATS. Defaults to svg.
resolve_jeprof_formats() {
    JEPROF_FORMATS=""
    for format in $(extract_dprop jeprof_format | tr ',' ' '); do
        case "$format" in
            svg|gif|txt)
                JEPROF_FORMATS="$JEPROF_FORMATS $format"
                ;;
            *)
                log_error "Unknown jeprof format $format, use svg, gif or txt."
                ;;
        esac
    done
    [ -n "$JEPROF_FORMATS" ] || JEPROF_FORMATS=svg
}

# Converts every new jemalloc heap dump into reports in the background. With
# diff enabled, each dump is also rendered against the previous dump of the
# same JVM so only the growth between them shows up.
start_heap_profiler() {
    log_info "jemalloc profiling enabled (dumps → $DUMP_DIR)"
    if ! command -v jeprof >/dev/null 2>&1 || ! command -v dot >/dev/null 2>&1; then
        log_info "jeprof or dot not found, heap dump conversion disabled."
        return
    fi

    resolve_jeprof_formats
    log_info "jeprof report formats:$JEPROF_FORMATS"

    diff_enabled=false
    if dprop_enabled diff; then
        diff_enabled=true
        log_info "jeprof diff reports enabled"
    fi

    keep=$(extract_dprop keep)
    case "$keep" in
        ''|*[!0-9]*|0)
            keep=""
            ;;
        *)
            log_info "keeping the newest $keep heap dumps"
            ;;
    esac

    (
        reset_allocator_env
        java_bin=$(readlink -f "$(command -v java)")
        [ -n "$java_bin" ] || exit 0
        previous=""
        while :; do
            for heap_file in $(list_heap_dumps); do
                name=${heap_file##*/}
                if [ ! -f "$DUMP_DIR/output/.done/$name" ]; then
                    if render_reports "$DUMP_DIR/output/$name" "$java_bin" "$heap_file"; then
                        : > "$DUMP_DIR/output/.done/$name" || true
                    fi
                    if [ "$diff_enabled" = true ] && [ -f "$previous" ] \
                        && [ "$(run_id "$previous")" = "$(run_id "$heap_file")" ]; then
                        render_reports "$DUMP_DIR/output/$name.diff" --base="$previous" "$java_bin" "$heap_file"
                    fi
                fi
                previous=$heap_file
            done
            [ -d "$DUMP_DIR" ] || exit 0
            [ -z "$keep" ] || prune_heap_dumps "$keep"
            sleep 10 || exit 0
        done
    ) >> "$DUMP_DIR/loop.log" 2>&1 &
}
