# Plezy TV build 2.26.1+164

An independently maintained Android and Android TV fork of [Plezy](https://github.com/edde746/plezy), synced with upstream `main` through commit `8310991fa`.

## Upstream updates

This release includes all ten upstream commits since the previous fork base:

- Reach the profile menu with the TV remote when the Home screen is empty.
- Restore the configured profile prompt after resuming a TV that hosts the companion remote server.
- Keep download sync rules from restarting downloads after a storage-related stop.
- Respect Plex's current media-deletion setting before offering or performing a deletion.
- Improve library controls and long library names on narrow phone screens.
- Add European Portuguese and improve locale selection.
- Include upstream iOS and macOS storage and external-display fixes in the synced source.

The Plezy name and icon, TV sleep timer, compressed APKs for each processor, package ID and signing key remain unchanged. Install this as an update to keep existing settings and downloads.

## Central updates

Vex Updates delivers Plezy on Android phones and televisions. The fork's built-in update checks, update prompts and Android installer remain removed.

## Name and download size

The owner-facing app name, launcher icon, splash icon and sign-in logo are restored to **Plezy** for personal TV installations. This remains an independently modified build, not an official Plezy release.

The former 276 MB universal APK is replaced by three standalone APKs, each containing only one processor architecture. Native libraries are compressed in the download and extracted by Android during installation. Installed storage usage is larger than the APK download size.

- `plezy-android-arm64-v8a.apk`: 64-bit ARM devices.
- `plezy-android-armeabi-v7a.apk`: 32-bit ARM devices.
- `plezy-android-x86_64.apk`: x86_64 devices/emulators.

For the Google TV Streamer 4K, use the ARMv7 (32-bit) APK; this architecture was confirmed on the owner's device. Vex Updates reads Android’s supported ABIs and chooses the matching APK automatically. All three use versionCode **164** and the same signing key as earlier fork builds, so existing fork installations update normally and retain their data.

## TV sleep timer

The sleep timer can now pause playback, save progress, and put an Android TV device to sleep. Both timed expiry and end-of-video use this behavior. Continue Watching, cancelling the timer, or manually pausing do not put the device to sleep.

On your Google TV Streamer 4K:

1. Open **Settings → Playback → TV sleep timer** in Plezy.
2. Turn on **Sleep this device when the timer finishes** and use **Open accessibility settings** to enable **Plezy sleep timer**.
3. Enable HDMI-CEC power control on both your Streamer and television so the television follows the Streamer into standby.

The accessibility service requests only Android's screen-lock action. It does not read screen content or monitor input. Android TV 9 or later is required for device sleep. Physical TV standby depends on HDMI-CEC and has not been verified on your television.

If the Accessibility switch immediately turns off, Android may have blocked restricted settings for the APK. This can recur after installation. Allow restricted settings for Plezy in Android's app settings if that option exists. On the Google TV Streamer, after connecting ADB to that device, the verified recovery is:

```sh
adb shell appops set com.vexilyze.tv ACCESS_RESTRICTED_SETTINGS allow
adb shell appops write-settings
```

Then enable **Plezy sleep timer** in Accessibility again. This is a device permission; reinstalling the APK does not fix it.

## Updates

The Vex Updates catalog delivers signed Plezy APKs for Android phones and TVs at https://updates.vexilar.io. Use the usual platform release downloads or store for desktop builds. This fork has removed its built-in update checks and installer.

## First installation

Install the APK matching your device architecture. The app displays **Plezy**, but retains the fork package ID (`com.vexilyze.tv`) and signing key so its updates remain compatible. The original upstream installation uses a different package ID and signing key; its data is not automatically transferred. Uninstalling the original app clears its app-private settings and downloads. Sign in to your server again after installing this fork for the first time.

Plex, Jellyfin and Emby connections remain available. Upstream-operated hosted services, shared tracker OAuth registrations, Discord presence and telemetry are disabled for this independent fork. This is not an official Plezy release.

Source, license, build instructions and upstream merge guidance are included in the repository's [release documentation](https://github.com/Vexilyze/plezy/blob/vexilyze/android-tv/docs/fork/RELEASING.md).
