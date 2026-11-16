#!/usr/bin/env python3
"""Materialize CI signing secrets without shell interpolation or logging values."""

import base64
import binascii
import os
from pathlib import Path
import sys


def properties_value(value: str) -> str:
    # java.util.Properties reads ISO-8859-1; escape everything outside ASCII.
    encoded = value.encode("utf-16-be")
    result = []
    for offset in range(0, len(encoded), 2):
        code = int.from_bytes(encoded[offset : offset + 2], "big")
        character = chr(code)
        if character in "\\ :=#!" or not 33 <= code <= 126:
            result.append(f"\\u{code:04x}")
        else:
            result.append(character)
    return "".join(result)


def main() -> int:
    names = (
        "ANDROID_KEYSTORE_BASE64",
        "ANDROID_STORE_PASSWORD",
        "ANDROID_KEY_PASSWORD",
        "ANDROID_KEY_ALIAS",
    )
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        print(f"Missing release signing secrets: {', '.join(missing)}", file=sys.stderr)
        return 1
    if os.environ["ANDROID_KEY_ALIAS"].lower() == "androiddebugkey":
        print("The Android debug key cannot sign a release.", file=sys.stderr)
        return 1
    try:
        keystore = base64.b64decode("".join(os.environ[names[0]].split()), validate=True)
    except (ValueError, binascii.Error):
        print("ANDROID_KEYSTORE_BASE64 is not valid base64.", file=sys.stderr)
        return 1
    if not keystore:
        print("The release keystore is empty.", file=sys.stderr)
        return 1

    root = Path(__file__).resolve().parents[2]
    android = root / "android"
    os.umask(0o077)
    key = android / "app/vexilyze-release.jks"
    properties = android / "key.properties"
    # Refuse to replace a developer's existing key/configuration by accident.
    if key.exists() or properties.exists():
        print("Signing files already exist; keep them or remove them explicitly before preparing CI signing.", file=sys.stderr)
        return 1
    key.write_bytes(keystore)
    try:
        values = {
            "storeFile": "vexilyze-release.jks",
            "storePassword": os.environ["ANDROID_STORE_PASSWORD"],
            "keyPassword": os.environ["ANDROID_KEY_PASSWORD"],
            "keyAlias": os.environ["ANDROID_KEY_ALIAS"],
        }
        properties.write_text(
            "".join(f"{name}={properties_value(value)}\n" for name, value in values.items()),
            encoding="ascii",
        )
    except OSError:
        key.unlink(missing_ok=True)
        raise
    print("Release signing configured.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
