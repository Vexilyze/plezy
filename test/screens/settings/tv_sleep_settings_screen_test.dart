import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/tv_sleep_settings_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/tv_sleep_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => messenger.setMockMethodCallHandler(TvSleepService.channel, null));

  testWidgets('opt-in is separate from permission and permission refreshes on return from Android settings', (
    tester,
  ) async {
    var enabled = false;
    var openedSettings = 0;
    var sleepRequests = 0;
    messenger.setMockMethodCallHandler(TvSleepService.channel, (call) async {
      switch (call.method) {
        case 'getStatus':
          return {'supported': true, 'enabled': enabled, 'ready': enabled};
        case 'openAccessibilitySettings':
          openedSettings++;
          return true;
        case 'sleep':
          sleepRequests++;
          return 'requested';
      }
      return null;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1080);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: monoTheme(MonoPalette.dark), home: const TvSleepSettingsScreen()));
    await tester.pumpAndSettle();

    expect(SettingsService.instance.read(SettingsService.sleepTimerSleepDevice), isFalse);
    expect(find.text(t.tvSleep.permissionRequired), findsOneWidget);
    await tester.tap(find.text(t.tvSleep.enable));
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(SettingsService.sleepTimerSleepDevice), isTrue);
    expect(sleepRequests, 0);

    await tester.tap(find.text(t.tvSleep.openSettings));
    await tester.pumpAndSettle();
    expect(openedSettings, 1);
    enabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(t.tvSleep.permissionReady), findsOneWidget);
    expect(sleepRequests, 0);
  });

  test('the device sleep opt-in resets locally and is excluded from settings export', () async {
    final settings = SettingsService.instance;
    await settings.write(SettingsService.sleepTimerSleepDevice, true);
    expect(SettingsService.portablePrefs, isNot(contains(SettingsService.sleepTimerSleepDevice)));
    await settings.resetAllSettings();
    expect(settings.read(SettingsService.sleepTimerSleepDevice), isFalse);
  });
}
