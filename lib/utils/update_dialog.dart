import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.g.dart';
import '../services/update_service.dart';
import '../services/android_update_release.dart';
import '../widgets/dialog_action_button.dart';
import 'android_update_dialog.dart';
import 'dialogs.dart';

bool _updateDialogOpen = false;

Future<void> showUpdateAvailableDialog(
  BuildContext context,
  Map<String, dynamic> updateInfo, {
  required String title,
  required String dismissLabel,
  bool showSkipVersion = false,
}) async {
  if (_updateDialogOpen) return;
  _updateDialogOpen = true;
  try {
    await showScopedDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final androidRelease = updateInfo['androidRelease'];
        if (androidRelease is AndroidUpdateRelease) {
          return AndroidUpdateDialog(
            release: androidRelease,
            currentVersion: updateInfo['currentVersion'] as String,
            title: title,
            dismissLabel: dismissLabel,
            showSkipVersion: showSkipVersion,
          );
        }
        final latestVersion = updateInfo['latestVersion'] as String;
        final releaseUrl = updateInfo['releaseUrl'] as String;

        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              Text(
                t.update.versionAvailable(version: latestVersion),
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t.update.currentVersion(version: updateInfo['currentVersion']),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            DialogActionButton(onPressed: () => Navigator.pop(dialogContext), label: dismissLabel),
            if (showSkipVersion)
              DialogActionButton(
                onPressed: () async {
                  await UpdateService.skipVersion(latestVersion);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                label: t.update.skipVersion,
              ),
            DialogActionButton(
              onPressed: () async {
                final url = Uri.parse(releaseUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              label: t.update.viewRelease,
              isPrimary: true,
            ),
          ],
        );
      },
    );
  } finally {
    _updateDialogOpen = false;
  }
}
