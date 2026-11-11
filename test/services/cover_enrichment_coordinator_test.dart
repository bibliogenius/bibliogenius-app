import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/services/cover_enrichment_coordinator.dart';

void main() {
  test('a sweep that finds covers reports them once', () async {
    var found = 0;
    var ticks = 0;
    final coordinator = CoverEnrichmentCoordinator(
      enrich: () async => 3,
      onCoversFound: () => found++,
      onPublishTick: () => ticks++,
    );

    await coordinator.run();

    expect(found, 1);
    expect(ticks, 0, reason: 'a short sweep never reaches a publish tick');
    expect(coordinator.isRunning, isFalse);
  });

  test('a sweep that finds nothing reports nothing', () async {
    var found = 0;
    var ticks = 0;
    final coordinator = CoverEnrichmentCoordinator(
      enrich: () async => 0,
      onCoversFound: () => found++,
      onPublishTick: () => ticks++,
    );

    await coordinator.run();

    expect(found, 0);
    expect(ticks, 0);
  });

  test('requests made during a sweep never overlap it and queue one rerun',
      () async {
    final sweeps = <Completer<int>>[];
    var concurrent = 0;
    var maxConcurrent = 0;
    var found = 0;
    final coordinator = CoverEnrichmentCoordinator(
      enrich: () async {
        concurrent++;
        if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        final sweep = Completer<int>();
        sweeps.add(sweep);
        final count = await sweep.future;
        concurrent--;
        return count;
      },
      onCoversFound: () => found++,
      onPublishTick: () {},
    );

    final first = coordinator.run();
    // The startup sweep took its list of books before these requests: each
    // one asks for a sweep that sees the books imported since.
    final second = coordinator.run();
    final third = coordinator.run();
    await Future<void>.delayed(Duration.zero);
    expect(sweeps, hasLength(1), reason: 'nothing starts while one runs');

    sweeps[0].complete(0);
    await Future<void>.delayed(Duration.zero);
    expect(sweeps, hasLength(2), reason: 'the queued rerun starts afterwards');
    expect(coordinator.isRunning, isTrue);

    sweeps[1].complete(2);
    await Future.wait([first, second, third]);

    expect(sweeps, hasLength(2), reason: 'two requests share a single rerun');
    expect(maxConcurrent, 1);
    expect(found, 1, reason: 'only the rerun found covers');
    expect(coordinator.isRunning, isFalse);
  });

  test('a failed sweep reports nothing and does not block the next one',
      () async {
    var calls = 0;
    var found = 0;
    final coordinator = CoverEnrichmentCoordinator(
      enrich: () async {
        calls++;
        if (calls == 1) throw StateError('backend unavailable');
        return 1;
      },
      onCoversFound: () => found++,
      onPublishTick: () {},
    );

    await coordinator.run();
    expect(found, 0);
    expect(coordinator.isRunning, isFalse);

    await coordinator.run();
    expect(calls, 2);
    expect(found, 1);
  });

  // testWidgets runs under a fake clock, so the periodic timer can be driven
  // without waiting.
  testWidgets('a long sweep publishes at each interval, then stops', (
    tester,
  ) async {
    final sweep = Completer<int>();
    var found = 0;
    var ticks = 0;
    final coordinator = CoverEnrichmentCoordinator(
      enrich: () => sweep.future,
      onCoversFound: () => found++,
      onPublishTick: () => ticks++,
      publishInterval: const Duration(minutes: 10),
    );

    final run = coordinator.run();
    await tester.pump(const Duration(minutes: 9));
    expect(ticks, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(ticks, 1);
    await tester.pump(const Duration(minutes: 20));
    expect(ticks, 3);

    sweep.complete(5);
    await tester.pump();
    await run;
    expect(found, 1);

    await tester.pump(const Duration(minutes: 30));
    expect(ticks, 3, reason: 'no tick once the sweep is over');
  });
}
