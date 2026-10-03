DUMP_DIR=/home/container/dumps

log_info() {
    printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$1"
}

log_error() {
    printf "\033[1m\033[31mcontainer@pterodactyl~ \033[0m%s\n" "$1"
}

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
    case "$(to_lower "$1")" in
        1|true|yes|on)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Prints the value of the last -D<key>=<value> in the startup command.
extract_dprop() {
    printf '%s' "$PARSED" | sed -n "s/.*-D$1=\([^ ]*\).*/\1/p" | tail -n1
}

dprop_enabled() {
    is_true "$(extract_dprop "$1")"
}
