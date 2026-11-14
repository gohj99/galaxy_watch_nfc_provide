#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/adb/galaxy_watch_nfc_provide
[ -f "$STATE/desired-uid" ] || exit 0
count=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$count" -lt 120 ]; do
    sleep 2
    count=$((count + 1))
done
[ "$(getprop sys.boot_completed)" = 1 ] || exit 1
[ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
sh "$MODDIR/uidctl" watch >> "$STATE/watch-launch.log" 2>&1 < /dev/null &
