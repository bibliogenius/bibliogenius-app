/// Calls [loadNext] until [hasMore] turns false or a call makes no progress.
///
/// [loadNext] returns whether it actually loaded a page. It must return
/// `false` when it did nothing (another load already in flight) or failed.
/// Stopping on `false` is what keeps this loop safe: awaiting a future that
/// is already complete resumes in a microtask, so looping on a loader that
/// returns at once would never yield to the event loop and would freeze the
/// UI. It also means a failing page is not retried in a tight loop.
Future<void> loadPagesUntilDone({
  required bool Function() hasMore,
  required Future<bool> Function() loadNext,
}) async {
  while (hasMore()) {
    if (!await loadNext()) return;
  }
}
