# Vexilyze TV 2.26.1+161

An independently maintained Android and Android TV fork of [Plezy](https://github.com/edde746/plezy), based on upstream commit `02eeba69723b33f28e6b8ae9dab2ce1c02a1c3cd`.

## TV sleep timer

The sleep timer can now pause playback, save progress, and put an Android TV device to sleep. Both timed expiry and end-of-video use this behavior. Continue Watching, cancelling the timer, or manually pausing do not put the device to sleep.

On your Google TV Streamer 4K:

1. Open **Settings → Playback → TV sleep timer** in Vexilyze TV.
2. Turn on **Sleep this device when the timer finishes** and use **Open accessibility settings** to enable **Vexilyze TV sleep timer**.
3. Enable HDMI-CEC power control on both your Streamer and television so the television follows the Streamer into standby.

The accessibility service requests only Android's screen-lock action. It does not read screen content or monitor input. If Android blocks the sideloaded service, allow restricted settings for Vexilyze TV in Android's app settings first. Android TV 9 or later is required for device sleep. Physical TV standby depends on HDMI-CEC and has not been verified on your television.

## Updates

The app checks this fork's published GitHub releases at startup, with a six-hour check interval, and notifies you when a compatible Android update is available. You can also check manually in Settings. Download and install from the update dialog; Android asks you to allow installation from this app the first time and confirm each update.

Updates are checked for package identity, signing key, build number, compatible processor, download size and the GitHub SHA-256 digest when available. Future releases use the same signing key and preserve this app's data.

## First installation

Install **vexilyze-tv-android.apk**, a universal release APK for ARMv7, ARM64 and x86_64. Vexilyze TV has its own app identity (`com.vexilyze.tv`) and installs alongside Plezy. Sign in to your server again; existing Plezy downloads and settings are not automatically transferred.

Plex, Jellyfin and Emby connections remain available. Upstream-operated hosted services, shared tracker OAuth registrations, Discord presence and telemetry are disabled for this independent fork. This is not an official Plezy release.

Source, license, build instructions and upstream merge guidance are included in the repository's [release documentation](https://github.com/Vexilyze/plezy/blob/vexilyze/android-tv/docs/fork/RELEASING.md).
