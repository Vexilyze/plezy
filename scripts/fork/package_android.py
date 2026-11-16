#!/usr/bin/env python3
"""Verify the fork identity and pinned release signer before packaging an APK."""

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from pubspec_version import parse_pubspec_version  # noqa: E402


def run(*arguments: str) -> str:
    return subprocess.check_output(arguments, cwd=ROOT, text=True)


def main() -> int:
    version, build = parse_pubspec_version((ROOT / "pubspec.yaml").read_text())
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise ValueError("ANDROID_HOME or ANDROID_SDK_ROOT must point to the Android SDK.")
    tools = Path(sdk) / "build-tools/36.1.0"
    apk = ROOT / "build/app/outputs/flutter-apk/app-release.apk"
    # apksigner exits nonzero for an invalid signature; stderr remains visible.
    signature = run(str(tools / "apksigner"), "verify", "--verbose", "--print-certs", str(apk))
    actual = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})$", signature, re.MULTILINE)
    pin = ROOT / "android/release-signing-certificate.sha256"
    expected = pin.read_text().strip().lower()
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or [value.lower() for value in actual] != [expected]:
        raise ValueError("APK signer does not match android/release-signing-certificate.sha256.")
    if "CN=Android Debug" in signature:
        raise ValueError("An Android debug certificate cannot sign a release.")

    metadata = run(str(tools / "aapt"), "dump", "badging", str(apk))
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata, re.MULTILINE)
    if not package or package.groups() != ("com.vexilyze.tv", build, version.split("+")[0]):
        raise ValueError("APK package/version does not match the fork and pubspec.yaml.")
    if not re.search(r"^application-label:'Vexilyze TV'$", metadata, re.MULTILINE):
        raise ValueError("APK display name must be Vexilyze TV.")
    if "application-debuggable" in metadata:
        raise ValueError("A debuggable APK cannot be released.")
    architectures = re.search(r"^native-code: (.+)$", metadata, re.MULTILINE)
    if not architectures or not {"arm64-v8a", "armeabi-v7a", "x86_64"}.issubset(set(re.findall(r"'([^']+)'", architectures.group(1)))):
        raise ValueError("The release APK must include arm64-v8a, armeabi-v7a and x86_64.")

    output = ROOT / "build/fork-release"
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "vexilyze-tv-android.apk"
    shutil.copy2(apk, destination)
    with destination.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    (output / f"{destination.name}.sha256").write_text(f"{digest}  {destination.name}\n")
    shutil.copy2(pin, output / pin.name)
    shutil.copy2(ROOT / "LICENSE", output / "LICENSE")
    commit = run("git", "rev-parse", "HEAD").strip()
    (output / "SOURCE.txt").write_text(
        f"Vexilyze TV {version}\nSource commit: {commit}\n"
        f"https://github.com/Vexilyze/plezy/tree/{commit}\n"
        "Based on Plezy; independently maintained, not an official Plezy build.\n"
        "License: GPL-3.0 (see LICENSE). Native dependency revisions: mpv-build.lock.json.\n"
        "Build instructions: docs/fork/RELEASING.md\n"
    )
    notes = (ROOT / "docs/fork/RELEASE_NOTES.md").read_text()
    (output / "RELEASE_NOTES.md").write_text(
        notes + f"\n\nVersion: `{version}` · Source: `{commit}`\n"
        f"\nAPK SHA-256: `{digest}`\nSigning certificate SHA-256: `{expected}`\n"
    )
    print(f"Verified signed release: {destination}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Release packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
