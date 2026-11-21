# Personal Plezy Android TV builds

This independently modified TV build displays **Plezy** for the owner's personal installations.
Its Android application ID remains `com.vexilyze.tv`, and it keeps the build 161 signing key.
Kotlin namespaces stay unchanged so upstream changes remain easy to merge. These APKs update
previous fork installs in place, but do not replace or inherit the original upstream app's data.

## Build and signing inputs

- Flutter **3.47.1**, commit `6655482ec06e547f90abf8ae7590466f4415978d` (the upstream SDK pin).
- Java 21; Android platform 36, build tools 36.1.0, NDK 29.0.14206865, CMake 4.1.2.
- Dependencies pinned in `pubspec.lock` and `mpv-build.lock.json`.
- One permanent release signing key. The public certificate's SHA-256 is committed in
  `android/release-signing-certificate.sha256`; the keystore and passwords are never committed.

Keep an encrypted backup of the keystore and its credentials outside this repository. All future
updates must use this key and application ID. Losing the key prevents updates to installed copies
without an uninstall. Never generate a replacement key as part of a normal release.

For GitHub Actions, configure these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded release keystore |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Signing key password |
| `ANDROID_KEY_ALIAS` | Signing key alias |

`scripts/fork/prepare_android_signing.py` reads those environment variables and creates ignored,
private `android/key.properties` and `android/app/vexilyze-release.jks`. It fails when credentials
are missing and refuses to overwrite existing local signing files. A local build can instead
use an existing `android/key.properties` pointing at the backed-up key. Its `storeFile` path is
resolved relative to `android/app`, so an absolute path is least ambiguous.

To record the initial public certificate pin, export the certificate from the permanent key and
hash its DER bytes. This uses a password prompt instead of putting a password on the command line:

```bash
keytool -exportcert -keystore /path/to/release.jks -alias YOUR_ALIAS -file /tmp/vexilyze-release.der
sha256sum /tmp/vexilyze-release.der | cut -d ' ' -f 1 > android/release-signing-certificate.sha256
rm /tmp/vexilyze-release.der
```

## Local build

Set `ANDROID_HOME` and put the pinned Flutter SDK on `PATH`, then run:

```bash
bash scripts/fork/build_android.sh
```

The script produces three standalone APKs in
`build/fork-release/`: `plezy-android-arm64-v8a.apk`, `plezy-android-armeabi-v7a.apk`, and
`plezy-android-x86_64.apk`, each with its own SHA-256 file. The output also contains the public
signing certificate fingerprint, source attribution, license and release notes. Packaging verifies
each APK's signature against the committed fingerprint, package ID, display name, version,
non-debuggable flag, compressed native libraries and exact single architecture. Release builds
cannot fall back to debug signing.

Flutter normally adds an architecture offset to split APK version codes. This project sets
`force-version-code-ignoring-abi=true` so every APK uses the exact numeric build from
`pubspec.yaml`. Preserve this setting: Vex Updates and Android’s installer both rely on monotonic
version codes, including upgrades from the universal build 161.

`android.packaging.jniLibs.useLegacyPackaging=true` compresses native libraries in each APK.
Android extracts them at installation, so the smaller download is not the installed app's size.
The ABI split also avoids storing unused architectures on the device.

Builds use pinned source and dependency inputs; byte-for-byte reproducibility across hosts is
not promised. Keep the published APK and its checksum as the exact release artifact.

## Publish an update

1. Merge and test upstream changes on `vexilyze/android-tv`.
2. Update `pubspec.yaml` and `docs/fork/RELEASE_NOTES.md`. Increase the numeric build number on
   **every release**, even when the human-readable version stays the same. The first fork release
   is `2.26.1+161`; do not let an upstream merge lower the fork's versionCode.
3. Commit the changes and push the branch to `origin`.
4. Tag that exact commit with `v` followed by the complete pubspec version, including `+build`:

```bash
git tag -a 'v2.26.1+164' -m 'Plezy TV build 2.26.1+164'
git push origin 'v2.26.1+164'
```

The **Plezy Android release** workflow runs only in `Vexilyze/plezy`. It analyzes the
project, runs focused playback tests, builds and verifies the three signed architecture-specific APKs, and
publishes a GitHub Release. Upstream's desktop build workflow is not triggered. A missing secret,
mismatched signer or existing release causes failure instead of publishing another kind of APK.

The workflow can also be dispatched from `vexilyze/android-tv` to produce an Actions artifact
without publishing. GitHub only exposes manual dispatch after the workflow exists on the
repository's default branch. For a manual publication, the version tag must already point at
the exact selected commit. The tag-triggered path works for the first release.

Set the repository Actions secret `VEX_UPDATES_TOKEN` to a publishing token scoped to `plezy`. Successful tagged releases publish each signed APK to the phone and TV catalog at https://updates.vexilar.io. Desktop packages are distributed through their usual release download or platform store.

## Keep the fork current

Use `origin` for `Vexilyze/plezy` and `upstream` for `edde746/plezy`. Keep `main` as the upstream
mirror and retain fork changes on `vexilyze/android-tv`:

```bash
git fetch upstream
git switch main
git merge --ff-only upstream/main
git push origin main
git switch vexilyze/android-tv
git merge main
```

Resolve conflicts, check the release signing rules, versionCode, catalog publication and fork
branding, run the relevant tests, then push the custom branch. Do not force-reset the custom
branch to upstream: that would discard the fork features. Existing users receive the change
only after a new signed APK is released and installed.

## Distribution identity

Retain the upstream `LICENSE` and attribution. The owner requested the original Plezy display
name and icon for personal TV installations; the fork package ID, publishing project, signing key
and URL scheme remain independent. This is not an official Plezy build. Consult `TRADEMARKS.md`
for the upstream project's naming and redistribution terms before distribution beyond personal use.

Upstream-operated services and third-party app registrations remain disabled unless replaced
with services/registrations controlled by the fork owner. Do not enable upstream telemetry or
donations. The release source archive and `SOURCE.txt` identify corresponding source and build instructions.
