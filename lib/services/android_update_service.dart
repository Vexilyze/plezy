import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'android_update_release.dart';

final class AndroidUpdateDevice {
  const AndroidUpdateDevice({required this.version, required this.build, required this.abis, required this.directory});
  final String version;
  final int build;
  final List<String> abis;
  final Directory directory;
}

/// The Android side uses the installed package identity, never a release's
/// claimed identity, when validating an APK and granting installer access.
class AndroidUpdateInstaller {
  static const _channel = MethodChannel('com.vexilyze/app_updates');

  static Future<AndroidUpdateDevice> device() async {
    final info = await _channel.invokeMapMethod<String, dynamic>('deviceInfo');
    if (info == null) throw StateError('Android update support unavailable');
    return AndroidUpdateDevice(
      version: info['versionName'] as String,
      build: info['versionCode'] as int,
      abis: List<String>.from(info['supportedAbis'] as List),
      directory: Directory(info['updateDirectory'] as String),
    );
  }

  static Future<void> validate(File apk) => _channel.invokeMethod<void>('validateApk', {'path': apk.path});
  static Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;
  static Future<void> openInstallPermission() => _channel.invokeMethod<void>('openInstallPermission');
  static Future<void> install(File apk) => _channel.invokeMethod<void>('installApk', {'path': apk.path});
}

final class AndroidUpdateCancelled implements Exception {
  const AndroidUpdateCancelled();
}

/// Streaming download into app-private cache. A single process-wide transfer
/// prevents two dialogs from starting competing APK downloads. The UI owns the
/// returned file; a partial or rejected file is never retained.
class AndroidApkDownloader {
  AndroidApkDownloader({http.Client Function()? clientFactory}) : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  static AndroidApkDownloader? _active;
  http.Client? _client;
  Completer<void>? _abort;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _client?.close();
  }

  void _checkCancelled() {
    if (_cancelled) throw const AndroidUpdateCancelled();
  }

  static bool _trustedRedirect(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty &&
      const {'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}.contains(uri.host);

  Future<File> download(
    AndroidUpdateRelease release,
    Directory directory, {
    required void Function(int received, int total) onProgress,
  }) async {
    if (_active != null) throw StateError('An update download is already running');
    if (!AndroidUpdateRelease.isTrustedAssetUrl(release.downloadUrl, release.repository)) {
      throw const FormatException('Untrusted update URL');
    }
    _active = this;
    _cancelled = false;
    _abort = Completer<void>();
    File? partial;
    File? completed;
    IOSink? sink;
    var accepted = false;
    try {
      await directory.create(recursive: true);
      _checkCancelled();
      // Old completed APKs may still be held by Android's package installer.
      // Unique files avoid overwriting an installation already in progress.
      final stem = '${directory.path}/update-${DateTime.now().microsecondsSinceEpoch}';
      partial = File('$stem.apk.part');
      completed = File('$stem.apk');
      final client = _client = _clientFactory();
      var url = release.downloadUrl;
      http.StreamedResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        _checkCancelled();
        if (!_trustedRedirect(url)) throw const FormatException('Untrusted update redirect');
        final request = http.AbortableRequest('GET', url, abortTrigger: _abort!.future)
          ..followRedirects = false
          ..headers['Accept'] = 'application/octet-stream';
        final candidate = await client.send(request).timeout(const Duration(seconds: 30));
        if (const {301, 302, 303, 307, 308}.contains(candidate.statusCode)) {
          final location = candidate.headers['location'];
          await candidate.stream.listen((_) {}).cancel();
          if (location == null || redirects == 5) throw const HttpException('Invalid update redirect');
          url = url.resolve(location);
          continue;
        }
        response = candidate;
        break;
      }
      if (response == null || response.statusCode != 200) {
        throw HttpException('Update download returned HTTP ${response?.statusCode}');
      }
      if (response.contentLength != null && response.contentLength != release.size) {
        throw const FormatException('Update download size does not match the release');
      }
      var received = 0;
      onProgress(0, release.size);
      sink = partial.openWrite();
      await sink.addStream(
        response.stream.timeout(const Duration(seconds: 30)).map((bytes) {
          _checkCancelled();
          received += bytes.length;
          if (received > release.size) throw const FormatException('Update download exceeds the release size');
          onProgress(received, release.size);
          return bytes;
        }),
      );
      await sink.flush();
      await sink.close();
      sink = null;
      _checkCancelled();
      if (received != release.size) throw const FormatException('Update download is incomplete');
      if (release.sha256 != null) {
        final digest = await sha256.bind(partial.openRead()).first;
        if (digest.toString() != release.sha256) throw const FormatException('Update checksum does not match');
      }
      _checkCancelled();
      await partial.rename(completed.path);
      accepted = true;
      return completed;
    } catch (_) {
      _checkCancelled();
      rethrow;
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // Keep the original transfer failure while cleaning its partial file.
      }
      _client?.close();
      _client = null;
      _abort = null;
      try {
        if (partial != null && await partial.exists()) await partial.delete();
        if (!accepted && completed != null && await completed.exists()) await completed.delete();
      } finally {
        _active = null;
      }
    }
  }
}
