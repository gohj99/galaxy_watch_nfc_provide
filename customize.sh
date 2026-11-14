#!/system/bin/sh
SKIPUNZIP=0

[ -n "${MODPATH:-}" ] && [ -d "$MODPATH" ] || abort "Missing module installation directory"
[ -r "$MODPATH/lib/reader.sh" ] || abort "Missing reader helpers"
[ -r "$MODPATH/lib/config.sh" ] && [ -r "$MODPATH/nfcconf" ] || abort "Missing configuration helpers"
[ -r "$MODPATH/lib/routing.sh" ] || abort "Missing routing configuration helpers"
[ -r "$MODPATH/nfc-uid-tools.jar" ] || abort "Missing UID helper"
. "$MODPATH/lib/reader.sh"

ui_print "- Galaxy Watch NFC Provide 1.0.6"
ui_print "- Module id is fixed: galaxy_watch_nfc_provide"
ui_print "- No device, Android API, or firmware whitelist"
ui_print "- Reader overlay uses this device's own NFC stack configuration"

if [ "${KSU:-false}" = true ]; then
    if [ -r /data/adb/modules/magic_mount_rs/module.prop ]; then
        [ -x /data/adb/modules/magic_mount_rs/meta-mm ] || abort "Magic Mount-rs executable is unavailable"
        [ ! -e /data/adb/modules/magic_mount_rs/disable ] || abort "Enable Magic Mount-rs before installing"
        ui_print "- Magic Mount-rs detected"
    else
        ui_print "! KernelSU requires a working system-mounting metamodule"
    fi
fi

nru_count=0
mkdir -p "$MODPATH/backup" || abort "Cannot create configuration backup directory"
: > "$MODPATH/config-paths" || abort "Cannot create configuration manifest"
printf '%s\n' 'Galaxy Watch NFC Provider installation' > "$MODPATH/install-summary.txt" || abort "Cannot write installation summary"

for nru_live in $(nru_config_paths); do
    [ -f "$nru_live" ] && [ -r "$nru_live" ] || continue
    if nru_raw=$(nru_read_mask "$nru_live"); then
        :
    else
        nru_status=$?
        if [ "$nru_status" -eq 10 ]; then
            ui_print "- Skipping $nru_live (no explicit polling mask)"
            continue
        fi
        abort "Ambiguous or unsupported POLLING_TECH_MASK in $nru_live"
    fi
    nru_numeric=$(nru_mask_number "$nru_raw") || abort "Unsupported numeric polling mask in $nru_live"
    nru_relative=$(nru_module_relative "$nru_live") || abort "Unsupported configuration path"
    nru_backup="$MODPATH/backup$nru_live"
    mkdir -p "${nru_backup%/*}" || abort "Cannot create backup path"
    cp "$nru_live" "$nru_backup" || abort "Cannot back up $nru_live"
    nru_patch_config "$nru_live" "$MODPATH/$nru_relative" || abort "Cannot safely prepare $nru_live"
    nru_changed=$(nru_read_mask "$MODPATH/$nru_relative") || abort "Prepared configuration failed verification"
    printf '%s\n' "$nru_live" >> "$MODPATH/config-paths" || abort "Cannot update configuration manifest"
    printf '%s: %s -> %s\n' "$nru_live" "$nru_raw" "$nru_changed" >> "$MODPATH/install-summary.txt" || abort "Cannot update installation summary"
    (cd "$MODPATH" && sha256sum "backup$nru_live" "$nru_relative") >> "$MODPATH/install-summary.txt" || abort "Cannot hash configuration files"
    ui_print "- $nru_live: $nru_raw -> $nru_changed"
    nru_count=$((nru_count + 1))
done

[ "$nru_count" -gt 0 ] || abort "No supported libnfc-nci.conf with an explicit polling mask was found"
[ -r "$MODPATH/system/etc/permissions/nfc-reader-unlock.xml" ] || abort "Missing NFC feature declaration"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/verify.sh" 0 0 0755
set_perm "$MODPATH/uidctl" 0 0 0755
set_perm "$MODPATH/nfcconf" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/post-mount.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
find "$MODPATH/backup" -type d -exec chmod 0700 {} \;
find "$MODPATH/backup" -type f -exec chmod 0600 {} \;

# Save an immutable-by-convention original before preparing an editable copy.
# NXP settings and Samsung routing XML are copied unchanged. Applications with
# root permission choose UID/routing values explicitly after installation.
sh "$MODPATH/nfcconf" prepare >> "$MODPATH/install-summary.txt" || abort "Cannot safely prepare writable NXP configuration"
ui_print "- Editable NXP and Samsung routing copies prepared without changing their values"

# Capability discovery and CORE_GET_CONFIG only; installation never sends CORE_SET_CONFIG.
sh "$MODPATH/uidctl" probe > "$MODPATH/install-probe.json" || abort "Incompatible NFC Binder interface"
if [ -f /data/adb/galaxy_watch_nfc_provide/factory.json ]; then
    ui_print "- Preserved existing factory NFCID1 baseline (including its hash guard)"
else
    sh "$MODPATH/uidctl" capture-default > "$MODPATH/install-default.json" || abort "Cannot safely capture this firmware's factory NFCID1"
    ui_print "- Saved device-derived factory NFCID1 using GET only"
fi
ui_print "- UID persistence remains disabled until you explicitly run uidctl persist"
ui_print "- Routing values are preserved; root-authorized apps can change them when needed"
ui_print "- Reboot to activate the module overlays; run verify.sh after reboot"
