"""Check Samsung policy transformation without mounting or changing a device."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SHELL = r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else (shutil.which("sh") or "/bin/sh")
KEYS = ("route_aid", "route_iso_dep", "route_tech", "route_system_code")
SOURCE = """<?xml version='1.0' encoding='utf-8'?>
<configurations>
  <version><major>1</major><minor>0</minor></version>
  <rules>
    <!-- Keep regions and the OEM listening restrictions. -->
    <rule id="1" listen_tech="0x07" route_aid="eSE" route_iso_dep="eSE" route_tech="eSE" route_system_code="eSE" description="default" />
    <rule id="2" listen_tech="0x05" route_aid="DH" route_iso_dep="DH" route_tech="eSE" route_system_code="eSE" description="restricted" />
  </rules>
  <regions><region area="1" country_iso_code="00" rule_id="1" /></regions>
</configurations>"""


def patch(source, check=False):
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        src, dst = folder / "in.xml", folder / "out.xml"
        src.write_bytes(source)
        script = 'gwn_state="$1"; MODDIR="$1"; . "$2"; gwr_patch "$3" "$4" "$5"'
        result = subprocess.run(
            [SHELL, "-c", script, "test-routing", folder.as_posix(),
             (ROOT / "lib/routing.sh").as_posix(), src.as_posix(), dst.as_posix(), str(int(check))],
            capture_output=True, timeout=15,
        )
        return result.returncode, dst.read_bytes() if dst.exists() else b"", result.stderr


def main():
    for suffix in (b"", b"\n"):
        original = SOURCE.encode() + suffix
        code, output, error = patch(original)
        assert code == 0, error
        before, after = ET.fromstring(original), ET.fromstring(output)
        for rule in before.findall("./rules/rule"):
            rule.attrib.update({key: "DH" for key in KEYS})
        assert ET.tostring(before) == ET.tostring(after), "Changed unrelated XML structure"
        expected = original.replace(b'="eSE"', b'="DH"')
        assert output == expected, "Changed unrelated bytes or final newline"
        assert patch(output)[:2] == (0, output), "Transformation must be idempotent"
        assert patch(output, check=True)[0] == 0
        assert patch(original, check=True)[0] != 0, "Status must reject an eSE route"
    bad_inputs = [
        SOURCE.replace(' route_tech="eSE"', "", 1),
        SOURCE.replace('route_aid="eSE"', 'route_aid="eSE" route_aid="DH"', 1),
        SOURCE.replace('listen_tech="0x07" ', 'listen_tech="0x07"\n      ', 1),
        SOURCE.replace('route_aid="eSE"', "route_aid='eSE'", 1),
        SOURCE.replace("</configurations>", ""),
        SOURCE.replace("<rules>", "<!-- <rules> -->"),
        '<configurations>\n<rules>\n<!-- <rule route_aid="DH" /> -->\n</rules>\n</configurations>',
        '<!DOCTYPE configurations [<!ENTITY x "value">]>\n' + SOURCE,
    ]
    for text in bad_inputs:
        assert patch(text.encode())[0] != 0, "Unsupported policy must be rejected"
    print("Routing tests passed: byte preservation, XML semantics, idempotence and 8 rejection cases")


if __name__ == "__main__":
    main()
