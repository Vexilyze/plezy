import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';

class TvSleepStatus {
  const TvSleepStatus({this.supported = false, this.enabled = false, this.ready = false});

  final bool supported;
  final bool enabled;
  final bool ready;
}

enum TvSleepResult { requested, permissionRequired, unsupported, failed }

/// Android screen lock, authorized by the user's accessibility-service toggle.
/// It sleeps the Android device; television standby depends on HDMI-CEC.
class TvSleepService {
  const TvSleepService();

  static const channel = MethodChannel('com.vexilyze/tv_sleep');

  static bool get isAndroidTv => Platform.isAndroid && PlatformDetector.isTVDevice();

  Future<TvSleepStatus> getStatus() async {
    try {
      final status = await channel.invokeMapMethod<String, dynamic>('getStatus');
      return TvSleepStatus(
        supported: status?['supported'] == true,
        enabled: status?['enabled'] == true,
        ready: status?['ready'] == true,
      );
    } on MissingPluginException {
      return const TvSleepStatus();
    } on PlatformException catch (error) {
      appLogger.w('Could not read TV sleep permission', error: error);
      return const TvSleepStatus();
    }
  }

  Future<bool> openAccessibilitySettings() async {
    try {
      return await channel.invokeMethod<bool>('openAccessibilitySettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      appLogger.w('Could not open accessibility settings', error: error);
      return false;
    }
  }

  Future<TvSleepResult> sleep() async {
    try {
      return switch (await channel.invokeMethod<String>('sleep')) {
        'requested' => TvSleepResult.requested,
        'permissionRequired' => TvSleepResult.permissionRequired,
        'unsupported' => TvSleepResult.unsupported,
        _ => TvSleepResult.failed,
      };
    } on MissingPluginException {
      return TvSleepResult.unsupported;
    } on PlatformException catch (error) {
      appLogger.w('TV sleep request failed', error: error);
      return TvSleepResult.failed;
    }
  }
}
