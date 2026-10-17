#!/bin/bash

set -euo pipefail

# --- paths / config -----------------------------------------------------------
RUNTIME_DIR="/run/dank-fan-stats"
OUTPUT_PATH="$RUNTIME_DIR/stats.json"
CONTROL_FIFO="$RUNTIME_DIR/control"
TMP_PATH="$RUNTIME_DIR/stats.json.tmp"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-3}"
CLIENT_USER="${CLIENT_USER:-$(id -un 1000 2>/dev/null || echo root)}"
CLIENT_GROUP="${CLIENT_GROUP:-$(id -gn "$CLIENT_USER" 2>/dev/null || echo root)}"

EC_DIR="/sys/devices/platform/msi-ec"
EC_DEBUG_IO="/sys/kernel/debug/ec/ec0/io"

# MSI "advanced" fan curve lives in raw EC memory (no sysfs interface), the same
# layout MControlCenter uses. Reading works with ec_sys read-only; writing needs
# ec_sys write_support=1 (see /etc/modprobe.d/ec_sys.conf).
CURVE_CPU_TEMP=0x6A;   CURVE_CPU_TEMP_N=6
CURVE_CPU_SPEED=0x72;  CURVE_CPU_SPEED_N=7
CURVE_GPU_TEMP=0x82;   CURVE_GPU_TEMP_N=6
CURVE_GPU_SPEED=0x8A;  CURVE_GPU_SPEED_N=7

BAT_DIR=""
for _bat in /sys/class/power_supply/BAT*; do
    if [[ -e "$_bat" ]]; then
        BAT_DIR="$_bat"
        break
    fi
done

# --- runtime setup ------------------------------------------------------------
mkdir -p "$RUNTIME_DIR"
rm -f "$CONTROL_FIFO"
mkfifo "$CONTROL_FIFO"
chown "$CLIENT_USER:$CLIENT_GROUP" "$CONTROL_FIFO" 2>/dev/null || true
chmod 0620 "$CONTROL_FIFO"
exec 3<>"$CONTROL_FIFO"

# --- helpers ------------------------------------------------------------------
json_escape() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/ }
    value=${value//$'\r'/ }
    value=${value//$'\t'/ }
    printf '%s' "$value"
}

read_attr() {
    local path=$1 default=${2:-}
    if [[ -r "$path" ]]; then
        tr -d '\n' < "$path"
    else
        printf '%s' "$default"
    fi
}

num_attr() {
    local v
    v=$(read_attr "$1" "")
    if [[ "$v" =~ ^-?[0-9]+$ ]]; then
        printf '%s' "$v"
    else
        printf '%s' "${2:-0}"
    fi
}

json_array() {
    local path=$1 first=1 item
    printf '['
    if [[ -r "$path" ]]; then
        while IFS= read -r item; do
            [[ -z "$item" ]] && continue
            [[ $first -eq 1 ]] || printf ','
            printf '"%s"' "$(json_escape "$item")"
            first=0
        done < "$path"
    fi
    printf ']'
}

is_on() {
    case "${1,,}" in
        on|1|true|enabled|yes) return 0 ;;
        *) return 1 ;;
    esac
}

toggle_value() {
    if is_on "$1"; then printf 'off'; else printf 'on'; fi
}

valid_choice() {
    local value=$1 path=$2
    [[ -r "$path" ]] && grep -qxF -- "$value" "$path"
}

read_ec_byte() {
    local addr=$1
    dd if="$EC_DEBUG_IO" bs=1 count=1 skip=$((addr)) 2>/dev/null | od -An -tx1 | tr -d ' '
}

read_ec_dec() {
    local h
    h=$(read_ec_byte "$1")
    if [[ "$h" =~ ^[0-9a-fA-F]{1,2}$ ]]; then
        printf '%s' $((16#$h))
    else
        printf '0'
    fi
}

ec_range_json() {
    local start=$1 count=$2 i first=1
    printf '['
    for ((i = 0; i < count; i++)); do
        [[ $first -eq 1 ]] || printf ','
        printf '%s' "$(read_ec_dec $((start + i)))"
        first=0
    done
    printf ']'
}

write_ec_byte() {
    local addr=$1 value=$2
    [[ -w "$EC_DEBUG_IO" ]] || return 1
    printf "\\x$(printf '%02x' $((value)))" | \
        dd of="$EC_DEBUG_IO" bs=1 seek=$((addr)) count=1 conv=notrunc 2>/dev/null
}

# Validate a comma separated list: count, 0..100 range, ordered (temps strictly
# ascending, speeds non-decreasing). Returns non-zero on any violation.
valid_curve_list() {
    local csv=$1 count=$2 mode=$3 i v prev=-1
    local -a vals
    IFS=',' read -r -a vals <<< "$csv"
    [[ ${#vals[@]} -eq $count ]] || return 1
    for i in "${!vals[@]}"; do
        v=${vals[$i]}
        [[ "$v" =~ ^[0-9]+$ ]] || return 1
        (( v >= 0 && v <= 100 )) || return 1
        if [[ $i -gt 0 ]]; then
            if [[ "$mode" == "temp" ]]; then
                (( v > prev )) || return 1
            else
                (( v >= prev )) || return 1
            fi
        fi
        prev=$v
    done
}

write_ec_range() {
    local start=$1 i=0 v
    shift
    for v in "$@"; do
        write_ec_byte $((start + i)) "$v"
        i=$((i + 1))
    done
}

# Apply a full CPU+GPU curve. Speeds are written before temperatures so the EC
# never sees a hard temperature with a stale low speed.
apply_fan_curve() {
    local cpu_temps=$1 cpu_speeds=$2 gpu_temps=$3 gpu_speeds=$4
    valid_curve_list "$cpu_temps" "$CURVE_CPU_TEMP_N" temp || return 0
    valid_curve_list "$cpu_speeds" "$CURVE_CPU_SPEED_N" speed || return 0
    valid_curve_list "$gpu_temps" "$CURVE_GPU_TEMP_N" temp || return 0
    valid_curve_list "$gpu_speeds" "$CURVE_GPU_SPEED_N" speed || return 0
    [[ -w "$EC_DEBUG_IO" ]] || return 0

    local -a ct cs gt gs
    IFS=',' read -r -a ct <<< "$cpu_temps"
    IFS=',' read -r -a cs <<< "$cpu_speeds"
    IFS=',' read -r -a gt <<< "$gpu_temps"
    IFS=',' read -r -a gs <<< "$gpu_speeds"

    write_ec_range "$CURVE_CPU_SPEED" "${cs[@]}"
    write_ec_range "$CURVE_CPU_TEMP" "${ct[@]}"
    write_ec_range "$CURVE_GPU_SPEED" "${gs[@]}"
    write_ec_range "$CURVE_GPU_TEMP" "${gt[@]}"
}

fan_rpm() {
    if [[ ! -r "$EC_DEBUG_IO" ]]; then
        printf '0'
        return
    fi

    local fan_addr=0xC9 value_cd value_c9 low_hex high_hex value

    value_cd=$(read_ec_byte 0xCD)
    if [[ -z "$value_cd" || "$value_cd" == "00" ]]; then
        value_c9=$(read_ec_byte 0xC9)
        if [[ "$value_c9" =~ ^[0-9a-fA-F]{1,2}$ && "$value_c9" != "00" && $((16#$value_c9)) -lt 50 ]]; then
            fan_addr=0xCD
        fi
    fi

    low_hex=$(read_ec_byte "$fan_addr")
    high_hex=$(read_ec_byte $((fan_addr - 1)))
    if [[ ! "$low_hex" =~ ^[0-9a-fA-F]{1,2}$ || ! "$high_hex" =~ ^[0-9a-fA-F]{1,2}$ ]]; then
        printf '0'
        return
    fi

    value=$(((16#$high_hex << 8) | 16#$low_hex))
    if [[ "$value" -gt 0 ]]; then
        printf '%s' $((470000 / value))
    else
        printf '0'
    fi
}

# --- keyboard backlight LED ---------------------------------------------------
# MSI exposes the keyboard backlight as a standard LED class device
# (msiacpi::kbd_backlight), 0..max_brightness = off/low/med/high.
KBD_LED=""
for _led in /sys/class/leds/*kbd_backlight/brightness; do
    if [[ -r "$_led" ]]; then
        KBD_LED="$_led"
        break
    fi
done
KBD_MAX=0
if [[ -n "$KBD_LED" ]]; then
    KBD_MAX=$(num_attr "$(dirname "$KBD_LED")/max_brightness" 0)
fi

# --- writers ------------------------------------------------------------------
set_attr() {
    local path=$1 value=$2
    if [[ -w "$path" ]]; then
        printf '%s\n' "$value" > "$path" 2>/dev/null || true
    fi
}

set_bool_attr() {
    local path=$1 value=${2,,}
    case "$value" in
        toggle)
            set_attr "$path" "$(toggle_value "$(read_attr "$path" off)")"
            ;;
        on|off)
            set_attr "$path" "$value"
            ;;
    esac
}

set_charge() {
    local key=$1 value=$2
    [[ "$value" =~ ^[0-9]+$ ]] || return 0
    (( value >= 0 && value <= 100 )) || return 0
    [[ -n "$BAT_DIR" ]] || return 0
    if [[ "$key" == "charge_start" ]]; then
        printf '%s\n' "$value" > "$BAT_DIR/charge_control_start_threshold" 2>/dev/null || true
    else
        printf '%s\n' "$value" > "$BAT_DIR/charge_control_end_threshold" 2>/dev/null || true
    fi
}

set_kbd_backlight() {
    local value=$1
    [[ -n "$KBD_LED" ]] || return 0
    [[ "$value" =~ ^[0-9]+$ ]] || return 0
    (( value >= 0 && value <= KBD_MAX )) || return 0
    printf '%s\n' "$value" > "$KBD_LED" 2>/dev/null || true
}

# --- json output --------------------------------------------------------------
write_json() {
    local error ok
    error=$(json_escape "${1:-}")
    if [[ -n "$error" ]]; then ok=false; else ok=true; fi

    cat > "$TMP_PATH" <<EOF
{
  "ok": $ok,
  "error": "$error",
  "fanRpm": $(fan_rpm),
  "cpuTemp": $(num_attr "$EC_DIR/cpu/realtime_temperature" 0),
  "gpuTemp": $(num_attr "$EC_DIR/gpu/realtime_temperature" 0),
  "cpuFan": $(num_attr "$EC_DIR/cpu/realtime_fan_speed" 0),
  "gpuFan": $(num_attr "$EC_DIR/gpu/realtime_fan_speed" 0),
  "fwVersion": "$(json_escape "$(read_attr "$EC_DIR/fw_version" "")")",
  "coolerBoost": "$(json_escape "$(read_attr "$EC_DIR/cooler_boost" off)")",
  "superBattery": "$(json_escape "$(read_attr "$EC_DIR/super_battery" off)")",
  "webcam": "$(json_escape "$(read_attr "$EC_DIR/webcam" "")")",
  "webcamBlock": "$(json_escape "$(read_attr "$EC_DIR/webcam_block" "")")",
  "fnKey": "$(json_escape "$(read_attr "$EC_DIR/fn_key" "")")",
  "winKey": "$(json_escape "$(read_attr "$EC_DIR/win_key" "")")",
  "shiftMode": "$(json_escape "$(read_attr "$EC_DIR/shift_mode" "")")",
  "shiftModes": $(json_array "$EC_DIR/available_shift_modes"),
  "fanMode": "$(json_escape "$(read_attr "$EC_DIR/fan_mode" "")")",
  "fanModes": $(json_array "$EC_DIR/available_fan_modes"),
  "curve": {
    "cpuTemps": $(ec_range_json "$CURVE_CPU_TEMP" "$CURVE_CPU_TEMP_N"),
    "cpuSpeeds": $(ec_range_json "$CURVE_CPU_SPEED" "$CURVE_CPU_SPEED_N"),
    "gpuTemps": $(ec_range_json "$CURVE_GPU_TEMP" "$CURVE_GPU_TEMP_N"),
    "gpuSpeeds": $(ec_range_json "$CURVE_GPU_SPEED" "$CURVE_GPU_SPEED_N")
  },
  "chargeStart": $(num_attr "$BAT_DIR/charge_control_start_threshold" 0),
  "chargeEnd": $(num_attr "$BAT_DIR/charge_control_end_threshold" 100),
  "kbdBacklight": $(num_attr "${KBD_LED:-/nonexistent}" 0),
  "kbdBacklightMax": $KBD_MAX
}
EOF

    chmod 0644 "$TMP_PATH"
    mv "$TMP_PATH" "$OUTPUT_PATH"
}

refresh_stats() {
    if [[ ! -e "$EC_DIR" ]]; then
        write_json "msi-ec driver is not loaded"
        return
    fi
    write_json ""
}

# --- command handling ---------------------------------------------------------
handle_command() {
    local line=$1
    local -a parts
    read -r -a parts <<< "$line"

    local action=${parts[0]:-}
    local key=${parts[1]:-}
    local value=${parts[2]:-}

    case "${action,,}" in
        refresh|"") ;;
        toggle)
            # legacy "toggle" -> cooler boost
            case "${key,,}" in
                ""|cooler_boost) set_bool_attr "$EC_DIR/cooler_boost" toggle ;;
                super_battery)   set_bool_attr "$EC_DIR/super_battery" toggle ;;
                webcam)          set_bool_attr "$EC_DIR/webcam" toggle ;;
                webcam_block)    set_bool_attr "$EC_DIR/webcam_block" toggle ;;
            esac
            ;;
        set)
            case "${key,,}" in
                cooler_boost|super_battery|webcam|webcam_block)
                    set_bool_attr "$EC_DIR/${key,,}" "$value"
                    ;;
                shift_mode)
                    valid_choice "$value" "$EC_DIR/available_shift_modes" && set_attr "$EC_DIR/shift_mode" "$value"
                    ;;
                fan_mode)
                    valid_choice "$value" "$EC_DIR/available_fan_modes" && set_attr "$EC_DIR/fan_mode" "$value"
                    ;;
                fan_curve)
                    apply_fan_curve "${parts[2]:-}" "${parts[3]:-}" "${parts[4]:-}" "${parts[5]:-}"
                    ;;
                advanced)
                    case "${value,,}" in
                        on|true|1)
                            valid_choice advanced "$EC_DIR/available_fan_modes" && set_attr "$EC_DIR/fan_mode" advanced
                            ;;
                        off|false|0)
                            set_attr "$EC_DIR/fan_mode" auto
                            ;;
                    esac
                    ;;
                fn_key|win_key)
                    case "${value,,}" in
                        left|right) set_attr "$EC_DIR/${key,,}" "${value,,}" ;;
                    esac
                    ;;
                charge_start|charge_end)
                    set_charge "${key,,}" "$value"
                    ;;
                kbd_backlight|backlight|keyboard_backlight)
                    set_kbd_backlight "$value"
                    ;;
            esac
            ;;
    esac

    refresh_stats
}

refresh_stats

while true; do
    if IFS= read -r -t "$REFRESH_INTERVAL" -u 3 line; then
        if [[ -n "${line:-}" ]]; then
            handle_command "$line"
        fi
    else
        refresh_stats
    fi
done
