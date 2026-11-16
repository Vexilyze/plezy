import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/android_update_release.dart';
import 'package:plezy/services/android_update_service.dart';
import 'package:plezy/utils/android_update_dialog.dart';
import 'package:plezy/widgets/dialog_action_button.dart';

class _Download extends AndroidApkDownloader {
  final complete = Completer<File>();
  void Function(int, int)? progress;
  bool cancelled = false;

  @override
  Future<File> download(
    AndroidUpdateRelease release,
    Directory directory, {
    required void Function(int, int) onProgress,
  }) {
    progress = onProgress;
    return complete.future;
  }

  @override
  void cancel() {
    cancelled = true;
    if (!complete.isCompleted) complete.completeError(const AndroidUpdateCancelled());
  }
}

final _release = AndroidUpdateRelease(
  repository: 'Vexilyze/plezy',
  version: const AndroidReleaseVersion([2, 27, 0], 162),
  versionLabel: '2.27.0+162',
  name: 'Update',
  notes: '',
  releaseUrl: 'https://github.com/Vexilyze/plezy/releases/tag/v2.27.0+162',
  publishedAt: DateTime(2026, 11, 17),
  assetName: 'vexilyze-tv-android.apk',
  downloadUrl: Uri.parse('https://github.com/Vexilyze/plezy/releases/download/v2.27.0+162/vexilyze-tv-android.apk'),
  size: 4 * 1048576,
);

Future<void> _open(WidgetTester tester, _Download download) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => AndroidUpdateDialog(
                  release: _release,
                  currentVersion: '2.26.1+161',
                  title: 'Update available',
                  dismissLabel: 'Close',
                  showSkipVersion: false,
                  downloader: download,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  const channel = MethodChannel('com.vexilyze/app_updates');
  late List<String> calls;
  var allowed = false;
  Completer<void>? pendingInstall;
  setUp(() {
    calls = [];
    allowed = false;
    pendingInstall = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'installApk' && pendingInstall != null) {
        await pendingInstall!.future;
        return null;
      }
      return switch (call.method) {
        'deviceInfo' => {
          'versionName': '2.26.1',
          'versionCode': 161,
          'supportedAbis': ['arm64-v8a'],
          'updateDirectory': '/unused',
        },
        'canInstall' => allowed,
        _ => null,
      };
    });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  testWidgets('TV select downloads, shows progress, and Back cancels the transfer', (tester) async {
    final download = _Download();
    await _open(tester, download);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(download.progress, isNotNull);
    download.progress!(1048576, _release.size);
    await tester.pump();
    expect(find.text(t.androidUpdater.progress(received: '1.0', total: '4.0')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AndroidUpdateDialog), findsNothing);
    expect(download.cancelled, isTrue);
    expect(calls, isNot(contains('installApk')));
  });

  testWidgets('permission return validates the APK and hands off once to the Android installer', (tester) async {
    final download = _Download();
    await _open(tester, download);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    download.complete.complete(File('/unused/update.apk'));
    await tester.pumpAndSettle();
    expect(calls, contains('validateApk'));
    expect(calls, isNot(contains('installApk')));
    expect(find.text(t.androidUpdater.permissionRequired), findsOneWidget);
    await tester.tap(find.text(t.androidUpdater.allowInstallation));
    await tester.pumpAndSettle();
    expect(calls, contains('openInstallPermission'));
    allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'installApk'), hasLength(1));
    expect(find.text(t.androidUpdater.installerOpened), findsOneWidget);
    // Resuming after a cancelled installer must not reopen it in a loop.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'installApk'), hasLength(1));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  for (final succeeds in [true, false]) {
    testWidgets('pending native handoff blocks Back and retains its APK until ${succeeds ? 'success' : 'failure'}', (
      tester,
    ) async {
      final directory = await tester.runAsync(() => Directory.systemTemp.createTemp('vexilyze-handoff-'));
      final apk = File('${directory!.path}/update.apk');
      await tester.runAsync(() => apk.writeAsBytes([1, 2, 3, 4]));
      addTearDown(() => directory.delete(recursive: true));
      allowed = true;
      pendingInstall = Completer<void>();
      final download = _Download();
      await _open(tester, download);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      download.complete.complete(apk);
      await tester.pump();
      await tester.pump();
      expect(calls, contains('installApk'));
      final cancel = tester.widget<DialogActionButton>(find.widgetWithText(DialogActionButton, t.common.cancel));
      expect(cancel.onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AndroidUpdateDialog), findsOneWidget);
      expect(await tester.runAsync(apk.exists), isTrue);

      // A parent can still remove the route programmatically. Its disposal must
      // preserve an APK the native worker/installer may already be reading.
      Navigator.of(tester.element(find.byType(AndroidUpdateDialog))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AndroidUpdateDialog), findsNothing);
      expect(await tester.runAsync(apk.exists), isTrue);
      await tester.runAsync(() async {
        if (succeeds) {
          pendingInstall!.complete();
        } else {
          pendingInstall!.completeError(PlatformException(code: 'UPDATE_FAILED'));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(await tester.runAsync(apk.exists), succeeds);
    });
  }
}
