import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Captures a complete foreground layer as a high-resolution RGBA atlas.
///
/// This deliberately preserves the layer's real color, opacity, antialiasing,
/// icon detail, and text rasterization. It is not an MSDF generator; the premium
/// shader refracts this RGBA atlas directly so tab foreground participates in
/// the same optical field without collapsing to a single reconstructed color.
class ForegroundColorAtlas {
  const ForegroundColorAtlas._();

  static const double defaultSupersample = 3.0;

  static Future<ForegroundColorSnapshot?> capture(
    RenderRepaintBoundary boundary, {
    required double devicePixelRatio,
    double supersample = defaultSupersample,
  }) async {
    if (!boundary.attached || !boundary.hasSize || boundary.size.isEmpty) {
      return null;
    }

    final captureScale = devicePixelRatio * supersample;
    final image = boundary.toImageSync(pixelRatio: captureScale);
    return ForegroundColorSnapshot(
      image: image,
      screenOriginPx: boundary.localToGlobal(ui.Offset.zero) * devicePixelRatio,
      screenSizePx: boundary.size * devicePixelRatio,
      atlasSizePx: ui.Size(image.width.toDouble(), image.height.toDouble()),
      supersample: supersample,
    );
  }
}

class ForegroundColorSnapshot {
  const ForegroundColorSnapshot({
    required this.image,
    required this.screenOriginPx,
    required this.screenSizePx,
    required this.atlasSizePx,
    required this.supersample,
  });

  final ui.Image image;
  final ui.Offset screenOriginPx;
  final ui.Size screenSizePx;
  final ui.Size atlasSizePx;
  final double supersample;

  void dispose() {
    image.dispose();
  }
}
