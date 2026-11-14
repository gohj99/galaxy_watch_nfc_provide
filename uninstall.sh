#!/system/bin/sh
MODDIR=${0%/*}
# Cancel future helper writes; do not send any NFC controller command.
rm -f /data/adb/galaxy_watch_nfc_provide/desired-uid
sh "$MODDIR/nfcconf" unmount
# The manager removes module files. The untouched firmware file is revealed.
# Keep private original/last-good backups for recovery; never copy onto vendor.
