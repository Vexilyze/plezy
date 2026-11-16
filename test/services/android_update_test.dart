import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/android_update_release.dart';
import 'package:plezy/services/android_update_service.dart';

const repository = 'Vexilyze/plezy';

Map<String, dynamic> asset(String name, {String tag = 'v2.27.0+162', String? digest}) => {
  'state': 'uploaded',
  'name': name,
  'size': 4,
  'browser_download_url': 'https://github.com/$repository/releases/download/$tag/$name',
  'digest': ?digest,
};

Map<String, dynamic> release(String tag, String date, List<Map<String, dynamic>> assets, {bool prerelease = false}) => {
  'tag_name': tag,
  'published_at': date,
  'prerelease': prerelease,
  'draft': false,
  'assets': assets,
};

AndroidUpdateRelease downloadable({String? digest}) => AndroidUpdateRelease.newestCompatible(
  [
    release('v2.27.0+162', '2026-11-17', [asset('vexilyze-tv-android.apk', digest: digest)]),
  ],
  repository: repository,
  supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
)!;

void main() {
  group('Android release discovery', () {
    test('compares numeric versions and version codes without accepting prerelease tags', () {
      expect(AndroidReleaseVersion.parse('v2.26.1+162')!.isNewerThan('2.26.1', 161), isTrue);
      expect(AndroidReleaseVersion.parse('v2.26.1+161')!.isNewerThan('2.26.1', 161), isFalse);
      expect(AndroidReleaseVersion.parse('v2.27.0+160')!.isNewerThan('2.26.1', 161), isFalse);
      expect(AndroidReleaseVersion.parse('v2.27.0')!.isNewerThan('2.26.1', 161), isTrue);
      expect(AndroidReleaseVersion.parse('2.9.0')!.isNewerThan('2.10.0', 5), isFalse);
      expect(AndroidReleaseVersion.parse('v2.26.1')!.isNewerThan('2.26.1', 161), isFalse);
      expect(AndroidReleaseVersion.parse('v2.27.0-beta.1'), isNull);
      expect(AndroidReleaseVersion.parse('nightly'), isNull);
    });

    test('finds latest published compatible APK behind a desktop-only release', () {
      final found = AndroidUpdateRelease.newestCompatible(
        [
          release('v2.29.0', '2026-11-20', [asset('app.dmg')]),
          release('v2.28.0', '2026-11-19', [asset('app-arm64-v8a.apk')], prerelease: true),
          {
            ...release('v2.28.0', '2026-11-19', [asset('app.apk')]),
            'draft': true,
          },
          release('v2.27.0', '2026-11-18', [asset('app-x86_64.apk')]),
          release('v2.26.1+161', '2026-11-16', [asset('vexilyze-tv-android.apk')]),
          release('v2.26.0+160', '2026-11-15', [asset('app-arm64-v8a.apk')]),
        ],
        repository: repository,
        supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(found?.versionLabel, '2.26.1+161');
      expect(found?.assetName, 'vexilyze-tv-android.apk');
    });

    test('prefers device ABI order and rejects unsupported split APKs', () {
      final releases = [
        release('v2.27.0', '2026-11-18', [
          asset('app-armeabi-v7a.apk'),
          asset('app-x86.apk'),
          asset('app-arm64-v8a.apk'),
          asset('app-universal.apk'),
        ]),
      ];
      expect(
        AndroidUpdateRelease.newestCompatible(
          releases,
          repository: repository,
          supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
        )?.assetName,
        'app-arm64-v8a.apk',
      );
      expect(
        AndroidUpdateRelease.newestCompatible(
          releases,
          repository: repository,
          supportedAbis: ['x86_64', 'x86'],
        )?.assetName,
        'app-x86.apk',
      );
      expect(
        AndroidUpdateRelease.newestCompatible(
          [
            release('v2.27.0', '2026-11-18', [asset('app-arm64-v8a.apk')]),
          ],
          repository: repository,
          supportedAbis: ['armeabi-v7a'],
        ),
        isNull,
      );
    });

    test('a recently published backport cannot hide a higher upgrade version', () {
      final found = AndroidUpdateRelease.newestCompatible(
        [
          release('v2.26.1+161', '2026-11-20', [asset('app.apk')]),
          release('v2.27.0+163', '2026-11-18', [asset('app.apk')]),
          release('v2.26.2+162', '2026-11-19', [asset('app.apk')]),
        ],
        repository: repository,
        supportedAbis: ['arm64-v8a'],
        installedVersion: '2.26.1',
        installedBuild: 161,
      );
      expect(found?.versionLabel, '2.27.0+163');
    });

    test('a higher version with an unusable versionCode cannot mask a valid upgrade', () {
      final found = AndroidUpdateRelease.newestCompatible(
        [
          release('v3.0.0+150', '2026-11-20', [asset('app.apk')]),
          release('v2.27.0+163', '2026-11-18', [asset('app.apk')]),
        ],
        repository: repository,
        supportedAbis: ['arm64-v8a'],
        installedVersion: '2.26.1',
        installedBuild: 161,
      );
      expect(found?.versionLabel, '2.27.0+163');
    });

    test('does not offer untrusted, incomplete or malformed assets', () {
      for (final badAsset in [
        {...asset('app.apk'), 'browser_download_url': 'https://example.com/app.apk'},
        {...asset('app.apk'), 'browser_download_url': 'http://github.com/$repository/releases/download/v2/app.apk'},
        {...asset('app.apk'), 'browser_download_url': 'https://github.com/other/repo/releases/download/v2/app.apk'},
        {...asset('app.apk'), 'state': 'new'},
        {...asset('app.apk'), 'size': 0},
        asset('app.apk', digest: 'sha256:bad'),
      ]) {
        expect(
          AndroidUpdateRelease.newestCompatible(
            [
              release('v2.27.0', '2026-11-18', [badAsset]),
            ],
            repository: repository,
            supportedAbis: ['arm64-v8a'],
          ),
          isNull,
        );
      }
    });
  });

  group('APK download', () {
    late Directory directory;
    setUp(() async => directory = await Directory.systemTemp.createTemp('vexilyze-update-test-'));
    tearDown(() async => directory.delete(recursive: true));
    const bytes = [1, 2, 3, 4];

    test('streams a trusted GitHub redirect, reports progress, verifies checksum, and commits APK', () async {
      final requests = <Uri>[];
      final progress = <int>[];
      final downloader = AndroidApkDownloader(
        clientFactory: () => MockClient.streaming((request, _) async {
          requests.add(request.url);
          expect(request.followRedirects, isFalse);
          if (request.url.host == 'github.com') {
            return http.StreamedResponse(
              const Stream.empty(),
              302,
              headers: {
                'location': 'https://release-assets.githubusercontent.com/github-production-release-asset/file',
              },
            );
          }
          return http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
            200,
            contentLength: 4,
          );
        }),
      );
      final file = await downloader.download(
        downloadable(digest: 'sha256:${sha256.convert(bytes)}'),
        directory,
        onProgress: (received, _) => progress.add(received),
      );
      expect(await file.readAsBytes(), bytes);
      expect(file.path.endsWith('.apk'), isTrue);
      expect(requests.length, 2);
      expect(progress, [0, 2, 4]);
      expect(await directory.list().length, 1);
    });

    test('rejects redirects outside GitHub release storage without requesting them', () async {
      var requests = 0;
      final downloader = AndroidApkDownloader(
        clientFactory: () => MockClient.streaming((request, _) async {
          requests++;
          return http.StreamedResponse(
            const Stream.empty(),
            302,
            headers: {'location': 'https://attacker.example/app.apk'},
          );
        }),
      );
      await expectLater(downloader.download(downloadable(), directory, onProgress: (_, _) {}), throwsFormatException);
      expect(requests, 1);
      expect(await directory.list().isEmpty, isTrue);
    });

    test('deletes truncated and checksum-invalid downloads and permits retry', () async {
      for (final payload in [
        [1, 2],
        [4, 3, 2, 1],
      ]) {
        final downloader = AndroidApkDownloader(
          clientFactory: () => MockClient.streaming((_, _) async => http.StreamedResponse(Stream.value(payload), 200)),
        );
        await expectLater(
          downloader.download(
            downloadable(digest: 'sha256:${sha256.convert(bytes)}'),
            directory,
            onProgress: (_, _) {},
          ),
          throwsFormatException,
        );
        expect(await directory.list().isEmpty, isTrue);
      }
      final retry = AndroidApkDownloader(
        clientFactory: () => MockClient.streaming((_, _) async => http.StreamedResponse(Stream.value(bytes), 200)),
      );
      expect(await (await retry.download(downloadable(), directory, onProgress: (_, _) {})).readAsBytes(), bytes);
    });

    test('cancel removes partial data and releases the process-wide download guard', () async {
      final downloader = AndroidApkDownloader(
        clientFactory: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
            200,
          ),
        ),
      );
      await expectLater(
        downloader.download(
          downloadable(),
          directory,
          onProgress: (received, _) {
            if (received > 0) downloader.cancel();
          },
        ),
        throwsA(isA<AndroidUpdateCancelled>()),
      );
      expect(await directory.list().isEmpty, isTrue);
      final retry = AndroidApkDownloader(
        clientFactory: () => MockClient.streaming((_, _) async => http.StreamedResponse(Stream.value(bytes), 200)),
      );
      expect(await (await retry.download(downloadable(), directory, onProgress: (_, _) {})).readAsBytes(), bytes);
    });

    test('rejects a concurrent download without disturbing the first', () async {
      final response = Completer<http.StreamedResponse>();
      final first = AndroidApkDownloader(clientFactory: () => MockClient.streaming((_, _) => response.future));
      final firstDownload = first.download(downloadable(), directory, onProgress: (_, _) {});
      await expectLater(
        AndroidApkDownloader().download(downloadable(), directory, onProgress: (_, _) {}),
        throwsStateError,
      );
      response.complete(http.StreamedResponse(Stream.value(bytes), 200));
      expect(await (await firstDownload).readAsBytes(), bytes);
    });
  });
}
