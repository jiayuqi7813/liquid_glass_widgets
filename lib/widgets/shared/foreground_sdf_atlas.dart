import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Builds a shader-friendly foreground distance atlas from a rendered vector
/// content boundary.
///
/// The produced image is MSDF-compatible: RGB stores the encoded signed
/// distance value. Today Flutter does not expose glyph/icon outlines through
/// dart:ui, so this generator derives a single-channel SDF from the vector
/// layer's alpha mask. The shader samples it with the same MSDF median path,
/// which keeps the pipeline ready for true multi-channel atlases later.
class ForegroundSdfAtlas {
  const ForegroundSdfAtlas._();

  static const double defaultPxRange = 8.0;

  static Future<ui.Image?> fromBoundary(
    RenderRepaintBoundary boundary, {
    required double pixelRatio,
    double pxRange = defaultPxRange,
  }) async {
    if (!boundary.attached || !boundary.hasSize || boundary.size.isEmpty) {
      return null;
    }

    final source = boundary.toImageSync(pixelRatio: pixelRatio);
    try {
      final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;

      return _buildDistanceImage(
        data.buffer.asUint8List(),
        source.width,
        source.height,
        pxRange: pxRange,
      );
    } finally {
      source.dispose();
    }
  }

  static Future<ForegroundSdfSnapshot?> capture(
    RenderRepaintBoundary boundary, {
    required double pixelRatio,
    double pxRange = defaultPxRange,
  }) async {
    final image = await fromBoundary(
      boundary,
      pixelRatio: pixelRatio,
      pxRange: pxRange,
    );
    if (image == null) return null;

    return ForegroundSdfSnapshot(
      image: image,
      origin: boundary.localToGlobal(ui.Offset.zero) * pixelRatio,
      size: ui.Size(image.width.toDouble(), image.height.toDouble()),
      pxRange: pxRange,
    );
  }

  static Future<ui.Image> _buildDistanceImage(
    Uint8List rgba,
    int width,
    int height, {
    required double pxRange,
  }) async {
    final count = width * height;
    final inside = Uint8List(count);
    var hasInside = false;
    var hasOutside = false;

    for (var i = 0; i < count; i++) {
      final alpha = rgba[i * 4 + 3];
      final isInside = alpha >= 128;
      inside[i] = isInside ? 1 : 0;
      hasInside |= isInside;
      hasOutside |= !isInside;
    }

    final output = Uint8List(count * 4);
    if (!hasInside) {
      for (var i = 3; i < output.length; i += 4) {
        output[i] = 255;
      }
      return _imageFromRgba(output, width, height);
    }

    if (!hasOutside) {
      for (var i = 0; i < count; i++) {
        final o = i * 4;
        output[o] = 255;
        output[o + 1] = 255;
        output[o + 2] = 255;
        output[o + 3] = 255;
      }
      return _imageFromRgba(output, width, height);
    }

    final outsideDistance = _distanceTransform(inside, width, height, true);
    final insideDistance = _distanceTransform(inside, width, height, false);
    final encodeScale = 255.0 / (pxRange * 2.0);

    for (var i = 0; i < count; i++) {
      final signedDistance =
          math.sqrt(outsideDistance[i]) - math.sqrt(insideDistance[i]);
      final encoded =
          (128.0 + signedDistance * encodeScale).round().clamp(0, 255);
      final o = i * 4;
      output[o] = encoded;
      output[o + 1] = encoded;
      output[o + 2] = encoded;
      output[o + 3] = 255;
    }

    return _imageFromRgba(output, width, height);
  }

  static Float64List _distanceTransform(
    Uint8List inside,
    int width,
    int height,
    bool distanceToInside,
  ) {
    const inf = 1.0e20;
    final grid = Float64List(width * height);

    for (var i = 0; i < grid.length; i++) {
      final isInside = inside[i] == 1;
      grid[i] = isInside == distanceToInside ? 0.0 : inf;
    }

    final tmp = Float64List(math.max(width, height));

    for (var x = 0; x < width; x++) {
      for (var y = 0; y < height; y++) {
        tmp[y] = grid[y * width + x];
      }
      _edt1d(tmp, height);
      for (var y = 0; y < height; y++) {
        grid[y * width + x] = tmp[y];
      }
    }

    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        tmp[x] = grid[row + x];
      }
      _edt1d(tmp, width);
      for (var x = 0; x < width; x++) {
        grid[row + x] = tmp[x];
      }
    }

    return grid;
  }

  static void _edt1d(Float64List f, int n) {
    const inf = 1.0e19;
    final v = Int32List(n);
    final z = Float64List(n + 1);
    var k = -1;

    for (var q = 0; q < n; q++) {
      if (f[q] >= inf) continue;

      double s;
      if (k < 0) {
        s = double.negativeInfinity;
      } else {
        do {
          final vk = v[k];
          s = ((f[q] + q * q) - (f[vk] + vk * vk)) / (2.0 * q - 2.0 * vk);
          if (s <= z[k]) {
            k--;
          }
        } while (k >= 0 && s <= z[k]);
      }

      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = double.infinity;
    }

    if (k < 0) {
      for (var q = 0; q < n; q++) {
        f[q] = 1.0e20;
      }
      return;
    }

    k = 0;
    for (var q = 0; q < n; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      final d = q - v[k];
      f[q] = d * d + f[v[k]];
    }
  }

  static Future<ui.Image> _imageFromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );

    try {
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }
}

class ForegroundSdfSnapshot {
  const ForegroundSdfSnapshot({
    required this.image,
    required this.origin,
    required this.size,
    required this.pxRange,
  });

  final ui.Image image;
  final ui.Offset origin;
  final ui.Size size;
  final double pxRange;

  void dispose() {
    image.dispose();
  }
}
