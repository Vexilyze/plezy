import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings_service.dart';
import '../../services/tv_sleep_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';

class TvSleepSettingsScreen extends StatefulWidget {
  const TvSleepSettingsScreen({super.key});

  @override
  State<TvSleepSettingsScreen> createState() => _TvSleepSettingsScreenState();
}

class _TvSleepSettingsScreenState extends State<TvSleepSettingsScreen> with WidgetsBindingObserver {
  final _service = const TvSleepService();
  TvSleepStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatus());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    final status = await _service.getStatus();
    if (mounted) setState(() => _status = status);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final permissionLabel = status == null
        ? t.tvSleep.checkingPermission
        : !status.supported
        ? t.tvSleep.unsupported
        : status.enabled && status.ready
        ? t.tvSleep.permissionReady
        : t.tvSleep.permissionRequired;
    return SettingsPage(
      title: Text(t.tvSleep.title),
      children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(t.tvSleep.description)),
        SettingsGroup(
          title: t.tvSleep.title,
          children: [
            SettingSwitchTile(
              pref: SettingsService.sleepTimerSleepDevice,
              icon: Symbols.tv_off_rounded,
              title: t.tvSleep.enable,
              subtitle: t.tvSleep.enableDescription,
              enabled: status?.supported == true,
            ),
            SettingNavigationTile(
              icon: Symbols.accessibility_new_rounded,
              title: t.tvSleep.openSettings,
              subtitle: permissionLabel,
              onTap: () async {
                final opened = await _service.openAccessibilitySettings();
                if (!opened && context.mounted) showErrorSnackBar(context, t.tvSleep.settingsFailed);
              },
            ),
          ],
        ),
        Padding(padding: const EdgeInsets.all(16), child: Text(t.tvSleep.setupHint)),
      ],
    );
  }
}
