#!/usr/bin/env python3
"""Verify the fork identity and pinned release signer before packaging an APK."""

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from zipfile import BadZipFile, ZipFile, ZIP_DEFLATED


ROOT = Path(__file__).resolve().parents[2]
ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
sys.path.insert(0, str(ROOT / "scripts"))
from pubspec_version import parse_pubspec_version  # noqa: E402


def run(*arguments: str) -> str:
    return subprocess.check_output(arguments, cwd=ROOT, text=True)


def verify_apk(apk: Path, abi: str, tools: Path, version: str, build: str, expected: str) -> None:
    # apksigner exits nonzero for a missing APK or invalid signature.
    signature = run(str(tools / "apksigner"), "verify", "--verbose", "--print-certs", str(apk))
    actual = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})$", signature, re.MULTILINE)
    if [value.lower() for value in actual] != [expected]:
        raise ValueError("APK signer does not match android/release-signing-certificate.sha256.")
    if "CN=Android Debug" in signature:
        raise ValueError("An Android debug certificate cannot sign a release.")

    metadata = run(str(tools / "aapt"), "dump", "badging", str(apk))
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata, re.MULTILINE)
    if not package or package.groups() != ("com.vexilyze.tv", build, version.split("+")[0]):
        raise ValueError("APK package/version does not match the fork and pubspec.yaml.")
    if not re.search(r"^application-label:'Plezy'$", metadata, re.MULTILINE):
        raise ValueError("APK display name must be Plezy.")
    if "application-debuggable" in metadata:
        raise ValueError("A debuggable APK cannot be released.")
    architectures = re.search(r"^native-code: (.+)$", metadata, re.MULTILINE)
    if not architectures or set(re.findall(r"'([^']+)'", architectures.group(1))) != {abi}:
        raise ValueError(f"The {abi} release APK must contain exactly that architecture.")
    with ZipFile(apk) as archive:
        libraries = [item for item in archive.infolist() if item.filename.startswith("lib/") and item.filename.endswith(".so")]
        if not libraries or {item.filename.split("/")[1] for item in libraries} != {abi}:
            raise ValueError(f"The {abi} release APK contains missing or unexpected native libraries.")
        if any(item.compress_type != ZIP_DEFLATED for item in libraries):
            raise ValueError("Native libraries must be compressed in the downloadable APK.")


def main() -> int:
    version, build = parse_pubspec_version((ROOT / "pubspec.yaml").read_text())
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise ValueError("ANDROID_HOME or ANDROID_SDK_ROOT must point to the Android SDK.")
    tools = Path(sdk) / "build-tools/36.1.0"
    pin = ROOT / "android/release-signing-certificate.sha256"
    expected = pin.read_text().strip().lower()
    if not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise ValueError("Invalid release signing certificate fingerprint.")
    apks = [(abi, ROOT / f"build/app/outputs/flutter-apk/app-{abi}-release.apk") for abi in ABIS]
    # Verify the entire release before replacing any previous output. This also
    # catches Flutter's ABI versionCode offset if the Gradle override is lost.
    for abi, apk in apks:
        verify_apk(apk, abi, tools, version, build, expected)
    commit = run("git", "rev-parse", "HEAD").strip()
    notes = (ROOT / "docs/fork/RELEASE_NOTES.md").read_text()
    output = ROOT / "build/fork-release"
    with tempfile.TemporaryDirectory(prefix="fork-release-", dir=ROOT / "build") as temporary:
        staging = Path(temporary)
        checksums = []
        for abi, apk in apks:
            destination = staging / f"plezy-android-{abi}.apk"
            shutil.copy2(apk, destination)
            with destination.open("rb") as source:
                digest = hashlib.file_digest(source, "sha256").hexdigest()
            (staging / f"{destination.name}.sha256").write_text(f"{digest}  {destination.name}\n")
            checksums.append(f"- `{destination.name}` ({destination.stat().st_size / 1_000_000:.1f} MB): `{digest}`")
        shutil.copy2(pin, staging / pin.name)
        shutil.copy2(ROOT / "LICENSE", staging / "LICENSE")
        (staging / "SOURCE.txt").write_text(
            f"Plezy {version}\nSource commit: {commit}\n"
            f"https://github.com/Vexilyze/plezy/tree/{commit}\n"
            "Personal TV fork; independently maintained, not an official Plezy build.\n"
            "License: GPL-3.0 (see LICENSE). Native dependency revisions: mpv-build.lock.json.\n"
            "Build instructions: docs/fork/RELEASING.md\n"
        )
        (staging / "RELEASE_NOTES.md").write_text(
            notes + f"\n\nVersion: `{version}` · Source: `{commit}`\n"
            "\nAPK SHA-256 checksums:\n\n" + "\n".join(checksums)
            + f"\n\nSigning certificate SHA-256: `{expected}`\n"
        )
        if output.exists():
            shutil.rmtree(output)
        staging.replace(output)
    print(f"Verified signed APKs: {output}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, BadZipFile, subprocess.CalledProcessError) as error:
        print(f"Release packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
