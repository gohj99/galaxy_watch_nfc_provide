#!/system/bin/sh
# Root-only, systemless NXP configuration storage. Never source the .conf itself.
gwn_state=/data/adb/galaxy_watch_nfc_provide
gwn_store=$gwn_state/config

gwn_error() { echo "nfcconf: $*" >&2; return 1; }
gwn_hash() { sha256sum "$1" | awk '{print $1}'; }
gwn_identity() { stat -c '%d:%i' "$1"; }

gwn_relative() {
    case "$1" in
        /vendor/etc/libnfc-nxp.conf|/vendor/etc/nfc/libnfc-nxp.conf)
            printf 'system%s\n' "$1" ;;
        /system/etc/libnfc-nxp.conf|/system/etc/nfc/libnfc-nxp.conf)
            printf '%s\n' "${1#/}" ;;
        *) gwn_error "Unsupported configuration path: $1" ;;
    esac
}

gwn_check_input() {
    [ -f "$1" ] && [ -r "$1" ] || { gwn_error 'Input must be a readable regular file'; return 1; }
    gwn_size=$(stat -c %s "$1") || return 1
    [ "$gwn_size" -gt 0 ] && [ "$gwn_size" -le 131072 ] || {
        gwn_error 'Input must contain 1..131072 bytes'; return 1;
    }
    # Basic format check only, not validation of every NCI parameter.
    [ "$(grep -c '^[[:space:]]*NXP_CORE_CONF[[:space:]]*=' "$1")" = 1 ] || {
        gwn_error 'Expected exactly one NXP_CORE_CONF setting'; return 1;
    }
}

gwn_load() {
    [ -d "$gwn_store" ] || { gwn_error 'Configuration backup is missing; reinstall the module'; return 1; }
    gwn_target=$(cat "$gwn_store/target-path") || return 1
    gwn_rel=$(gwn_relative "$gwn_target") || return 1
    gwn_source=$MODDIR/$gwn_rel
    [ "$(cat "$gwn_store/fingerprint")" = "$(getprop ro.build.fingerprint)" ] || {
        gwn_error 'Firmware changed; review the saved original before preparing a new backup'; return 1;
    }
    [ "$(gwn_hash "$gwn_store/original.conf")" = "$(cat "$gwn_store/original.sha256")" ] || {
        gwn_error 'Original backup hash mismatch'; return 1;
    }
    gwn_context=$(cat "$gwn_store/selinux-context") || return 1
    case "$gwn_context" in
        u:object_r:*:s0) ;;
        *) gwn_error 'Invalid saved SELinux context'; return 1 ;;
    esac
}

gwn_permissions() {
    [ -f "$gwn_source" ] && [ ! -L "$gwn_source" ] || {
        gwn_error 'Module configuration must be a regular file, not a symlink'; return 1;
    }
    chown 0:0 "$gwn_source" && chmod 0644 "$gwn_source" && chcon "$gwn_context" "$gwn_source"
}

gwn_prepare() {
    mkdir -p "$gwn_state" || return 1
    chmod 0700 "$gwn_state" || return 1
    if [ ! -e "$gwn_store" ]; then
        gwn_target=
        for gwn_candidate in /vendor/etc/libnfc-nxp.conf /vendor/etc/nfc/libnfc-nxp.conf \
                             /system/etc/libnfc-nxp.conf /system/etc/nfc/libnfc-nxp.conf; do
            if [ -f "$gwn_candidate" ] && gwn_check_input "$gwn_candidate"; then
                gwn_target=$gwn_candidate
                break
            fi
        done
        [ -n "$gwn_target" ] || { gwn_error 'No supported device NXP configuration found'; return 1; }
        # Refuse to call another module's overlay the original firmware file.
        gwn_mount_root=$(awk -v p="$gwn_target" '$5 == p {v=$4} END {print v}' /proc/1/mountinfo)
        case "$gwn_mount_root" in
            */modules/*|*/modules_update/*)
                gwn_error 'Existing configuration overlay found without an original backup'; return 1 ;;
        esac
        gwn_tmp=$gwn_state/.config-new.$$
        mkdir "$gwn_tmp" || return 1
        if ! { cp "$gwn_target" "$gwn_tmp/original.conf" &&
               gwn_hash "$gwn_tmp/original.conf" > "$gwn_tmp/original.sha256" &&
               printf '%s\n' "$gwn_target" > "$gwn_tmp/target-path" &&
               getprop ro.build.fingerprint > "$gwn_tmp/fingerprint" &&
               ls -Zd "$gwn_target" | awk '{print $1}' > "$gwn_tmp/selinux-context" &&
               chmod 0700 "$gwn_tmp" && chmod 0600 "$gwn_tmp/"* &&
               mv "$gwn_tmp" "$gwn_store"; }; then
            gwn_error "Backup preparation failed; preserved temporary data at $gwn_tmp"
            return 1
        fi
    fi
    gwn_load || return 1
    # On upgrade keep the currently visible edits, but never replace the original backup.
    if [ ! -e "$gwn_source" ]; then
        gwn_check_input "$gwn_target" || return 1
        mkdir -p "${gwn_source%/*}" || return 1
        cp "$gwn_target" "$gwn_source" || return 1
    fi
    gwn_permissions || return 1
    echo "CONFIG_PREPARED=$gwn_target"
    echo "ORIGINAL_BACKUP=$gwn_store/original.conf"
    echo "MODULE_COPY=$gwn_source"
}

gwn_mount_line() {
    awk -v p="$gwn_target" '$5 == p {v=$0} END {print v}' /proc/self/mountinfo
}

# Magic Mount-rs owns the actual mount. This helper only verifies its result;
# a second bind mount would bypass the metamodule's namespace and lifecycle.
gwn_mount() {
    [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || {
        gwn_error 'Module is disabled or scheduled for removal'; return 1;
    }
    gwn_load && gwn_permissions || return 1
    gwn_line=$(gwn_mount_line)
    [ "$(gwn_identity "$gwn_target")" = "$(gwn_identity "$gwn_source")" ] || {
        gwn_error 'Magic Mount-rs has not mounted the module copy at the target'; return 1;
    }
    [ -n "$gwn_line" ] || { gwn_error 'Target file mount is not visible'; return 1; }
    echo "CONFIG_SOURCE_WRITABLE=$gwn_source"
    echo "CONFIG_TARGET=$gwn_target"
    echo 'CONFIG_MOUNT_OWNER=magic_mount_rs'
    echo 'CONFIG_TARGET_MOUNT=read-only-by-manager; edit the module source inode'
}

gwn_status() {
    gwn_load || return 1
    echo "TARGET=$gwn_target"
    echo "MODULE_COPY=$gwn_source"
    echo "ORIGINAL_BACKUP=$gwn_store/original.conf"
    echo "ORIGINAL_SHA256=$(cat "$gwn_store/original.sha256")"
    echo "CURRENT_SHA256=$(gwn_hash "$gwn_target")"
    echo "MODULE_SHA256=$(gwn_hash "$gwn_source")"
    if [ "$(gwn_identity "$gwn_target")" = "$(gwn_identity "$gwn_source")" ]; then
        echo 'SAME_INODE=yes'
    else
        echo 'SAME_INODE=no'
    fi
    echo "FILE_MOUNT=$(gwn_mount_line)"
    ls -lZ "$gwn_target"
}
