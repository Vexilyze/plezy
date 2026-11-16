"""Release guards must reject credentials/artifacts that cannot update this fork."""

import base64
import contextlib
import hashlib
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile, ZIP_DEFLATED, ZIP_STORED

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
        (self.root / "pubspec.yaml").write_text("version: 2.26.1+162\n")
        (self.root / "LICENSE").write_text("test license")
        (self.root / "docs/fork").mkdir(parents=True)
        (self.root / "docs/fork/RELEASE_NOTES.md").write_text("test notes")
        self.apks = {}
        for abi in package_android.ABIS:
            apk = self.root / f"build/app/outputs/flutter-apk/app-{abi}-release.apk"
            apk.parent.mkdir(parents=True, exist_ok=True)
            with ZipFile(apk, "w", compression=ZIP_DEFLATED) as archive:
                archive.writestr(f"lib/{abi}/libapp.so", b"fixture APK bytes" * 32)
            self.apks[abi] = apk
        self.metadata = (
            "package: name='com.vexilyze.tv' versionCode='162' versionName='2.26.1'\n"
            "application-label:'Plezy'\n"
            "native-code: '{abi}'\n"
        )

    def package(self, *, signer=None, metadata=None, metadata_by_abi=None):
        def run(*args):
            executable = Path(args[0]).name
            if executable == "apksigner":
                return f"Signer #1 certificate SHA-256 digest: {signer or self.pin}\n"
            if executable == "aapt":
                abi = next(abi for abi, apk in self.apks.items() if str(apk) == args[-1])
                return (metadata_by_abi or {}).get(abi, metadata or self.metadata).format(abi=abi)
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

    def test_all_three_verified_apks_get_exact_byte_checksums_and_source(self):
        self.assertEqual(self.package(), 0)
        output = self.root / "build/fork-release"
        self.assertEqual(len(list(output.glob("*.apk"))), 3)
        for abi, source in self.apks.items():
            name = f"plezy-android-{abi}.apk"
            self.assertEqual((output / name).read_bytes(), source.read_bytes())
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertEqual((output / f"{name}.sha256").read_text(), f"{digest}  {name}\n")
        self.assertIn("b" * 40, (output / "SOURCE.txt").read_text())

    def test_successful_packaging_removes_the_stale_universal_apk(self):
        output = self.root / "build/fork-release"
        output.mkdir()
        (output / "vexilyze-tv-android.apk").write_bytes(b"old universal")
        self.assertEqual(self.package(), 0)
        self.assertFalse((output / "vexilyze-tv-android.apk").exists())

    def test_changed_signing_key_cannot_produce_release_artifacts(self):
        with self.assertRaisesRegex(ValueError, "signer does not match"):
            self.package(signer="c" * 64)
        self.assertFalse((self.root / "build/fork-release").exists())

    def test_upstream_package_cannot_be_published_as_fork(self):
        with self.assertRaisesRegex(ValueError, "package/version"):
            self.package(metadata=self.metadata.replace("com.vexilyze.tv", "com.edde746.plezy"))

    def test_wrong_display_name_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "display name must be Plezy"):
            self.package(metadata=self.metadata.replace("application-label:'Plezy'", "application-label:'Vexilyze TV'"))

    def test_missing_architecture_cannot_produce_an_incomplete_release(self):
        self.apks["x86_64"].unlink()
        with self.assertRaises(FileNotFoundError):
            self.package()
        self.assertFalse((self.root / "build/fork-release").exists())

    def test_wrong_version_code_cannot_be_published(self):
        with self.assertRaisesRegex(ValueError, "package/version"):
            self.package(metadata=self.metadata.replace("versionCode='162'", "versionCode='161'"))

    def test_flutter_abi_version_offset_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "package/version"):
            self.package(metadata=self.metadata.replace("versionCode='162'", "versionCode='2162'"))

    def test_a_bad_final_apk_does_not_replace_the_previous_verified_release(self):
        output = self.root / "build/fork-release"
        output.mkdir()
        previous = output / "SOURCE.txt"
        previous.write_text("previous verified release")
        with self.assertRaisesRegex(ValueError, "package/version"):
            self.package(metadata_by_abi={"x86_64": self.metadata.replace("versionCode='162'", "versionCode='161'")})
        self.assertEqual(previous.read_text(), "previous verified release")
        self.assertEqual(list(output.iterdir()), [previous])

    def test_debuggable_apk_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "debuggable"):
            self.package(metadata=self.metadata + "application-debuggable\n")

    def test_universal_apk_cannot_be_mislabeled_as_one_architecture(self):
        with self.assertRaisesRegex(ValueError, "exactly that architecture"):
            self.package(metadata=self.metadata.replace("'{abi}'", "'arm64-v8a' 'armeabi-v7a' 'x86_64'"))

    def test_zip_cannot_hide_a_different_architecture(self):
        with ZipFile(self.apks["arm64-v8a"], "a", compression=ZIP_DEFLATED) as archive:
            archive.writestr("lib/x86_64/libapp.so", b"wrong architecture")
        with self.assertRaisesRegex(ValueError, "unexpected native libraries"):
            self.package()

    def test_uncompressed_native_libraries_are_rejected(self):
        with ZipFile(self.apks["arm64-v8a"], "w", compression=ZIP_STORED) as archive:
            archive.writestr("lib/arm64-v8a/libapp.so", b"uncompressed native")
        with self.assertRaisesRegex(ValueError, "must be compressed"):
            self.package()

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
