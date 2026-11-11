import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs the background search for missing covers, one sweep at a time, and
/// says when its results are worth showing and publishing.
///
/// The sweep itself lives in the Rust core: it lists the books that have an
/// ISBN and no cover, asks the external sources about each one, and stores a
/// cover the moment it finds it. Two properties of it shape this class:
///
/// - It takes its list of books when it starts. Books imported while it runs
///   are not on that list, so a request made during a sweep must lead to
///   another sweep afterwards rather than be dropped.
/// - It is slow on purpose (the sources throttle), about one book every few
///   seconds, and only reports a total at the very end. A large import keeps
///   it busy for hours, so the covers found along the way are published at
///   [publishInterval] instead of waiting for that total.
///
/// Sweeps never overlap: two at once would ask the sources about the same
/// books twice and spend their per-address budgets for nothing.
///
/// All side effects are injected so tests can drive it without FFI.
class CoverEnrichmentCoordinator {
  /// How often a running sweep publishes what it has found so far.
  ///
  /// Each publication that carries new covers re-sends the whole catalog
  /// (about 1 MB for 3600 books), mobile data included, so this is a trade:
  /// short enough that covers show up within minutes, long enough that a
  /// three-hour sweep costs at most 18 uploads. A tick with nothing new
  /// uploads nothing, the catalog hash short-circuits it (ADR-027); a library
  /// that is not public still pays one small request per tick, to read its
  /// followers before deciding how to push.
  static const Duration defaultPublishInterval = Duration(minutes: 10);

  final Future<int> Function() _enrich;
  final VoidCallback _onCoversFound;
  final VoidCallback _onPublishTick;
  final Duration _publishInterval;

  Future<void>? _running;
  bool _rerunQueued = false;

  /// [enrich] runs one sweep and returns the number of covers it stored.
  /// [onCoversFound] is called once after a sweep that stored at least one.
  /// [onPublishTick] is called at every [publishInterval] while a sweep runs;
  /// it cannot know whether anything was found yet, so it must be cheap when
  /// nothing changed.
  CoverEnrichmentCoordinator({
    required Future<int> Function() enrich,
    required VoidCallback onCoversFound,
    required VoidCallback onPublishTick,
    Duration publishInterval = defaultPublishInterval,
  }) : _enrich = enrich,
       _onCoversFound = onCoversFound,
       _onPublishTick = onPublishTick,
       _publishInterval = publishInterval;

  /// True while a sweep, or the rerun queued behind it, is in progress.
  bool get isRunning => _running != null;

  /// Ask for a sweep. Starts one when none is running; otherwise queues a
  /// single rerun, shared by every request made in the meantime. The returned
  /// future completes when no sweep is left to run, and never fails.
  Future<void> run() {
    final running = _running;
    if (running != null) {
      _rerunQueued = true;
      return running;
    }
    return _running = _drain();
  }

  Future<void> _drain() async {
    try {
      do {
        _rerunQueued = false;
        await _sweepOnce();
      } while (_rerunQueued);
    } finally {
      _running = null;
    }
  }

  Future<void> _sweepOnce() async {
    final ticker = Timer.periodic(_publishInterval, (_) => _onPublishTick());
    try {
      final count = await _enrich();
      if (count > 0) {
        debugPrint('Enriched $count book covers');
        _onCoversFound();
      }
    } catch (e) {
      // Covers stored before the failure stay stored; the next sweep picks up
      // where this one stopped.
      debugPrint('Cover enrichment sweep failed: $e');
    } finally {
      ticker.cancel();
    }
  }
}
