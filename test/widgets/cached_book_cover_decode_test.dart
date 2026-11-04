import 'dart:async';

import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers are decoded at the size they are drawn, in PHYSICAL pixels: a
/// decode at the logical width blurs every cover on a high-density screen.
Future<void> _pump(WidgetTester tester, Widget cover) async {
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: cover)),
    ),
  );
}

void main() {
  testWidgets('a local cover with a width is decoded at width x pixel ratio', (
    tester,
  ) async {
    await _pump(
      tester,
      const CachedBookCover(
        imageUrl: '/covers/a.jpg',
        width: 26,
        height: 36,
        semanticLabel: null,
      ),
    );

    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    expect((image as ResizeImage).width, 78);
  });

  testWidgets('a cover rewritten at its path loses every decoded size, and '
      'only that cover', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          CachedBookCover(
            imageUrl: '/covers/a.jpg',
            width: 26,
            semanticLabel: null,
          ),
          CachedBookCover(
            imageUrl: '/covers/a.jpg',
            width: 40,
            semanticLabel: null,
          ),
          CachedBookCover(imageUrl: '/covers/a.jpg', semanticLabel: null),
          CachedBookCover(
            imageUrl: '/covers/b.jpg',
            width: 26,
            semanticLabel: null,
          ),
        ],
      ),
    );
    // The keys the image cache really uses, held as decodes in flight.
    final keys = <Object>[
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        await image.image.obtainKey(ImageConfiguration.empty),
    ];
    for (final key in keys) {
      imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
      );
    }
    expect(keys.toSet(), hasLength(4));
    expect(
      keys.map((k) => imageCache.statusForKey(k).tracked),
      everyElement(true),
    );

    CachedBookCover.evictLocalCover('/covers/a.jpg');
    await tester.pump();

    expect(
      keys.map((k) => imageCache.statusForKey(k).tracked).toList(),
      [false, false, false, true],
    );
  });

  testWidgets('a local cover without a width keeps its full decode', (
    tester,
  ) async {
    await _pump(
      tester,
      const CachedBookCover(imageUrl: '/covers/a.jpg', semanticLabel: null),
    );

    expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());
  });

  testWidgets('a remote cover is decoded at width x pixel ratio too', (
    tester,
  ) async {
    await _pump(
      tester,
      const CachedBookCover(
        imageUrl: 'https://c/a.jpg',
        width: 26,
        height: 36,
        semanticLabel: null,
      ),
    );

    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .memCacheWidth,
      78,
    );
  });
}
