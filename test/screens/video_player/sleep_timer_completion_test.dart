import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/video_player/sleep_timer_completion.dart';

void main() {
  test('sleep waits for pause, wakelock release, and the final progress write', () async {
    final writes = Completer<void>();
    final events = <String>[];
    final completion = completeSleepTimerPlayback(
      isCurrent: () => true,
      pause: () async => events.add('pause'),
      releaseWakelock: () async => events.add('release'),
      finalizeProgress: () {
        events.add('save');
        return writes.future;
      },
      shouldSleep: () => true,
      sleep: () async => events.add('sleep'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, ['pause', 'release', 'save']);
    writes.complete();
    await completion;
    expect(events, ['pause', 'release', 'save', 'sleep']);
  });

  test('a canceled or superseded timer cannot sleep after its pending save finishes', () async {
    final writes = Completer<void>();
    var current = true;
    var sleepRequests = 0;
    final completion = completeSleepTimerPlayback(
      isCurrent: () => current,
      pause: () async {},
      releaseWakelock: () async {},
      finalizeProgress: () => writes.future,
      shouldSleep: () => true,
      sleep: () async => sleepRequests++,
    );
    await Future<void>.delayed(Duration.zero);
    current = false;
    writes.complete();
    await completion;
    expect(sleepRequests, 0);
  });

  test('the default pause-only option saves progress without sleeping the device', () async {
    final events = <String>[];
    await completeSleepTimerPlayback(
      isCurrent: () => true,
      pause: () async => events.add('pause'),
      releaseWakelock: () async => events.add('release'),
      finalizeProgress: () async => events.add('save'),
      shouldSleep: () => false,
      sleep: () async => events.add('sleep'),
    );
    expect(events, ['pause', 'release', 'save']);
  });

  test('a failed final progress write never powers down first', () async {
    var sleepRequests = 0;
    await expectLater(
      completeSleepTimerPlayback(
        isCurrent: () => true,
        pause: () async {},
        releaseWakelock: () async {},
        finalizeProgress: () async => throw StateError('disk write failed'),
        shouldSleep: () => true,
        sleep: () async => sleepRequests++,
      ),
      throwsStateError,
    );
    expect(sleepRequests, 0);
  });
}
