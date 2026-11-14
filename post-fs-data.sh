#!/system/bin/sh
MODDIR=${0%/*}
# Bind the module copy after the root manager has mounted module files. This
# runs before normal late-start services; service.sh retries as a fallback.
sh "$MODDIR/nfcconf" mount > "$MODDIR/config-mount-early.log" 2>&1
