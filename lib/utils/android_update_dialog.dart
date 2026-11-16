import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.g.dart';
import '../services/android_update_release.dart';
import '../services/android_update_service.dart';
import '../services/update_service.dart';
import '../widgets/dialog_action_button.dart';
import 'app_logger.dart';

enum _UpdateStage { offered, downloading, verifying, permission, installer, failed }

class AndroidUpdateDialog extends StatefulWidget {
  const AndroidUpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
    required this.title,
    required this.dismissLabel,
    required this.showSkipVersion,
    this.downloader,
  });

  final AndroidUpdateRelease release;
  final String currentVersion;
  final String title;
  final String dismissLabel;
  final bool showSkipVersion;

  /// Injectable transfer for dialog/permission lifecycle tests.
  final AndroidApkDownloader? downloader;

  @override
  State<AndroidUpdateDialog> createState() => _AndroidUpdateDialogState();
}

class _AndroidUpdateDialogState extends State<AndroidUpdateDialog> with WidgetsBindingObserver {
  late final _downloader = widget.downloader ?? AndroidApkDownloader();
  _UpdateStage _stage = _UpdateStage.offered;
  File? _apk;
  String? _error;
  int _received = 0;
  bool _waitingForPermission = false;
  bool _handedToInstaller = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _downloader.cancel();
    // The installer may still be reading its content URI after this dialog
    // closes. Native cache housekeeping reclaims handed-off APKs later.
    // If a parent route disappears while native validation/handoff is pending,
    // its result owns cleanup. Deleting now could break an installer already
    // opening the content URI before the method-channel result arrives.
    if (!_handedToInstaller && !_installing) unawaited(_discardApk());
    super.dispose();
  }

  Future<void> _discardApk() async {
    final apk = _apk;
    _apk = null;
    try {
      if (apk != null && await apk.exists()) await apk.delete();
    } catch (error) {
      appLogger.d('Could not remove update cache file', error: error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForPermission) {
      _waitingForPermission = false;
      unawaited(_continueAfterPermission());
    }
  }

  Future<void> _continueAfterPermission() async {
    try {
      final allowed = await AndroidUpdateInstaller.canInstall();
      if (!mounted) return;
      if (allowed) await _install();
    } catch (error, stack) {
      _showFailure(error, stack, installing: true);
    }
  }

  Future<void> _download() async {
    if (_stage == _UpdateStage.downloading || _stage == _UpdateStage.verifying) return;
    setState(() {
      _stage = _UpdateStage.downloading;
      _error = null;
      _received = 0;
    });
    try {
      await _discardApk();
      final device = await AndroidUpdateInstaller.device();
      if (!mounted) return;
      final apk = await _downloader.download(
        widget.release,
        device.directory,
        onProgress: (received, total) {
          if (mounted) setState(() => _received = received);
        },
      );
      _apk = apk;
      if (!mounted) {
        await _discardApk();
        return;
      }
      setState(() => _stage = _UpdateStage.verifying);
      await AndroidUpdateInstaller.validate(apk);
      if (!mounted) return;
      await _install();
    } on AndroidUpdateCancelled {
      // Closing the dialog owns cancellation; the downloader cleans partials.
    } catch (error, stack) {
      await _discardApk();
      _showFailure(error, stack);
    }
  }

  Future<void> _install() async {
    final apk = _apk;
    if (apk == null || _installing || !mounted) return;
    setState(() => _installing = true);
    try {
      if (!await AndroidUpdateInstaller.canInstall()) {
        if (mounted) setState(() => _stage = _UpdateStage.permission);
        return;
      }
      if (!mounted) return;
      await AndroidUpdateInstaller.install(apk);
      _handedToInstaller = true;
      if (mounted) setState(() => _stage = _UpdateStage.installer);
    } on PlatformException catch (error, stack) {
      if (error.code == 'INSTALL_PERMISSION') {
        if (mounted) setState(() => _stage = _UpdateStage.permission);
      } else {
        _showFailure(error, stack, installing: true);
      }
    } catch (error, stack) {
      _showFailure(error, stack, installing: true);
    } finally {
      if (mounted) {
        setState(() => _installing = false);
      } else {
        _installing = false;
        if (!_handedToInstaller) await _discardApk();
      }
    }
  }

  Future<void> _allowInstallation() async {
    try {
      if (await AndroidUpdateInstaller.canInstall()) {
        if (mounted) await _install();
        return;
      }
      if (!mounted) return;
      _waitingForPermission = true;
      await AndroidUpdateInstaller.openInstallPermission();
    } catch (error, stack) {
      _waitingForPermission = false;
      _showFailure(error, stack, installing: true);
    }
  }

  void _showFailure(Object error, StackTrace stack, {bool installing = false}) {
    appLogger.w('Android app update failed', error: error, stackTrace: stack);
    if (!mounted) return;
    final strings = t.androidUpdater;
    final message = switch (error) {
      PlatformException(code: 'WRONG_PACKAGE') => strings.wrongPackage,
      PlatformException(code: 'WRONG_SIGNATURE') => strings.wrongSignature,
      PlatformException(code: 'NOT_NEWER') => strings.notNewer,
      PlatformException(code: 'UNSUPPORTED') => strings.unsupported,
      PlatformException(code: 'INVALID_APK') || FormatException() => strings.invalidDownload,
      _ => installing ? strings.installFailed : strings.downloadFailed,
    };
    setState(() {
      _stage = _UpdateStage.failed;
      _error = message;
    });
  }

  void _close() {
    if (!_installing) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _installing || _stage == _UpdateStage.downloading || _stage == _UpdateStage.verifying;
    final strings = t.androidUpdater;
    return PopScope(
      canPop: !_installing,
      child: FocusTraversalGroup(
        child: AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.update.versionAvailable(version: widget.release.versionLabel)),
                  const SizedBox(height: 8),
                  Text(
                    t.update.currentVersion(version: widget.currentVersion),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (busy) ...[
                    const SizedBox(height: 20),
                    Text(
                      _installing || (_installing || _stage == _UpdateStage.verifying)
                          ? strings.verifying
                          : strings.downloading,
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _installing || (_installing || _stage == _UpdateStage.verifying)
                          ? null
                          : _received / widget.release.size,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.progress(
                        received: (_received / 1048576).toStringAsFixed(1),
                        total: (widget.release.size / 1048576).toStringAsFixed(1),
                      ),
                    ),
                  ],
                  if (_stage == _UpdateStage.permission) ...[
                    const SizedBox(height: 16),
                    Text(strings.permissionRequired),
                  ],
                  if (_stage == _UpdateStage.installer) ...[const SizedBox(height: 16), Text(strings.installerOpened)],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            DialogActionButton(
              onPressed: _installing ? null : _close,
              onBack: _close,
              label: busy ? t.common.cancel : widget.dismissLabel,
              autofocus: busy,
            ),
            if (_stage == _UpdateStage.offered && widget.showSkipVersion)
              DialogActionButton(
                onPressed: () async {
                  await UpdateService.skipVersion(widget.release.versionLabel);
                  if (mounted) _close();
                },
                onBack: _close,
                label: t.update.skipVersion,
              ),
            if (!busy)
              DialogActionButton(
                autofocus: true,
                isPrimary: true,
                onBack: _close,
                onPressed: () => unawaited(switch (_stage) {
                  _UpdateStage.permission => _allowInstallation(),
                  _UpdateStage.installer => _install(),
                  _ => _apk != null ? _install() : _download(),
                }),
                label: switch (_stage) {
                  _UpdateStage.permission => strings.allowInstallation,
                  _UpdateStage.installer => strings.install,
                  _UpdateStage.failed => t.common.retry,
                  _ => strings.downloadAndInstall,
                },
              ),
          ],
        ),
      ),
    );
  }
}
