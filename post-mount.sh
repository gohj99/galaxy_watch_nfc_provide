#!/system/bin/sh
MODDIR=${0%/*}
sh "$MODDIR/nfcconf" mount > "$MODDIR/config-mount.log" 2>&1
