import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class DocumentImagePreprocessor {
  const DocumentImagePreprocessor();

  static const int _maxPageDimension = 1600;
  static const int _jpegQuality = 82;

  Future<Uint8List?> preprocessSinglePage(Uint8List bytes) {
    return compute(_preprocessSinglePageIsolate, bytes);
  }

  Future<List<Uint8List>> preprocessPages(List<Uint8List> pages) {
    return compute(_preprocessPagesIsolate, pages);
  }

  Future<Uint8List?> mergePages(List<Uint8List> pages) {
    return compute(_mergePagesIsolate, pages);
  }
}

List<Uint8List> _preprocessPagesIsolate(List<Uint8List> pages) {
  return pages
      .map(_preprocessSinglePageIsolate)
      .whereType<Uint8List>()
      .toList(growable: false);
}

Uint8List? _mergePagesIsolate(List<Uint8List> pages) {
  final decodedPages = pages
      .map(img.decodeImage)
      .whereType<img.Image>()
      .toList(growable: false);

  if (decodedPages.isEmpty) return null;
  if (decodedPages.length == 1) {
    return Uint8List.fromList(img.encodeJpg(decodedPages.first, quality: 88));
  }

  final maxWidth = decodedPages
      .map((page) => page.width)
      .reduce((a, b) => a > b ? a : b);
  final separatorHeight = (maxWidth * 0.025).round().clamp(24, 80);
  final totalHeight = decodedPages.fold<int>(
        0,
        (sum, page) => sum + page.height,
      ) +
      separatorHeight * (decodedPages.length - 1);

  final merged = img.Image(width: maxWidth, height: totalHeight);
  img.fill(merged, color: img.ColorRgb8(248, 248, 248));

  var offsetY = 0;
  for (var index = 0; index < decodedPages.length; index++) {
    final page = decodedPages[index];
    img.compositeImage(merged, page, dstX: 0, dstY: offsetY);
    offsetY += page.height;

    if (index < decodedPages.length - 1) {
      final separator = img.Image(width: maxWidth, height: separatorHeight);
      img.fill(separator, color: img.ColorRgb8(236, 236, 236));
      img.compositeImage(merged, separator, dstX: 0, dstY: offsetY);
      offsetY += separatorHeight;
    }
  }

  return Uint8List.fromList(img.encodeJpg(merged, quality: 88));
}

Uint8List? _preprocessSinglePageIsolate(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    var working = decoded;

    if (working.width > working.height * 1.18) {
      working = img.copyRotate(working, angle: 90);
    }

    final marginX = (working.width * 0.02).round();
    final marginY = (working.height * 0.02).round();
    final cropWidth = (working.width - (marginX * 2)).clamp(1, working.width);
    final cropHeight = (working.height - (marginY * 2)).clamp(1, working.height);
    working = img.copyCrop(
      working,
      x: marginX.clamp(0, working.width - 1),
      y: marginY.clamp(0, working.height - 1),
      width: cropWidth,
      height: cropHeight,
    );

    if (working.width > DocumentImagePreprocessor._maxPageDimension ||
        working.height > DocumentImagePreprocessor._maxPageDimension) {
      working = working.width >= working.height
          ? img.copyResize(
              working,
              width: DocumentImagePreprocessor._maxPageDimension,
            )
          : img.copyResize(
              working,
              height: DocumentImagePreprocessor._maxPageDimension,
            );
    }

    return Uint8List.fromList(
      img.encodeJpg(
        working,
        quality: DocumentImagePreprocessor._jpegQuality,
      ),
    );
  } catch (_) {
    return null;
  }
}
