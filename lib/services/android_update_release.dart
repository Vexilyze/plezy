/// Release metadata shared by the updater and its tests. Android's installer
/// checks the APK's actual version code, package and signer before handoff.
final class AndroidReleaseVersion implements Comparable<AndroidReleaseVersion> {
  const AndroidReleaseVersion(this.parts, this.build);

  final List<int> parts;
  final int? build;

  static AndroidReleaseVersion? parse(String value) {
    final match = RegExp(r'^v?(\d+\.\d+\.\d+)(?:\+(\d+))?$').firstMatch(value.trim());
    if (match == null) return null;
    return AndroidReleaseVersion(match[1]!.split('.').map(int.parse).toList(), int.tryParse(match[2] ?? ''));
  }

  @override
  int compareTo(AndroidReleaseVersion other) {
    for (var i = 0; i < parts.length; i++) {
      final comparison = parts[i].compareTo(other.parts[i]);
      if (comparison != 0) return comparison;
    }
    return (build ?? 0).compareTo(other.build ?? 0);
  }

  bool isNewerThan(String installedVersion, int installedBuild) {
    final installed = parse(installedVersion);
    if (installed == null) throw const FormatException('Installed version is unavailable');
    // Android rejects a versionCode downgrade even when the version name rises.
    if (build != null && build! <= installedBuild) return false;
    return compareTo(AndroidReleaseVersion(installed.parts, installedBuild)) > 0;
  }
}

final class AndroidUpdateRelease {
  const AndroidUpdateRelease({
    required this.repository,
    required this.version,
    required this.versionLabel,
    required this.name,
    required this.notes,
    required this.releaseUrl,
    required this.publishedAt,
    required this.assetName,
    required this.downloadUrl,
    required this.size,
    this.sha256,
  });

  final String repository;
  final AndroidReleaseVersion version;
  final String versionLabel;
  final String name;
  final String notes;
  final String releaseUrl;
  final DateTime publishedAt;
  final String assetName;
  final Uri downloadUrl;
  final int size;
  final String? sha256;

  static bool isTrustedAssetUrl(Uri uri, String repository) {
    final repoParts = repository.toLowerCase().split('/');
    final parts = uri.pathSegments;
    return repoParts.length == 2 &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        parts.length == 6 &&
        parts[0].toLowerCase() == repoParts[0] &&
        parts[1].toLowerCase() == repoParts[1] &&
        parts[2] == 'releases' &&
        parts[3] == 'download' &&
        parts[4].isNotEmpty &&
        parts[5].toLowerCase().endsWith('.apk');
  }

  /// Select the highest stable version that actually has an APK this device
  /// can install. A newly published backport must not hide a newer version.
  static AndroidUpdateRelease? newestCompatible(
    List<dynamic> releases, {
    required String repository,
    required List<String> supportedAbis,
    String? installedVersion,
    int? installedBuild,
  }) {
    final candidates = <AndroidUpdateRelease>[];
    for (final raw in releases) {
      if (raw is! Map || raw['draft'] == true || raw['prerelease'] == true) continue;
      final tag = raw['tag_name'];
      if (tag is! String) continue;
      final version = AndroidReleaseVersion.parse(tag);
      final published = DateTime.tryParse(raw['published_at']?.toString() ?? '');
      final assets = raw['assets'];
      if (version == null || published == null || assets is! List) continue;
      if (installedVersion != null &&
          installedBuild != null &&
          !version.isNewerThan(installedVersion, installedBuild)) {
        continue;
      }
      Map? selected;
      var bestScore = -1;
      for (final asset in assets) {
        if (asset is! Map || asset['state'] != 'uploaded') continue;
        final name = asset['name'];
        final url = Uri.tryParse(asset['browser_download_url']?.toString() ?? '');
        final size = asset['size'];
        if (name is! String ||
            !name.toLowerCase().endsWith('.apk') ||
            url == null ||
            !isTrustedAssetUrl(url, repository) ||
            size is! int ||
            size <= 0 ||
            size > 1024 * 1024 * 1024) {
          continue;
        }
        final digest = asset['digest'];
        if (digest != null && (digest is! String || !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest))) continue;
        final score = _abiScore(name, supportedAbis);
        if (score > bestScore) {
          selected = asset;
          bestScore = score;
        }
      }
      if (selected == null) continue;
      candidates.add(
        AndroidUpdateRelease(
          repository: repository,
          version: version,
          versionLabel: tag.startsWith('v') ? tag.substring(1) : tag,
          name: raw['name']?.toString() ?? tag,
          notes: raw['body']?.toString() ?? '',
          releaseUrl: 'https://github.com/$repository/releases/tag/${Uri.encodeComponent(tag)}',
          publishedAt: published,
          assetName: selected['name'] as String,
          downloadUrl: Uri.parse(selected['browser_download_url'] as String),
          size: selected['size'] as int,
          sha256: (selected['digest'] as String?)?.substring(7).toLowerCase(),
        ),
      );
    }
    candidates.sort((a, b) {
      final version = b.version.compareTo(a.version);
      return version != 0 ? version : b.publishedAt.compareTo(a.publishedAt);
    });
    return candidates.firstOrNull;
  }

  static int _abiScore(String assetName, List<String> supportedAbis) {
    final name = assetName.toLowerCase();
    final aliases = <String, List<String>>{
      'arm64-v8a': ['arm64-v8a', 'arm64', 'aarch64'],
      'armeabi-v7a': ['armeabi-v7a', 'armv7'],
      'x86_64': ['x86_64', 'x64'],
      'x86': ['x86'],
    };
    String? assetAbi;
    for (final entry in aliases.entries) {
      if (entry.value.any((alias) => RegExp('(^|[-_.])${RegExp.escape(alias)}([-_.]|\$)').hasMatch(name))) {
        assetAbi = entry.key;
        break;
      }
    }
    if (assetAbi == null || name.contains('universal')) return 1;
    final index = supportedAbis.indexOf(assetAbi);
    return index < 0 ? -1 : 100 - index;
  }
}

final class NoCompatibleAndroidRelease implements Exception {
  const NoCompatibleAndroidRelease();
}
