#!/system/bin/sh
MODDIR=${0%/*}
# Verify manager-owned mounts. Magic Mount-rs performs the actual mounting;
# later hooks retry if its mounts are not visible at this early stage.
sh "$MODDIR/nfcconf" mount > "$MODDIR/config-mount-early.log" 2>&1
