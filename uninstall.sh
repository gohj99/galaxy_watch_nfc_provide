#!/system/bin/sh
MODDIR=${0%/*}
# Cancel future helper writes; do not send any NFC controller command.
rm -f /data/adb/galaxy_watch_nfc_provide/desired-uid
# Magic Mount-rs removes the module mount as part of module removal. The
# untouched firmware file is then revealed; no shell mount operation is used.
