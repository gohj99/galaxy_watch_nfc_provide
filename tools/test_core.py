"""Run module core tests without a device."""
from pathlib import Path
import subprocess
from build_env import java_tool

ROOT = Path(__file__).resolve().parents[1]
out = ROOT / "build/core-tests"
out.mkdir(parents=True, exist_ok=True)
sources = sorted((ROOT / "core/src").rglob("*.java")) + sorted((ROOT / "tests/java").rglob("*.java"))
subprocess.run([str(java_tool("javac")), "-encoding", "UTF-8", "-d", str(out), *map(str, sources)], check=True)
subprocess.run([str(java_tool("java")), "-cp", str(out), "dev.nfctools.tests.CoreTest", str(ROOT / "tests/fixtures/watch7-core.conf")], check=True)
