"""Build the open-source Galaxy Watch NFC Provider module."""
from pathlib import Path
import hashlib
import json
import os
import stat
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
JDK = Path(r"C:\Program Files\Microsoft\jdk-17.0.11.9-hotspot")
SDK = Path(r"D:\Android\Sdk")
ANDROID = SDK / "platforms/android-36/android.jar"
BT = SDK / "build-tools/36.0.0"


def run(args, **kwargs):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=180, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout + result.stderr


def main():
    build = ROOT / "build"
    out = ROOT / "dist"
    classes = build / "uid-classes"
    dex = build / "uid-dex"
    build.mkdir(exist_ok=True)
    out.mkdir(exist_ok=True)
    classes.mkdir(parents=True, exist_ok=True)
    dex.mkdir(parents=True, exist_ok=True)
    for old in classes.rglob("*.class"):
        old.unlink()
    for old in dex.glob("*.dex"):
        old.unlink()
    sources = sorted((ROOT / "core/src").rglob("*.java")) + sorted((ROOT / "uid/src").rglob("*.java"))
    boot = str(ANDROID) + os.pathsep + str(BT / "core-lambda-stubs.jar")
    run([JDK / "bin/javac.exe", "-encoding", "UTF-8", "-source", "8", "-target", "8",
         "-bootclasspath", boot, "-d", classes, *sources])
    classes_jar = build / "classes.jar"
    with zipfile.ZipFile(classes_jar, "w", zipfile.ZIP_DEFLATED) as archive:
        for source in sorted(classes.rglob("*.class")):
            info = zipfile.ZipInfo(source.relative_to(classes).as_posix(), date_time=(2026, 11, 14, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, source.read_bytes())
    run([BT / "d8.bat", "--min-api", "26", "--lib", ANDROID, "--output", dex, classes_jar],
        env={**os.environ, "JAVA_HOME": str(JDK), "PATH": str(JDK / "bin") + os.pathsep + os.environ.get("PATH", "")})
    helper = out / "nfc-uid-tools.jar"
    with zipfile.ZipFile(helper, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("classes.dex", (dex / "classes.dex").read_bytes())

    files = {
        "module.prop": ROOT / "module.prop",
        "customize.sh": ROOT / "customize.sh",
        "service.sh": ROOT / "service.sh",
        "uidctl": ROOT / "uidctl",
        "nfc-uid-tools.jar": helper,
        "lib/reader.sh": ROOT / "lib/reader.sh",
        "system/etc/permissions/nfc-reader-unlock.xml": ROOT / "system/etc/permissions/nfc-reader-unlock.xml",
        "verify.sh": ROOT / "verify.sh",
        "README.md": ROOT / "README.md",
    }
    package = out / "galaxy_watch_nfc_provide-v1.0.0.zip"
    with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, source in files.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 14, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | (0o755 if name.endswith(".sh") or name == "uidctl" else 0o644)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, source.read_bytes())
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None
    report = {
        "module_id": "galaxy_watch_nfc_provide",
        "artifact": package.name,
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "bytes": package.stat().st_size,
        "payload_sha256": {name: hashlib.sha256(source.read_bytes()).hexdigest() for name, source in files.items()},
        "includes_test_apk": False,
    }
    (out / "build-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
