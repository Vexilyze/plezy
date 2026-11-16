/// Finish the playback side of a sleep timer before requesting device sleep.
/// Every asynchronous boundary checks ownership: a new timer, playback action,
/// episode, or route must invalidate a completion that is still saving progress.
Future<void> completeSleepTimerPlayback({
  required bool Function() isCurrent,
  required Future<void> Function() pause,
  required Future<void> Function() releaseWakelock,
  required Future<void> Function() finalizeProgress,
  required bool Function() shouldSleep,
  required Future<void> Function() sleep,
}) async {
  if (!isCurrent()) return;
  await pause();
  if (!isCurrent()) return;
  await releaseWakelock();
  if (!isCurrent()) return;
  await finalizeProgress();
  if (!isCurrent() || !shouldSleep()) return;
  await sleep();
}
