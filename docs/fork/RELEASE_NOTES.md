# Plezy TV build 2.26.1+162

An independently maintained Android and Android TV fork of [Plezy](https://github.com/edde746/plezy), based on upstream commit `02eeba69723b33f28e6b8ae9dab2ce1c02a1c3cd`.

## Name and download size

The owner-facing app name, launcher icon, splash icon and sign-in logo are restored to **Plezy** for personal TV installations. This remains an independently modified build, not an official Plezy release.

The former 276 MB universal APK is replaced by three standalone APKs, each containing only one processor architecture. Native libraries are compressed in the download and extracted by Android during installation. Installed storage usage is larger than the APK download size.

- `plezy-android-arm64-v8a.apk`: 64-bit ARM devices.
- `plezy-android-armeabi-v7a.apk`: 32-bit ARM devices.
- `plezy-android-x86_64.apk`: x86_64 devices/emulators.

For the Google TV Streamer 4K, start with the ARMv7 (32-bit) APK: its Android userspace has been reported as 32-bit despite the 64-bit CPU ([device installation report](https://github.com/yuliskov/SmartTube/issues/4620)). The updater reads Android’s supported ABIs and chooses the matching APK automatically. All three use versionCode **162** and the same signing key as build 161, so existing fork installations update normally and retain their data.

## TV sleep timer

The sleep timer can now pause playback, save progress, and put an Android TV device to sleep. Both timed expiry and end-of-video use this behavior. Continue Watching, cancelling the timer, or manually pausing do not put the device to sleep.

On your Google TV Streamer 4K:

1. Open **Settings → Playback → TV sleep timer** in Plezy.
2. Turn on **Sleep this device when the timer finishes** and use **Open accessibility settings** to enable **Plezy sleep timer**.
3. Enable HDMI-CEC power control on both your Streamer and television so the television follows the Streamer into standby.

The accessibility service requests only Android's screen-lock action. It does not read screen content or monitor input. If Android blocks the sideloaded service, allow restricted settings for Plezy in Android's app settings first. Android TV 9 or later is required for device sleep. Physical TV standby depends on HDMI-CEC and has not been verified on your television.

## Updates

The app checks this fork's published GitHub releases at startup, with a six-hour check interval, and notifies you when a compatible Android update is available. You can also check manually in Settings. Download and install from the update dialog; Android asks you to allow installation from this app the first time and confirm each update.

Updates are checked for package identity, signing key, build number, compatible processor, download size and the GitHub SHA-256 digest when available. Future releases use the same signing key and preserve this app's data.

## First installation

Install the APK matching your device architecture. The app displays **Plezy**, but retains the fork package ID (`com.vexilyze.tv`) and signing key so its updates remain compatible. The original upstream installation uses a different package ID and signing key; its data is not automatically transferred. Uninstalling the original app clears its app-private settings and downloads. Sign in to your server again after installing this fork for the first time.

Plex, Jellyfin and Emby connections remain available. Upstream-operated hosted services, shared tracker OAuth registrations, Discord presence and telemetry are disabled for this independent fork. This is not an official Plezy release.

Source, license, build instructions and upstream merge guidance are included in the repository's [release documentation](https://github.com/Vexilyze/plezy/blob/vexilyze/android-tv/docs/fork/RELEASING.md).
