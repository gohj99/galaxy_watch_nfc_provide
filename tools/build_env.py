"""Find Java and Android SDK tools on local machines and GitHub runners."""
from pathlib import Path
import os
import shutil


def java_home():
    configured = os.environ.get("JAVA_HOME")
    if configured:
        return Path(configured)
    compiler = shutil.which("javac")
    if compiler:
        return Path(compiler).resolve().parent.parent
    if os.name == "nt":
        return Path(r"C:\Program Files\Microsoft\jdk-17.0.11.9-hotspot")
    raise RuntimeError("JDK not found; install JDK 17 and set JAVA_HOME")


def java_tool(name):
    tool = java_home() / "bin" / (name + (".exe" if os.name == "nt" else ""))
    if not tool.is_file():
        raise RuntimeError(f"Java tool not found: {tool}; check JAVA_HOME")
    return tool


def android_sdk():
    configured = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    if configured:
        return Path(configured)
    if os.name == "nt":
        return Path(r"D:\Android\Sdk")
    raise RuntimeError("Set ANDROID_SDK_ROOT or ANDROID_HOME to the Android SDK directory")
