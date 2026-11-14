#!/system/bin/sh
# Device-derived Samsung routing overlay; Magic Mount-rs owns every mount.
gwr_target=/system/etc/nfc_rule_configs.xml
gwr_store=$gwn_state/routing
gwr_source=$MODDIR/system/etc/nfc_rule_configs.xml

# Supported OEM format: one self-closing rule per line, double-quoted routes.
# Refuse unfamiliar layouts rather than install a partially edited policy.
gwr_patch() {
    gwr_last=$(tail -c 1 "$1") || return 1
    gwr_newline=0
    [ -n "$gwr_last" ] || gwr_newline=1
    awk -v final_newline="$gwr_newline" -v check_only="${3:-0}" '
        BEGIN {
            keys[1]="route_aid"; keys[2]="route_iso_dep"
            keys[3]="route_tech"; keys[4]="route_system_code"
        }
        {
            scan=""; rest=$0
            while (length(rest)) {
                if (comment) {
                    p=index(rest,"-->")
                    if (!p) { rest=""; break }
                    rest=substr(rest,p+3); comment=0
                } else {
                    p=index(rest,"<!--")
                    if (!p) { scan=scan rest; rest="" }
                    else { scan=scan substr(rest,1,p-1); rest=substr(rest,p+4); comment=1 }
                }
            }
            if (scan ~ /<!DOCTYPE|<!ENTITY/) bad=1
            if (scan ~ /^[[:space:]]*<configurations>[[:space:]]*$/) opened++
            if (scan ~ /^[[:space:]]*<\/configurations>[[:space:]]*$/) closed++
            if (scan ~ /^[[:space:]]*<rules>[[:space:]]*$/) in_rules=1
            if (scan ~ /<rule([[:space:]]|>)/) {
                rules++
                if (!in_rules || $0 !~ /^[[:space:]]*<rule[[:space:]][^<>]*\/>[[:space:]]*$/) bad=1
                for (k=1;k<=4;k++) {
                    pattern="[[:space:]]" keys[k] "[[:space:]]*=[[:space:]]*\"[^\"]*\""
                    copy=$0
                    if (gsub(pattern,"",copy)!=1) { bad=1; continue }
                    match($0,pattern)
                    start=RSTART; size=RLENGTH; token=substr($0,start,size)
                    value=token; sub(/^[^=]*=[[:space:]]*"/,"",value); sub(/"$/,"",value)
                    if (check_only && value!="DH") bad=1
                    sub(/"[^"]*"$/,"\"DH\"",token)
                    $0=substr($0,1,start-1) token substr($0,start+size)
                }
            }
            if (scan ~ /^[[:space:]]*<\/rules>[[:space:]]*$/) in_rules=0
            if (NR>1) printf "%s\n", previous
            previous=$0
        }
        END {
            if (NR) printf "%s", previous
            if (NR && final_newline) printf "\n"
            if (bad || comment || !rules || opened!=1 || closed!=1 || in_rules) exit 1
        }
    ' "$1" > "$2"
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
        echo 'HOST_ROUTING=not-applicable (no Samsung routing policy)'
        return 0
    fi
    [ "$(stat -c %s "$gwr_target")" -le 131072 ] || {
        gwn_error 'Samsung routing policy is unexpectedly large'; return 1;
    }
    gwr_patch "$gwr_target" /dev/null || {
        gwn_error 'Unsupported Samsung routing XML; no routing overlay prepared'; return 1;
    }
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
    mkdir -p "${gwr_source%/*}" || return 1
    gwr_prepared=$gwr_source.new.$$
    gwr_patch "$gwr_target" "$gwr_prepared" || return 1
    gwr_patch "$gwr_prepared" /dev/null 1 || return 1
    [ ! -L "$gwr_source" ] || { gwn_error 'Routing module copy must not be a symlink'; return 1; }
    cat "$gwr_prepared" > "$gwr_source" || return 1
    rm -f "$gwr_prepared"
    chown 0:0 "$gwr_source" && chmod 0644 "$gwr_source" && chcon "$gwr_context" "$gwr_source" || return 1
    echo "HOST_ROUTING_PREPARED=$gwr_target"
    echo 'HOST_ROUTING_DESTINATION=DH (aid, iso_dep, tech, system_code; all existing rules)'
    echo "HOST_ROUTING_ORIGINAL=$gwr_store/original.xml"
}

gwr_status() {
    if [ ! -f "$gwr_target" ]; then
        echo 'HOST_ROUTING=not-applicable (no Samsung routing policy)'
        return 0
    fi
    gwr_load || return 1
    echo "HOST_ROUTING_TARGET=$gwr_target"
    echo "HOST_ROUTING_MODULE_COPY=$gwr_source"
    echo "HOST_ROUTING_ORIGINAL=$gwr_store/original.xml"
    gwr_patch "$gwr_target" /dev/null 1 || { gwn_error 'Visible Samsung routes are not all DH'; return 1; }
    [ "$(gwn_identity "$gwr_target")" = "$(gwn_identity "$gwr_source")" ] || {
        gwn_error 'Magic Mount-rs has not activated the Samsung routing overlay; reboot required'; return 1;
    }
    echo 'HOST_ROUTING_FILE=DH; manager mount matches'
    echo 'HOST_ROUTING_AIR_UID=not-verified (requires an external reader)'
}
