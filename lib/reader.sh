#!/system/bin/sh
# Shared POSIX-shell helpers. No commands run when this file is sourced.

nru_config_paths() {
    printf '%s\n' \
        /system/etc/libnfc-nci.conf \
        /system/etc/nfc/libnfc-nci.conf \
        /vendor/etc/libnfc-nci.conf \
        /vendor/etc/nfc/libnfc-nci.conf \
        /product/etc/libnfc-nci.conf \
        /product/etc/nfc/libnfc-nci.conf \
        /system_ext/etc/libnfc-nci.conf \
        /system_ext/etc/nfc/libnfc-nci.conf
}

# 10 = no explicit setting; 11 = duplicate or unrecognized setting.
nru_read_mask() {
    awk '
        /^[[:space:]]*POLLING_TECH_MASK[[:space:]]*=/ {
            count++
            value = $0
            sub(/^[[:space:]]*POLLING_TECH_MASK[[:space:]]*=[[:space:]]*/, "", value)
            sub(/#.*/, "", value)
            sub(/[[:space:]]+$/, "", value)
            if (value !~ /^(0[xX][0-9a-fA-F]+|[0-9]+)$/) invalid = 1
        }
        END {
            if (!count) exit 10
            if (count != 1 || invalid) exit 11
            print value
        }
    ' "$1"
}

# Bound arithmetic to an unsigned 16-bit mask, including on ARM32 shells.
nru_mask_number() {
    case "$1" in
        0[xX]*)
            nru_digits=${1#??}
            case "$nru_digits" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
            [ "${#nru_digits}" -le 4 ] || return 1
            nru_number=$((0x$nru_digits))
            ;;
        *)
            case "$1" in ''|*[!0-9]*) return 1 ;; esac
            nru_digits=$(printf '%s' "$1" | sed 's/^0*//')
            [ -n "$nru_digits" ] || nru_digits=0
            [ "${#nru_digits}" -le 5 ] || return 1
            nru_number=$((nru_digits + 0))
            ;;
    esac
    [ "$nru_number" -le 65535 ] || return 1
    printf '%s\n' "$nru_number"
}

nru_module_relative() {
    case "$1" in
        /system/etc/*) printf '%s\n' "system/etc/${1#/system/etc/}" ;;
        /vendor/etc/*|/product/etc/*|/system_ext/etc/*) printf 'system%s\n' "$1" ;;
        *) return 1 ;;
    esac
}

# Preserve the complete source when already enabled. Otherwise replace only
# the numeric token, retaining whitespace, comments, and unrelated settings.
nru_patch_config() {
    nru_source=$1
    nru_target=$2
    nru_old=$(nru_read_mask "$nru_source") || return 1
    nru_old_number=$(nru_mask_number "$nru_old") || return 1
    nru_new_number=$((nru_old_number | 15))
    mkdir -p "${nru_target%/*}" || return 1
    if [ "$nru_old_number" -eq "$nru_new_number" ]; then
        cp "$nru_source" "$nru_target" || return 1
    else
        nru_new=$(printf '0x%02X' "$nru_new_number") || return 1
        nru_last=$(tail -c 1 "$nru_source") || return 1
        nru_final_newline=0
        [ -n "$nru_last" ] || nru_final_newline=1
        awk -v replacement="$nru_new" -v final_newline="$nru_final_newline" '
            /^[[:space:]]*POLLING_TECH_MASK[[:space:]]*=/ {
                match($0, /=[[:space:]]*(0[xX][0-9a-fA-F]+|[0-9]+)/)
                token = substr($0, RSTART, RLENGTH)
                sub(/(0[xX][0-9a-fA-F]+|[0-9]+)$/, replacement, token)
                $0 = substr($0, 1, RSTART - 1) token substr($0, RSTART + RLENGTH)
            }
            {
                if (NR > 1) printf "%s\n", previous
                previous = $0
            }
            END {
                if (NR) printf "%s", previous
                if (NR && final_newline) printf "\n"
            }
        ' "$nru_source" > "$nru_target" || return 1
    fi
    nru_verified=$(nru_read_mask "$nru_target") || return 1
    nru_verified_number=$(nru_mask_number "$nru_verified") || return 1
    [ "$nru_verified_number" -eq "$nru_new_number" ]
}
