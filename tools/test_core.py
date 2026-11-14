"""Run module core tests without a device."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
JDK = Path(r"C:\Program Files\Microsoft\jdk-17.0.11.9-hotspot\bin")
out = ROOT / "build/core-tests"
out.mkdir(parents=True, exist_ok=True)
sources = sorted((ROOT / "core/src").rglob("*.java")) + sorted((ROOT / "tests-java").rglob("*.java"))
subprocess.run([str(JDK / "javac.exe"), "-encoding", "UTF-8", "-d", str(out), *map(str, sources)], check=True)
subprocess.run([str(JDK / "java.exe"), "-cp", str(out), "dev.nfctools.tests.CoreTest", str(ROOT / "watch7-core.conf")], check=True)
