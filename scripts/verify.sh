#!/system/bin/sh
# Read-only diagnostics. Does not toggle NFC or start polling by itself.
MODDIR=${0%/*}
. "$MODDIR/lib/reader.sh" || exit 1
result=0

if pm list features | grep -q '^feature:android\.hardware\.nfc$'; then
    echo 'FEATURE=present'
else
    echo 'FEATURE=missing (reboot, mounting, or OEM feature exclusion requires checking)'
    result=1
fi

if [ ! -s "$MODDIR/config-paths" ]; then
    echo 'CONFIG_MANIFEST=missing'
    exit 1
fi
while IFS= read -r source; do
    relative=$(nru_module_relative "$source") || { result=1; continue; }
    if cmp -s "$source" "$MODDIR/$relative"; then
        echo "CONFIG_MOUNT=matches $source"
    else
        echo "CONFIG_MOUNT=mismatch $source"
        result=1
    fi
    mask=$(nru_read_mask "$source") || { result=1; continue; }
    number=$(nru_mask_number "$mask") || { result=1; continue; }
    echo "POLLING_TECH_MASK=$mask $source"
    [ "$((number & 15))" -eq 15 ] || result=1
done < "$MODDIR/config-paths"

echo '--- NXP configuration file mount ---'
sh "$MODDIR/nfcconf" status || result=1

echo '--- NFC service state (not a physical tag test) ---'
dumpsys nfc | grep -e '^mState=' -e '^mScreenState=' -e '^mIsReaderOptionEnabled='
echo 'Use a foreground NFC reader application and a known working tag to test actual reading.'
exit "$result"
