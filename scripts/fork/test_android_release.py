"""Release guards must reject credentials/artifacts that cannot update this fork."""

import base64
import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import package_android
import prepare_android_signing


class AndroidReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="vexilyze-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "android/app").mkdir(parents=True)
        self.pin = "a" * 64
        (self.root / "android/release-signing-certificate.sha256").write_text(self.pin)
        (self.root / "pubspec.yaml").write_text("version: 2.26.1+161\n")
        (self.root / "LICENSE").write_text("test license")
        (self.root / "docs/fork").mkdir(parents=True)
        (self.root / "docs/fork/RELEASE_NOTES.md").write_text("test notes")
        apk = self.root / "build/app/outputs/flutter-apk/app-release.apk"
        apk.parent.mkdir(parents=True)
        apk.write_bytes(b"fixture APK bytes")
        self.metadata = (
            "package: name='com.vexilyze.tv' versionCode='161' versionName='2.26.1'\n"
            "application-label:'Vexilyze TV'\n"
            "native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'\n"
        )

    def package(self, *, signer=None, metadata=None):
        def run(*args):
            executable = Path(args[0]).name
            if executable == "apksigner":
                return f"Signer #1 certificate SHA-256 digest: {signer or self.pin}\n"
            if executable == "aapt":
                return metadata or self.metadata
            if executable == "git":
                return "b" * 40
            self.fail(f"Unexpected command: {args}")

        with (
            patch.object(package_android, "ROOT", self.root),
            patch.object(package_android, "run", side_effect=run),
            patch.dict(os.environ, {"ANDROID_HOME": str(self.root / "sdk")}),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            return package_android.main()

    def test_verified_apk_gets_exact_byte_checksum_and_source(self):
        self.assertEqual(self.package(), 0)
        output = self.root / "build/fork-release"
        self.assertEqual((output / "vexilyze-tv-android.apk").read_bytes(), b"fixture APK bytes")
        self.assertIn("  vexilyze-tv-android.apk\n", (output / "vexilyze-tv-android.apk.sha256").read_text())
        self.assertIn("b" * 40, (output / "SOURCE.txt").read_text())

    def test_changed_signing_key_cannot_produce_release_artifacts(self):
        with self.assertRaisesRegex(ValueError, "signer does not match"):
            self.package(signer="c" * 64)
        self.assertFalse((self.root / "build/fork-release").exists())

    def test_upstream_package_cannot_be_published_as_fork(self):
        with self.assertRaisesRegex(ValueError, "package/version"):
            self.package(metadata=self.metadata.replace("com.vexilyze.tv", "com.edde746.plezy"))

    def test_wrong_version_code_cannot_be_published(self):
        with self.assertRaisesRegex(ValueError, "package/version"):
            self.package(metadata=self.metadata.replace("versionCode='161'", "versionCode='160'"))

    def test_debuggable_apk_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "debuggable"):
            self.package(metadata=self.metadata + "application-debuggable\n")

    def test_arm64_only_apk_cannot_be_mislabeled_universal(self):
        with self.assertRaisesRegex(ValueError, "include arm64"):
            self.package(metadata=self.metadata.replace(" 'armeabi-v7a' 'x86_64'", ""))

    def prepare(self, credentials):
        previous_umask = os.umask(0o077)
        try:
            with (
                patch.object(prepare_android_signing, "__file__", str(self.root / "scripts/fork/prepare_android_signing.py")),
                patch.dict(os.environ, credentials, clear=True),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                return prepare_android_signing.main()
        finally:
            os.umask(previous_umask)

    def credentials(self):
        return {
            "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"test keystore").decode(),
            "ANDROID_STORE_PASSWORD": "password with spaces\\and:newlines\n",
            "ANDROID_KEY_PASSWORD": "pássword",
            "ANDROID_KEY_ALIAS": "release",
        }

    def test_missing_or_invalid_credentials_write_no_files(self):
        self.assertEqual(self.prepare({}), 1)
        self.assertEqual(self.prepare({**self.credentials(), "ANDROID_KEYSTORE_BASE64": "invalid!"}), 1)
        self.assertFalse((self.root / "android/key.properties").exists())
        self.assertFalse((self.root / "android/app/vexilyze-release.jks").exists())

    def test_credentials_are_private_escaped_and_never_overwrite_existing_key(self):
        self.assertEqual(self.prepare(self.credentials()), 0)
        properties = self.root / "android/key.properties"
        self.assertEqual(properties.stat().st_mode & 0o777, 0o600)
        content = properties.read_text()
        self.assertIn("storePassword=password\\u0020with\\u0020spaces\\u005cand\\u003anewlines\\u000a\n", content)
        self.assertIn("keyPassword=p\\u00e1ssword\n", content)
        self.assertEqual(self.prepare(self.credentials()), 1)
        self.assertEqual(properties.read_text(), content)


if __name__ == "__main__":
    unittest.main()
