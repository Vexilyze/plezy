import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/tv_sleep_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const service = TvSleepService();

  tearDown(() => messenger.setMockMethodCallHandler(TvSleepService.channel, null));

  test('permission is queried afresh and a revoked service declines sleep', () async {
    var enabled = true;
    messenger.setMockMethodCallHandler(TvSleepService.channel, (call) async {
      return switch (call.method) {
        'getStatus' => {'supported': true, 'enabled': enabled, 'ready': enabled},
        'sleep' => enabled ? 'requested' : 'permissionRequired',
        _ => null,
      };
    });
    expect((await service.getStatus()).ready, isTrue);
    expect(await service.sleep(), TvSleepResult.requested);
    enabled = false;
    expect((await service.getStatus()).enabled, isFalse);
    expect(await service.sleep(), TvSleepResult.permissionRequired);
  });

  test('unsupported hosts do not report a successful sleep', () async {
    expect((await service.getStatus()).supported, isFalse);
    expect(await service.sleep(), TvSleepResult.unsupported);
    expect(await service.openAccessibilitySettings(), isFalse);
  });

  test('native errors and rejected screen lock remain visible failures', () async {
    messenger.setMockMethodCallHandler(TvSleepService.channel, (_) async => 'failed');
    expect(await service.sleep(), TvSleepResult.failed);
    messenger.setMockMethodCallHandler(TvSleepService.channel, (_) async {
      throw PlatformException(code: 'TV_SLEEP_FAILED');
    });
    expect(await service.sleep(), TvSleepResult.failed);
  });
}
