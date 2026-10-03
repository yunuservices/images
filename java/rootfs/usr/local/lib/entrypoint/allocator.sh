JEMALLOC_LIB=/usr/local/lib/libjemalloc.so
MIMALLOC_LIB=/usr/local/lib/libmimalloc.so
JEMALLOC_DEFAULT_CONF="background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0,tcache_max:1024"
# The JVM usually runs as PID 1, so a start timestamp keeps dump names unique
# across restarts.
JEMALLOC_PROFILING_CONF="prof:true,lg_prof_interval:31,lg_prof_sample:17,prof_prefix:$DUMP_DIR/jeprof/jeprof-$(date -u +%Y%m%d-%H%M%S)"

# Sets SELECTED_ALLOC and exports LD_PRELOAD and MALLOC_CONF for the chosen allocator.
select_allocator() {
    SELECTED_ALLOC=""
    selected_lib=""

    if [ "$MIMALLOC_ENABLED" = true ] && [ "$JEMALLOC_ENABLED" = true ]; then
        log_error "Both -Dmimalloc=true and -Djemalloc=true are set. Choose only one allocator."
    elif [ "$MIMALLOC_ENABLED" = true ]; then
        if [ -f "$MIMALLOC_LIB" ]; then
            SELECTED_ALLOC="mimalloc"
            selected_lib="$MIMALLOC_LIB"
        else
            log_error "-Dmimalloc=true set but libmimalloc.so not found."
        fi
    elif [ "$JEMALLOC_ENABLED" = true ]; then
        if [ -f "$JEMALLOC_LIB" ]; then
            SELECTED_ALLOC="jemalloc"
            selected_lib="$JEMALLOC_LIB"
        else
            log_error "-Djemalloc=true set but libjemalloc.so not found."
        fi
    else
        log_info "Using default(malloc) allocator"
    fi

    if [ -n "$selected_lib" ]; then
        export LD_PRELOAD="$selected_lib${LD_PRELOAD:+:$LD_PRELOAD}"
        log_info "Using allocator: $SELECTED_ALLOC"
    fi

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
