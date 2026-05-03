#!/bin/bash

set -euo pipefail

RUNTIME_DIR="/run/dank-fan-stats"
OUTPUT_PATH="$RUNTIME_DIR/stats.json"
CONTROL_FIFO="$RUNTIME_DIR/control"
TMP_PATH="$RUNTIME_DIR/stats.json.tmp"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-3}"
CLIENT_USER="${CLIENT_USER:-spreadsheets600}"

mkdir -p "$RUNTIME_DIR"
rm -f "$CONTROL_FIFO"
mkfifo "$CONTROL_FIFO"
chown "$CLIENT_USER:$CLIENT_USER" "$CONTROL_FIFO"
chmod 0620 "$CONTROL_FIFO"
exec 3<>"$CONTROL_FIFO"

read_ec_byte() {
    local addr=$1
    dd if=/sys/kernel/debug/ec/ec0/io bs=1 count=1 skip=$((addr)) 2>/dev/null | od -An -tx1 | tr -d ' '
}

json_escape() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/ }
    printf '%s' "$value"
}

cooler_boost_state() {
    if [[ -r /sys/devices/platform/msi-ec/cooler_boost ]]; then
        local raw
        raw=$(< /sys/devices/platform/msi-ec/cooler_boost)
        case "${raw,,}" in
            on|1|true|enabled)
                printf 'on'
                return
                ;;
        esac
    fi
    printf 'off'
}

write_json() {
    local ok=$1
    local fan_rpm=$2
    local cooler_boost=$3
    local error
    error=$(json_escape "$4")

    cat > "$TMP_PATH" <<EOF
{
  "ok": $ok,
  "fanRpm": $fan_rpm,
  "coolerBoost": "$cooler_boost",
  "error": "$error"
}
EOF

    chmod 0644 "$TMP_PATH"
    mv "$TMP_PATH" "$OUTPUT_PATH"
}

refresh_stats() {
    local fan_addr value_cd value_c9 low_hex high_hex low high value fan_rpm boost

    if [[ ! -r /sys/kernel/debug/ec/ec0/io ]]; then
        write_json false 0 "$(cooler_boost_state)" "EC debugfs path is not readable"
        return
    fi

    fan_addr=0xC9
    value_cd=$(read_ec_byte 0xCD)

    if [[ -z "$value_cd" || "$value_cd" == "00" ]]; then
        value_c9=$(read_ec_byte 0xC9)
        if [[ -n "$value_c9" && "$value_c9" != "00" && $((16#$value_c9)) -lt 50 ]]; then
            fan_addr=0xCD
        fi
    fi

    low_hex=$(read_ec_byte "$fan_addr")
    high_hex=$(read_ec_byte $((fan_addr - 1)))
    boost=$(cooler_boost_state)

    if [[ -z "$low_hex" || -z "$high_hex" ]]; then
        write_json false 0 "$boost" "Failed to read EC registers"
        return
    fi

    low=$((16#$low_hex))
    high=$((16#$high_hex))
    value=$(((high << 8) | low))
    fan_rpm=0

    if [[ "$value" -gt 0 ]]; then
        fan_rpm=$((470000 / value))
    fi

    write_json true "$fan_rpm" "$boost" ""
}

set_cooler_boost() {
    local desired=$1
    printf '%s\n' "$desired" > /sys/devices/platform/msi-ec/cooler_boost
}

handle_command() {
    local command=${1,,}
    case "$command" in
        toggle)
            if [[ "$(cooler_boost_state)" == "on" ]]; then
                set_cooler_boost off
            else
                set_cooler_boost on
            fi
            ;;
        on|off)
            set_cooler_boost "$command"
            ;;
    esac
    refresh_stats
}

refresh_stats

while true; do
    if IFS= read -r -t "$REFRESH_INTERVAL" -u 3 command; then
        if [[ -n "${command:-}" ]]; then
            handle_command "$command"
        fi
    else
        refresh_stats
    fi
done
