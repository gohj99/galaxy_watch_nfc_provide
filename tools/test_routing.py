"""Test routing backups, opaque copies and root edits without a device or mounts."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SHELL = r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else (shutil.which("sh") or "/bin/sh")
SOURCE = b"""<?xml version='1.0' encoding='utf-8'?>
<configurations>
  <rules>
    <!-- OEM formatting and routes must survive byte-for-byte. -->
    <rule id="1" listen_tech="0x07" route_aid="eSE"
      route_iso_dep='eSE' route_tech="eSE" route_system_code="eSE" />
  </rules>
  <regions><region country_iso_code="00" rule_id="1" /></regions>
</configurations>"""

HARNESS = r"""set -eu
base=$1
MODDIR=$base/module
. "$2/lib/config.sh"
gwn_state=$base/state
mkdir -p "$gwn_state"
. "$2/lib/routing.sh"
gwr_target=$base/firmware.xml
gwr_store=$gwn_state/routing
gwr_source=$MODDIR/system/etc/nfc_rule_configs.xml
getprop() { printf '%s\n' "${test_firmware:-test-firmware}"; }
ls() {
    if [ "${1:-}" = -Zd ]; then printf 'u:object_r:system_file:s0 %s\n' "$2";
    else command ls "$@"; fi
}
chown() { :; }
chcon() { :; }
awk() {
    for test_arg do :; done
    if [ "$test_arg" = /proc/1/mountinfo ]; then
        if [ "${test_overlay:-0}" = 1 ]; then
            printf '/data/adb/modules/another/system/etc/nfc_rule_configs.xml\n'
        fi
    else command awk "$@"; fi
}
gwr_prepare
cmp -s "$gwr_target" "$gwr_source"
cmp -s "$gwr_target" "$gwr_store/original.xml"
cp "$gwr_store/original.xml" "$base/original.expected"
# A root app edits only the module source. Prepare must keep its bytes/inode.
printf '\n<!-- application edit; host routing chosen explicitly -->\n' >> "$gwr_source"
cp "$gwr_source" "$base/edited.expected"
before_inode=$(gwn_identity "$gwr_source")
gwr_prepare
cmp -s "$gwr_source" "$base/edited.expected"
[ "$(gwn_identity "$gwr_source")" = "$before_inode" ]
cmp -s "$gwr_store/original.xml" "$base/original.expected"
# An upgrade sees the active edited policy and copies it into the new module.
cat "$gwr_source" > "$gwr_target"
MODDIR=$base/upgrade
gwr_source=$MODDIR/system/etc/nfc_rule_configs.xml
gwr_prepare
cmp -s "$gwr_source" "$base/edited.expected"
cmp -s "$gwr_store/original.xml" "$base/original.expected"
# A default eSE route is valid. Failure here must only be the missing mount.
if gwr_status > "$base/status.txt" 2> "$base/status.err"; then
    echo 'Unmounted source accepted' >&2; exit 1
fi
grep -q 'Magic Mount-rs has not activated' "$base/status.err"
# Format checks refuse unreadable/empty/non-XML/oversized input.
: > "$base/empty.xml"
printf '<wrong-root />' > "$base/wrong.xml"
for invalid in "$base/missing.xml" "$base/empty.xml" "$base/wrong.xml" "$base/large.xml"; do
    if gwr_check_input "$invalid"; then echo "Accepted invalid input: $invalid" >&2; exit 1; fi
done
# A symlink cannot become the writable module copy.
# Git Bash emulates ln -s by copying on Windows; exercise real links on Unix.
case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *)
        for destination in "$gwr_target" "$base/must-not-be-created.xml"; do
            MODDIR=$base/symlink-$(basename "$destination")
            gwr_source=$MODDIR/system/etc/nfc_rule_configs.xml
            mkdir -p "${gwr_source%/*}"
            ln -s "$destination" "$gwr_source"
            if gwr_prepare; then echo 'Symlink accepted' >&2; exit 1; fi
        done
        [ ! -e "$base/must-not-be-created.xml" ]
        ;;
esac
# Firmware/hash changes fail before overwriting the application edit.
MODDIR=$base/upgrade
gwr_source=$MODDIR/system/etc/nfc_rule_configs.xml
test_firmware=changed
if gwr_prepare; then echo 'Firmware mismatch accepted' >&2; exit 1; fi
test_firmware=test-firmware
printf 'tampered' >> "$gwr_store/original.xml"
if gwr_prepare; then echo 'Original hash mismatch accepted' >&2; exit 1; fi
cmp -s "$gwr_source" "$base/edited.expected"
# Never label an existing module overlay as the original without a backup.
gwr_store=$base/unbacked
test_overlay=1
if gwr_prepare; then echo 'Unbacked existing overlay accepted' >&2; exit 1; fi
[ ! -e "$gwr_store" ]
# Non-Samsung systems without this file remain supported.
gwr_target=$base/absent.xml
gwr_prepare
gwr_status
"""


def main():
    ET.fromstring(SOURCE)
    for suffix in (b"", b"\n"):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            original = SOURCE + suffix
            (base / "firmware.xml").write_bytes(original)
            (base / "large.xml").write_bytes(b"x" * 131073)
            result = subprocess.run(
                [SHELL, "-c", HARNESS, "test-routing", base.as_posix(), ROOT.as_posix()],
                capture_output=True, timeout=30,
            )
            if result.returncode:
                raise AssertionError((result.stdout + result.stderr).decode("utf-8", "replace"))
            assert (base / "original.expected").read_bytes() == original
            assert (base / "upgrade/system/etc/nfc_rule_configs.xml").read_bytes() == (base / "edited.expected").read_bytes()
    print("Routing storage tests passed: original bytes, editable copies, upgrades, inode preservation, guards and no-policy devices")


if __name__ == "__main__":
    main()
