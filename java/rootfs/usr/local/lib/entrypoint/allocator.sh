# shellcheck shell=sh
JEMALLOC_LIB=/usr/local/lib/libjemalloc.so
MIMALLOC_LIB=/usr/local/lib/libmimalloc.so
TCMALLOC_LIB=/usr/local/lib/libtcmalloc_minimal.so
JEMALLOC_DEFAULT_CONF="background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0,tcache_max:1024"
# The JVM usually runs as PID 1, so a start timestamp keeps dump names unique
# across restarts.
JEMALLOC_PROFILING_CONF="prof:true,lg_prof_interval:31,lg_prof_sample:17,prof_prefix:$DUMP_DIR/jeprof/jeprof-$(date -u +%Y%m%d-%H%M%S)"

# Sets SELECTED_ALLOC and exports LD_PRELOAD and MALLOC_CONF for the chosen allocator.
select_allocator() {
    SELECTED_ALLOC=""
    requested=""
    [ "$JEMALLOC_ENABLED" = true ] && requested="$requested jemalloc"
    [ "$MIMALLOC_ENABLED" = true ] && requested="$requested mimalloc"
    [ "$TCMALLOC_ENABLED" = true ] && requested="$requested tcmalloc"

    case "$requested" in
        '')
            log_info "Using default(malloc) allocator"
            return
            ;;
        *' '*' '*)
            log_error "Multiple allocators are set:$requested. Choose only one allocator."
            return
            ;;
    esac

    allocator=${requested# }
    case "$allocator" in
        jemalloc) lib="$JEMALLOC_LIB" ;;
        mimalloc) lib="$MIMALLOC_LIB" ;;
        tcmalloc) lib="$TCMALLOC_LIB" ;;
    esac
    if [ ! -f "$lib" ]; then
        log_error "-D$allocator=true set but ${lib##*/} not found."
        return
    fi

    SELECTED_ALLOC=$allocator
    export LD_PRELOAD="$lib${LD_PRELOAD:+:$LD_PRELOAD}"
    log_info "Using allocator: $SELECTED_ALLOC"

    if [ "$SELECTED_ALLOC" = "jemalloc" ]; then
        conf="$JEMALLOC_DEFAULT_CONF"
        if [ "$DUMP_ENABLED" = true ]; then
            conf="$conf,$JEMALLOC_PROFILING_CONF"
        fi
        # User options come last so they override the image defaults.
        export MALLOC_CONF="$conf${MALLOC_CONF:+,$MALLOC_CONF}"
        log_info "Using allocator: jemalloc (RSS tuned)"
    fi
}

# Caps glibc malloc arenas, which otherwise grow to 8 per CPU and inflate RSS
# in heavily threaded JVMs. Only applies to the default allocator.
apply_malloc_arena_limit() {
    arenas=$(extract_dprop arenas)
    [ -n "$arenas" ] || return 0
    case "$arenas" in
        *[!0-9]*|0)
            log_error "-Darenas=$arenas is not a positive number, ignoring it."
            return 0
            ;;
    esac
    if [ -n "$SELECTED_ALLOC" ]; then
        log_error "-Darenas only applies to the default allocator, ignoring it with $SELECTED_ALLOC."
        return 0
    fi
    export MALLOC_ARENA_MAX="$arenas"
    log_info "Using glibc malloc with at most $arenas arenas"
}
