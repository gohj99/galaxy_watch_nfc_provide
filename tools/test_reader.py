"""Test reader configuration preparation and upgrade preservation."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SHELL = r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else (shutil.which("sh") or "/bin/sh")

HARNESS = r"""set -eu
base=$1
. "$2/lib/reader.sh"

cat > "$base/live.conf" <<'EOF'
# Keep this comment and unrelated settings.
POLLING_TECH_MASK = 0x01 # only the numeric token changes on first install
NFC_DEBUG=0
EOF
nru_prepare_module_copy "$base/live.conf" "$base/module/system/etc/libnfc-nci.conf"
grep -q '^POLLING_TECH_MASK = 0x0F # only the numeric token changes on first install$' "$base/module/system/etc/libnfc-nci.conf"
grep -q '^NFC_DEBUG=0$' "$base/module/system/etc/libnfc-nci.conf"

# A root edit to the active module copy must survive an upgrade verbatim,
# including a deliberately reduced polling mask and its inode.
sed -i 's/0x0F/0x02/' "$base/module/system/etc/libnfc-nci.conf"
printf '\nUSER_EDIT=keep\n' >> "$base/module/system/etc/libnfc-nci.conf"
before_inode=$(stat -c '%d:%i' "$base/module/system/etc/libnfc-nci.conf")
cp "$base/module/system/etc/libnfc-nci.conf" "$base/edited.conf"
nru_prepare_module_copy "$base/live.conf" "$base/module/system/etc/libnfc-nci.conf"
cmp -s "$base/edited.conf" "$base/module/system/etc/libnfc-nci.conf"
[ "$(stat -c '%d:%i' "$base/module/system/etc/libnfc-nci.conf")" = "$before_inode" ]

# A fresh update directory copies the previous module copy without applying
# the first-install mask edit again.
nru_copy_module_copy "$base/module/system/etc/libnfc-nci.conf" "$base/upgrade/system/etc/libnfc-nci.conf"
cmp -s "$base/edited.conf" "$base/upgrade/system/etc/libnfc-nci.conf"

# Symlinks are never accepted as module configuration sources.
case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *)
        ln -s "$base/live.conf" "$base/link.conf"
        if nru_prepare_module_copy "$base/live.conf" "$base/link.conf"; then
            echo 'Symlink accepted' >&2
            exit 1
        fi
        ;;
esac
"""


def main() -> None:
    with tempfile.TemporaryDirectory() as folder:
        base = Path(folder)
        result = subprocess.run(
            [SHELL, "-c", HARNESS, "test-reader", base.as_posix(), ROOT.as_posix()],
            capture_output=True,
            timeout=30,
        )
        if result.returncode:
            raise AssertionError((result.stdout + result.stderr).decode("utf-8", "replace"))
    print("Reader tests passed: first-install patching, upgrade preservation, inode stability and symlink rejection")


if __name__ == "__main__":
    main()
