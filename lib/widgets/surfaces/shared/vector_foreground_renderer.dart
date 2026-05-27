// ignore_for_file: deprecated_member_use
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Compact tab foreground data for the post-glass vector renderer.
class VectorForegroundItem {
  const VectorForegroundItem({
    this.label,
    this.icon,
    this.activeIcon,
  });

  final String? label;
  final Widget? icon;
  final Widget? activeIcon;
}

/// Paints bottom-bar foreground after the glass shader.
///
/// Standard [Icon] widgets and text labels are re-rasterized by Flutter at the
/// final screen position instead of being sampled from a texture. Flutter does
/// not expose glyph outlines, so the painter warps each glyph run by lens field
/// rather than flattening true glyph paths. The important bit for quality is
/// that every glyph is still drawn from font/vector data at final resolution.
class BottomBarVectorForegroundLayer extends StatelessWidget {
  const BottomBarVectorForegroundLayer({
    required this.items,
    required this.selectedIndex,
    required this.selectedIconColor,
    required this.unselectedIconColor,
    required this.iconSize,
    required this.labelFontSize,
    required this.iconLabelSpacing,
    required this.tabPadding,
    required this.itemCount,
    required this.alignment,
    required this.thickness,
    required this.expansion,
    required this.transform,
    required this.borderRadius,
    this.debugLayout = false,
    this.textStyle,
    super.key,
  });

  final List<VectorForegroundItem> items;
  final int selectedIndex;
  final Color selectedIconColor;
  final Color unselectedIconColor;
  final double iconSize;
  final double labelFontSize;
  final double iconLabelSpacing;
  final EdgeInsetsGeometry tabPadding;
  final int itemCount;
  final Alignment alignment;
  final double thickness;
  final double expansion;
  final Matrix4 transform;
  final double borderRadius;
  final bool debugLayout;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (thickness <= 0.05) return const SizedBox.expand();

    return IgnorePointer(
      child: ClipPath(
        clipper: _BottomBarLensClipper(
          itemCount: itemCount,
          alignment: alignment,
          thickness: thickness,
          expansion: expansion,
          transform: transform,
          borderRadius: borderRadius,
        ),
        child: CustomPaint(
          painter: _VectorForegroundPainter(
            items: items,
            selectedIndex: selectedIndex,
            selectedIconColor: selectedIconColor,
            unselectedIconColor: unselectedIconColor,
            iconSize: iconSize,
            iconLabelSpacing: iconLabelSpacing,
            padding: tabPadding.resolve(Directionality.of(context)),
            textDirection: Directionality.of(context),
            lens: _LensField.bottomBar(
              itemCount: itemCount,
              alignment: alignment,
              thickness: thickness,
              expansion: expansion,
              borderRadius: borderRadius,
            ),
            debugLayout: debugLayout,
            itemRectResolver: (size, index) {
              final contentRect =
                  tabPadding.resolve(Directionality.of(context)).deflateRect(
                        Offset.zero & size,
                      );
              if (contentRect.isEmpty || itemCount <= 0) return Rect.zero;
              final tabWidth = contentRect.width / itemCount;
              return Rect.fromLTWH(
                contentRect.left + index * tabWidth,
                contentRect.top,
                tabWidth,
                contentRect.height,
              );
            },
            selectedLabelStyle: textStyle ??
                TextStyle(
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w600,
                ),
            unselectedLabelStyle: textStyle ??
                TextStyle(
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w500,
                ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Paints fixed or scrollable [GlassTabBar] foreground after the glass shader.
class TabBarVectorForegroundLayer extends StatelessWidget {
  const TabBarVectorForegroundLayer({
    required this.items,
    required this.selectedIndex,
    required this.selectedLabelStyle,
    required this.unselectedLabelStyle,
    required this.selectedIconColor,
    required this.unselectedIconColor,
    required this.iconSize,
    required this.padding,
    required this.itemCount,
    required this.alignment,
    required this.thickness,
    required this.expansion,
    required this.borderRadius,
    this.indicatorLeft,
    this.indicatorWidth,
    this.scrollOffset = 0.0,
    this.itemOffsets,
    this.itemWidths,
    this.debugLayout = false,
    super.key,
  });

  final List<VectorForegroundItem> items;
  final int selectedIndex;
  final TextStyle selectedLabelStyle;
  final TextStyle unselectedLabelStyle;
  final Color selectedIconColor;
  final Color unselectedIconColor;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final int itemCount;
  final Alignment alignment;
  final double thickness;
  final double expansion;
  final double borderRadius;
  final double? indicatorLeft;
  final double? indicatorWidth;
  final double scrollOffset;
  final List<double>? itemOffsets;
  final List<double>? itemWidths;
  final bool debugLayout;

  @override
  Widget build(BuildContext context) {
    if (thickness <= 0.05) return const SizedBox.expand();

    final direction = Directionality.of(context);
    return IgnorePointer(
      child: ClipPath(
        clipper: _TabBarLensClipper(
          itemCount: itemCount,
          alignment: alignment,
          indicatorLeft: indicatorLeft,
          indicatorWidth: indicatorWidth,
          borderRadius: borderRadius,
          expansion: expansion,
          thickness: thickness,
        ),
        child: CustomPaint(
          painter: _VectorForegroundPainter(
            items: items,
            selectedIndex: selectedIndex,
            selectedIconColor: selectedIconColor,
            unselectedIconColor: unselectedIconColor,
            iconSize: iconSize,
            iconLabelSpacing: 4.0,
            padding: padding.resolve(direction),
            textDirection: direction,
            selectedLabelStyle: selectedLabelStyle,
            unselectedLabelStyle: unselectedLabelStyle,
            lens: _LensField.tabBar(
              itemCount: itemCount,
              alignment: alignment,
              thickness: thickness,
              expansion: expansion,
              borderRadius: borderRadius,
              indicatorLeft: indicatorLeft,
              indicatorWidth: indicatorWidth,
            ),
            debugLayout: debugLayout,
            itemRectResolver: (size, index) {
              final resolvedPadding = padding.resolve(direction);
              final contentRect = resolvedPadding.deflateRect(
                Offset.zero & size,
              );
              if (contentRect.isEmpty || itemCount <= 0) return Rect.zero;

              final offsets = itemOffsets;
              final widths = itemWidths;
              if (offsets != null &&
                  widths != null &&
                  index < offsets.length &&
                  index < widths.length) {
                return Rect.fromLTWH(
                  offsets[index] - scrollOffset,
                  contentRect.top,
                  widths[index],
                  contentRect.height,
                );
              }

              final tabWidth = contentRect.width / itemCount;
              return Rect.fromLTWH(
                contentRect.left + index * tabWidth,
                contentRect.top,
                tabWidth,
                contentRect.height,
              );
            },
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

typedef _ItemRectResolver = Rect Function(Size size, int index);

class _VectorForegroundPainter extends CustomPainter {
  const _VectorForegroundPainter({
    required this.items,
    required this.selectedIndex,
    required this.selectedIconColor,
    required this.unselectedIconColor,
    required this.iconSize,
    required this.iconLabelSpacing,
    required this.padding,
    required this.textDirection,
    required this.selectedLabelStyle,
    required this.unselectedLabelStyle,
    required this.lens,
    required this.itemRectResolver,
    required this.debugLayout,
  });

  final List<VectorForegroundItem> items;
  final int selectedIndex;
  final Color selectedIconColor;
  final Color unselectedIconColor;
  final double iconSize;
  final double iconLabelSpacing;
  final EdgeInsets padding;
  final TextDirection textDirection;
  final TextStyle selectedLabelStyle;
  final TextStyle unselectedLabelStyle;
  final _LensField lens;
  final _ItemRectResolver itemRectResolver;
  final bool debugLayout;

  static String? _lastDebugLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || size.isEmpty) return;

    for (var index = 0; index < items.length; index++) {
      final rect = itemRectResolver(size, index);
      if (rect.isEmpty || !rect.overlaps(Offset.zero & size)) continue;

      final item = items[index];
      final selected = index == selectedIndex;
      final color = selected ? selectedIconColor : unselectedIconColor;
      _paintItem(canvas, size, rect, item, index, selected, color);
    }
  }

  void _paintItem(
    Canvas canvas,
    Size size,
    Rect rect,
    VectorForegroundItem item,
    int index,
    bool selected,
    Color color,
  ) {
    final iconWidget = selected ? (item.activeIcon ?? item.icon) : item.icon;
    final iconData = _iconDataFor(iconWidget);
    final label = item.label;

    final labelRuns = label == null
        ? const <_GlyphRun>[]
        : _layoutGlyphRuns(
            label,
            _labelStyle(color, selected),
            maxWidth: rect.width,
          );

    final hasIcon = iconData != null;
    final hasLabel = labelRuns.isNotEmpty;
    if (!hasIcon && !hasLabel) return;

    final labelHeight = hasLabel
        ? labelRuns.map((run) => run.size.height).reduce(math.max)
        : 0.0;
    final gap = hasIcon && hasLabel ? iconLabelSpacing : 0.0;
    final contentHeight = (hasIcon ? iconSize : 0.0) + gap + labelHeight;
    var y = rect.center.dy - contentHeight / 2;
    _PaintRunMetrics? iconMetrics;
    _PaintRunMetrics? labelMetrics;

    if (hasIcon) {
      final iconText = String.fromCharCode(iconData.codePoint);
      final iconStyle = TextStyle(
        inherit: false,
        color: color,
        fontSize: iconSize,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
      );
      final iconPainter = TextPainter(
        text: TextSpan(text: iconText, style: iconStyle),
        textDirection: textDirection,
        maxLines: 1,
        strutStyle: StrutStyle(
          fontSize: iconSize,
          height: 1.0,
          forceStrutHeight: true,
        ),
      )..layout();
      final iconRun = _GlyphRun(
        text: iconText,
        style: iconStyle,
        strutStyle: StrutStyle(
          fontSize: iconSize,
          height: 1.0,
          forceStrutHeight: true,
        ),
        size: Size.square(iconSize),
        paintOffset: Offset(
          (iconSize - iconPainter.width) / 2,
          (iconSize - iconPainter.height) / 2,
        ),
        localDx: 0,
      );
      iconMetrics = _paintGlyphRun(
        canvas,
        size,
        iconRun,
        Offset(rect.center.dx - iconSize / 2, y),
        rect.center,
        color,
      );
      y += iconSize + gap;
    }

    if (hasLabel) {
      final totalWidth =
          labelRuns.fold<double>(0.0, (sum, run) => sum + run.size.width);
      var x = rect.center.dx - totalWidth / 2;
      for (final run in labelRuns) {
        labelMetrics =
            _paintGlyphRun(canvas, size, run, Offset(x, y), rect.center, color);
        x += run.size.width;
      }
    }

    if (debugLayout && selected) {
      _debugLogLayout(
        size: size,
        index: index,
        label: label,
        rect: rect,
        groupCenter: rect.center,
        contentHeight: contentHeight,
        iconMetrics: iconMetrics,
        labelMetrics: labelMetrics,
      );
    }
  }

  List<_GlyphRun> _layoutGlyphRuns(
    String text,
    TextStyle style, {
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: maxWidth);

    if (painter.width <= 0.0 || painter.height <= 0.0) {
      return const <_GlyphRun>[];
    }

    return [
      _GlyphRun(
        text: text,
        style: style,
        strutStyle: null,
        size: Size(painter.width, painter.height),
        paintOffset: Offset.zero,
        localDx: 0,
      ),
    ];
  }

  _PaintRunMetrics _paintGlyphRun(
    Canvas canvas,
    Size size,
    _GlyphRun run,
    Offset topLeft,
    Offset groupCenter,
    Color color,
  ) {
    final center = topLeft + Offset(run.size.width / 2, run.size.height / 2);
    final edge = lens.edgeAmount(center, size);
    final groupCoverage = lens.coverageAmount(groupCenter, size);
    final groupScale = 1.0 + groupCoverage * lens.effectAmount * 0.05;
    // Keep the foreground anchored to the tab layout. The glass owns the
    // background refraction; foreground gets only local magnification/CA so
    // icons and labels do not jump when the lens edge crosses their centers.
    const groupDelta = Offset.zero;
    final warped = center + groupDelta;
    final scaledSize = run.size * groupScale;
    final offset = Offset(
      warped.dx - scaledSize.width / 2,
      warped.dy - scaledSize.height / 2,
    );

    final fringeEdge = edge * lens.effectAmount;
    if (fringeEdge > 0.01) {
      final normal = lens.normalAt(center, size);
      final fringePx = math.min(0.65, 0.18 + fringeEdge * 0.42);
      _paintText(
        canvas,
        run,
        offset + normal * fringePx,
        Color.fromRGBO(255, 42, 34, 0.11 * fringeEdge),
        scale: groupScale,
      );
      _paintText(
        canvas,
        run,
        offset - normal * fringePx,
        Color.fromRGBO(32, 116, 255, 0.11 * fringeEdge),
        scale: groupScale,
      );
    }

    _paintText(canvas, run, offset, color, scale: groupScale);

    return _PaintRunMetrics(
      sourceCenter: center,
      warpedCenter: warped,
      paintOffset: offset,
      scale: groupScale,
      edge: edge,
      groupCoverage: groupCoverage,
      groupDelta: groupDelta,
    );
  }

  void _debugLogLayout({
    required Size size,
    required int index,
    required String? label,
    required Rect rect,
    required Offset groupCenter,
    required double contentHeight,
    required _PaintRunMetrics? iconMetrics,
    required _PaintRunMetrics? labelMetrics,
  }) {
    final line = [
      '[GlassVectorForeground]',
      'tab=$index',
      if (label != null) 'label="$label"',
      'size=${_fmtSize(size)}',
      'rect=${_fmtRect(rect)}',
      'lens=${_fmtRect(lens.rectFor(size))}',
      'thickness=${_fmt(lens.thickness)}',
      'effect=${_fmt(lens.effectAmount)}',
      'contentH=${_fmt(contentHeight)}',
      'group=${_fmtOffset(groupCenter)}',
      if (iconMetrics != null) 'icon=${iconMetrics.debugString}',
      if (labelMetrics != null) 'text=${labelMetrics.debugString}',
    ].join(' ');

    if (line == _lastDebugLine) return;
    _lastDebugLine = line;
    debugPrint(line);
  }

  void _paintText(
    Canvas canvas,
    _GlyphRun run,
    Offset offset,
    Color color, {
    double scale = 1.0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: run.text,
        style: run.style.copyWith(color: color),
      ),
      textDirection: textDirection,
      maxLines: 1,
      strutStyle: run.strutStyle,
    )..layout();
    if ((scale - 1.0).abs() < 1e-4) {
      painter.paint(canvas, offset + run.paintOffset);
      return;
    }

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    painter.paint(canvas, run.paintOffset);
    canvas.restore();
  }

  TextStyle _labelStyle(Color color, bool selected) {
    final base = selected ? selectedLabelStyle : unselectedLabelStyle;
    return base.copyWith(color: color);
  }

  IconData? _iconDataFor(Widget? widget) {
    if (widget is Icon) return widget.icon;
    return null;
  }

  @override
  bool shouldRepaint(_VectorForegroundPainter oldDelegate) {
    return items != oldDelegate.items ||
        selectedIndex != oldDelegate.selectedIndex ||
        selectedIconColor != oldDelegate.selectedIconColor ||
        unselectedIconColor != oldDelegate.unselectedIconColor ||
        iconSize != oldDelegate.iconSize ||
        iconLabelSpacing != oldDelegate.iconLabelSpacing ||
        padding != oldDelegate.padding ||
        textDirection != oldDelegate.textDirection ||
        selectedLabelStyle != oldDelegate.selectedLabelStyle ||
        unselectedLabelStyle != oldDelegate.unselectedLabelStyle ||
        lens != oldDelegate.lens ||
        debugLayout != oldDelegate.debugLayout ||
        itemRectResolver != oldDelegate.itemRectResolver;
  }
}

class _PaintRunMetrics {
  const _PaintRunMetrics({
    required this.sourceCenter,
    required this.warpedCenter,
    required this.paintOffset,
    required this.scale,
    required this.edge,
    required this.groupCoverage,
    required this.groupDelta,
  });

  final Offset sourceCenter;
  final Offset warpedCenter;
  final Offset paintOffset;
  final double scale;
  final double edge;
  final double groupCoverage;
  final Offset groupDelta;

  String get debugString =>
      'src=${_fmtOffset(sourceCenter)},dst=${_fmtOffset(warpedCenter)},'
      'paint=${_fmtOffset(paintOffset)},scale=${_fmt(scale)},'
      'edge=${_fmt(edge)},cover=${_fmt(groupCoverage)},'
      'delta=${_fmtOffset(groupDelta)}';
}

String _fmt(double value) => value.toStringAsFixed(2);

String _fmtOffset(Offset offset) => '(${_fmt(offset.dx)},${_fmt(offset.dy)})';

String _fmtSize(Size size) => '${_fmt(size.width)}x${_fmt(size.height)}';

String _fmtRect(Rect rect) =>
    '(${_fmt(rect.left)},${_fmt(rect.top)},${_fmt(rect.width)},${_fmt(rect.height)})';

class _GlyphRun {
  const _GlyphRun({
    required this.text,
    required this.style,
    required this.strutStyle,
    required this.size,
    required this.paintOffset,
    required this.localDx,
  });

  final String text;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final Size size;
  final Offset paintOffset;
  final double localDx;
}

class _LensField {
  const _LensField({
    required this.kind,
    required this.itemCount,
    required this.alignment,
    required this.thickness,
    required this.expansion,
    required this.borderRadius,
    this.indicatorLeft,
    this.indicatorWidth,
  });

  factory _LensField.bottomBar({
    required int itemCount,
    required Alignment alignment,
    required double thickness,
    required double expansion,
    required double borderRadius,
  }) {
    return _LensField(
      kind: _LensKind.bottomBar,
      itemCount: itemCount,
      alignment: alignment,
      thickness: thickness,
      expansion: expansion,
      borderRadius: borderRadius,
    );
  }

  factory _LensField.tabBar({
    required int itemCount,
    required Alignment alignment,
    required double thickness,
    required double expansion,
    required double borderRadius,
    double? indicatorLeft,
    double? indicatorWidth,
  }) {
    return _LensField(
      kind: _LensKind.tabBar,
      itemCount: itemCount,
      alignment: alignment,
      thickness: thickness,
      expansion: expansion,
      borderRadius: borderRadius,
      indicatorLeft: indicatorLeft,
      indicatorWidth: indicatorWidth,
    );
  }

  final _LensKind kind;
  final int itemCount;
  final Alignment alignment;
  final double thickness;
  final double expansion;
  final double borderRadius;
  final double? indicatorLeft;
  final double? indicatorWidth;

  double get effectAmount => _smoothstep(0.05, 0.65, thickness);

  Rect rectFor(Size size) {
    if (kind == _LensKind.bottomBar) {
      final tabWidth = size.width / itemCount;
      final availableWidth = size.width - tabWidth;
      final left = (alignment.x + 1) / 2 * availableWidth;
      final baseRect = Rect.fromLTWH(left, 0, tabWidth, size.height);
      final paddedRect = Rect.fromLTRB(
        baseRect.left + 4.0,
        baseRect.top + 4.0,
        baseRect.right - 4.0,
        baseRect.bottom - 4.0,
      );
      return paddedRect.inflate(expansion * thickness);
    }

    final slotWidth = indicatorWidth ?? size.width / itemCount;
    final left =
        indicatorLeft ?? (alignment.x + 1.0) * 0.5 * (size.width - slotWidth);
    return Rect.fromLTWH(left, 0, slotWidth, size.height).inflate(
      expansion * thickness,
    );
  }

  Offset warpPoint(Offset p, Size size) {
    final edge = edgeAmount(p, size);
    if (edge <= 0.0) return p;

    final normal = normalAt(p, size);
    final rect = rectFor(size);
    final strength = edge * edge * effectAmount * 0.16;
    return p + normal * rect.height * strength;
  }

  double edgeAmount(Offset p, Size size) {
    final rect = rectFor(size);
    final sd = _roundedRectSdf(p, rect, borderRadius + expansion * thickness);
    final width = math.max(8.0, rect.height * 0.22);
    return _smoothstep(width, 0.0, sd.abs());
  }

  double coverageAmount(Offset p, Size size) {
    final rect = rectFor(size);
    final sd = _roundedRectSdf(p, rect, borderRadius + expansion * thickness);
    final width = math.max(6.0, rect.height * 0.12);
    return _smoothstep(width, 0.0, sd);
  }

  Offset normalAt(Offset p, Size size) {
    const eps = 0.75;
    final rect = rectFor(size);
    final radius = borderRadius + expansion * thickness;
    final dx = _roundedRectSdf(p + const Offset(eps, 0), rect, radius) -
        _roundedRectSdf(p - const Offset(eps, 0), rect, radius);
    final dy = _roundedRectSdf(p + const Offset(0, eps), rect, radius) -
        _roundedRectSdf(p - const Offset(0, eps), rect, radius);
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-4) return Offset.zero;
    return Offset(dx / len, dy / len);
  }

  static double _roundedRectSdf(Offset p, Rect rect, double radius) {
    final center = rect.center;
    final half = Offset(rect.width / 2, rect.height / 2);
    final qx = (p.dx - center.dx).abs() - (half.dx - radius);
    final qy = (p.dy - center.dy).abs() - (half.dy - radius);
    final outside = Offset(math.max(qx, 0.0), math.max(qy, 0.0)).distance;
    final inside = math.min(math.max(qx, qy), 0.0);
    return outside + inside - radius;
  }

  static double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  @override
  bool operator ==(Object other) {
    return other is _LensField &&
        kind == other.kind &&
        itemCount == other.itemCount &&
        alignment == other.alignment &&
        thickness == other.thickness &&
        expansion == other.expansion &&
        borderRadius == other.borderRadius &&
        indicatorLeft == other.indicatorLeft &&
        indicatorWidth == other.indicatorWidth;
  }

  @override
  int get hashCode => Object.hash(
        kind,
        itemCount,
        alignment,
        thickness,
        expansion,
        borderRadius,
        indicatorLeft,
        indicatorWidth,
      );
}

enum _LensKind { bottomBar, tabBar }

class _BottomBarLensClipper extends CustomClipper<Path> {
  const _BottomBarLensClipper({
    required this.itemCount,
    required this.alignment,
    required this.thickness,
    required this.expansion,
    required this.transform,
    required this.borderRadius,
  });

  final int itemCount;
  final Alignment alignment;
  final double thickness;
  final double expansion;
  final Matrix4 transform;
  final double borderRadius;

  @override
  Path getClip(Size size) {
    final rect = _LensField.bottomBar(
      itemCount: itemCount,
      alignment: alignment,
      thickness: thickness,
      expansion: expansion,
      borderRadius: borderRadius,
    ).rectFor(size);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
      );

    final center = rect.center;
    final centeredTransform = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..multiply(transform)
      ..translate(-center.dx, -center.dy);
    return path.transform(centeredTransform.storage);
  }

  @override
  bool shouldReclip(covariant _BottomBarLensClipper oldClipper) {
    return itemCount != oldClipper.itemCount ||
        alignment != oldClipper.alignment ||
        thickness != oldClipper.thickness ||
        expansion != oldClipper.expansion ||
        transform != oldClipper.transform ||
        borderRadius != oldClipper.borderRadius;
  }
}

class _TabBarLensClipper extends CustomClipper<Path> {
  const _TabBarLensClipper({
    required this.itemCount,
    required this.borderRadius,
    required this.expansion,
    required this.thickness,
    this.alignment,
    this.indicatorLeft,
    this.indicatorWidth,
  });

  final int itemCount;
  final Alignment? alignment;
  final double? indicatorLeft;
  final double? indicatorWidth;
  final double borderRadius;
  final double expansion;
  final double thickness;

  @override
  Path getClip(Size size) {
    final rect = _LensField.tabBar(
      itemCount: itemCount,
      alignment: alignment ?? Alignment.center,
      thickness: thickness,
      expansion: expansion,
      borderRadius: borderRadius,
      indicatorLeft: indicatorLeft,
      indicatorWidth: indicatorWidth,
    ).rectFor(size);
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(borderRadius + expansion * thickness),
        ),
      );
  }

  @override
  bool shouldReclip(covariant _TabBarLensClipper oldClipper) {
    return itemCount != oldClipper.itemCount ||
        alignment != oldClipper.alignment ||
        indicatorLeft != oldClipper.indicatorLeft ||
        indicatorWidth != oldClipper.indicatorWidth ||
        borderRadius != oldClipper.borderRadius ||
        expansion != oldClipper.expansion ||
        thickness != oldClipper.thickness;
  }
}
