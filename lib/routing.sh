#!/system/bin/sh
# Device-derived Samsung routing overlay; Magic Mount-rs owns every mount.
gwr_target=/system/etc/nfc_rule_configs.xml
gwr_store=$gwn_state/routing
gwr_source=$MODDIR/system/etc/nfc_rule_configs.xml

# Store the policy as opaque XML. Routing values belong to root-authorized apps;
# this is only a bounded format check, not a complete XML/policy validator.
gwr_check_input() {
    [ -f "$1" ] && [ -r "$1" ] || {
        gwn_error 'Routing input must be a readable regular file'; return 1;
    }
    gwr_size=$(stat -c %s "$1") || return 1
    [ "$gwr_size" -gt 0 ] && [ "$gwr_size" -le 131072 ] || {
        gwn_error 'Routing input must contain 1..131072 bytes'; return 1;
    }
    grep -q '<configurations[[:space:]>]' "$1" &&
    grep -q '</configurations[[:space:]]*>' "$1" || {
        gwn_error 'Routing input is missing its configurations root'; return 1;
    }
}

gwr_permissions() {
    [ -f "$gwr_source" ] && [ ! -L "$gwr_source" ] || {
        gwn_error 'Routing module copy must be a regular file, not a symlink'; return 1;
    }
    chown 0:0 "$gwr_source" && chmod 0644 "$gwr_source" && chcon "$gwr_context" "$gwr_source"
}

gwr_load() {
    [ -d "$gwr_store" ] || { gwn_error 'Samsung routing backup is missing'; return 1; }
    [ "$(cat "$gwr_store/fingerprint")" = "$(getprop ro.build.fingerprint)" ] || {
        gwn_error 'Firmware changed; review the saved Samsung routing original'; return 1;
    }
    [ "$(gwn_hash "$gwr_store/original.xml")" = "$(cat "$gwr_store/original.sha256")" ] || {
        gwn_error 'Samsung routing backup hash mismatch'; return 1;
    }
    gwr_context=$(cat "$gwr_store/selinux-context") || return 1
    case "$gwr_context" in
        u:object_r:*:s0) ;;
        *) gwn_error 'Invalid saved routing SELinux context'; return 1 ;;
    esac
}

gwr_prepare() {
    if [ ! -f "$gwr_target" ]; then
        echo 'ROUTING_CONFIG=not-applicable (no Samsung routing policy)'
        return 0
    fi
    gwr_check_input "$gwr_target" || return 1
    if [ ! -e "$gwr_store" ]; then
        gwr_mount_root=$(awk -v p="$gwr_target" '$5==p {v=$4} END {print v}' /proc/1/mountinfo)
        case "$gwr_mount_root" in
            */modules/*|*/modules_update/*)
                gwn_error 'Existing Samsung routing overlay found without an original backup'; return 1 ;;
        esac
        gwr_tmp=$gwn_state/.routing-new.$$
        mkdir "$gwr_tmp" || return 1
        if ! { cp "$gwr_target" "$gwr_tmp/original.xml" &&
               gwn_hash "$gwr_tmp/original.xml" > "$gwr_tmp/original.sha256" &&
               getprop ro.build.fingerprint > "$gwr_tmp/fingerprint" &&
               ls -Zd "$gwr_target" | awk '{print $1}' > "$gwr_tmp/selinux-context" &&
               chmod 0700 "$gwr_tmp" && chmod 0600 "$gwr_tmp/"* &&
               mv "$gwr_tmp" "$gwr_store"; }; then
            gwn_error "Routing backup failed; temporary data retained at $gwr_tmp"
            return 1
        fi
    fi
    gwr_load || return 1
    # Match NXP configuration handling: copy current bytes only for a new module
    # copy; never rewrite an existing root edit or relabel it as the original.
    [ ! -L "$gwr_source" ] || { gwn_error 'Routing module copy must not be a symlink'; return 1; }
    if [ ! -e "$gwr_source" ]; then
        gwr_previous=$(gwn_previous_module_source 'system/etc/nfc_rule_configs.xml' || true)
        if [ -n "$gwr_previous" ]; then
            gwr_check_input "$gwr_previous" || return 1
            gwr_copy_source=$gwr_previous
        else
            gwr_copy_source=$gwr_target
        fi
        mkdir -p "${gwr_source%/*}" || return 1
        cp "$gwr_copy_source" "$gwr_source" || return 1
    fi
    gwr_permissions || return 1
    echo "ROUTING_CONFIG_PREPARED=$gwr_target"
    echo 'ROUTING_CONFIG_POLICY=preserved; edited by root-authorized applications'
    echo "ROUTING_CONFIG_ORIGINAL=$gwr_store/original.xml"
}

gwr_status() {
    if [ ! -f "$gwr_target" ]; then
        echo 'ROUTING_CONFIG=not-applicable (no Samsung routing policy)'
        return 0
    fi
    gwr_load || return 1
    echo "ROUTING_CONFIG_TARGET=$gwr_target"
    echo "ROUTING_CONFIG_MODULE_COPY=$gwr_source"
    echo "ROUTING_CONFIG_ORIGINAL=$gwr_store/original.xml"
    echo "ROUTING_CONFIG_ORIGINAL_SHA256=$(cat "$gwr_store/original.sha256")"
    echo "ROUTING_CONFIG_CURRENT_SHA256=$(gwn_hash "$gwr_target")"
    echo "ROUTING_CONFIG_MODULE_SHA256=$(gwn_hash "$gwr_source")"
    gwr_check_input "$gwr_target" || return 1
    [ -f "$gwr_source" ] && [ ! -L "$gwr_source" ] || {
        gwn_error 'Routing module copy is missing or is a symlink'; return 1;
    }
    [ "$(gwn_identity "$gwr_target")" = "$(gwn_identity "$gwr_source")" ] || {
        gwn_error 'Magic Mount-rs has not activated the Samsung routing overlay; reboot required'; return 1;
    }
    echo 'ROUTING_CONFIG_SAME_INODE=yes'
    echo 'ROUTING_CONFIG_MOUNT_OWNER=magic_mount_rs'
    echo 'ROUTING_CONFIG_DESTINATION=not-enforced'
}
