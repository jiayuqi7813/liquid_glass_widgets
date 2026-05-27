// ignore_for_file: deprecated_member_use
library;

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../glass_bottom_bar.dart' show GlassBottomBarTab, JellyClipper;

/// Experimental foreground renderer for premium bottom bars.
///
/// This keeps foreground content out of the shader texture pipeline. Standard
/// [Icon] glyphs and labels are painted after the glass pass so Flutter
/// rasterizes them at the final screen resolution, avoiding magnified atlas
/// softness while still allowing a lens-shaped displacement field.
class BottomBarVectorForegroundLayer extends StatelessWidget {
  const BottomBarVectorForegroundLayer({
    required this.tabs,
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
    this.textStyle,
    super.key,
  });

  final List<GlassBottomBarTab> tabs;
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
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (thickness <= 0.05) return const SizedBox.expand();

    return IgnorePointer(
      child: ClipPath(
        clipper: JellyClipper(
          itemCount: itemCount,
          alignment: alignment,
          thickness: thickness,
          expansion: expansion,
          transform: transform,
          borderRadius: borderRadius,
        ),
        child: CustomPaint(
          painter: _BottomBarVectorForegroundPainter(
            tabs: tabs,
            selectedIndex: selectedIndex,
            selectedIconColor: selectedIconColor,
            unselectedIconColor: unselectedIconColor,
            iconSize: iconSize,
            labelFontSize: labelFontSize,
            iconLabelSpacing: iconLabelSpacing,
            textStyle: textStyle,
            padding: tabPadding.resolve(Directionality.of(context)),
            itemCount: itemCount,
            alignment: alignment,
            thickness: thickness,
            expansion: expansion,
            borderRadius: borderRadius,
            textDirection: Directionality.of(context),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _BottomBarVectorForegroundPainter extends CustomPainter {
  const _BottomBarVectorForegroundPainter({
    required this.tabs,
    required this.selectedIndex,
    required this.selectedIconColor,
    required this.unselectedIconColor,
    required this.iconSize,
    required this.labelFontSize,
    required this.iconLabelSpacing,
    required this.textStyle,
    required this.padding,
    required this.itemCount,
    required this.alignment,
    required this.thickness,
    required this.expansion,
    required this.borderRadius,
    required this.textDirection,
  });

  final List<GlassBottomBarTab> tabs;
  final int selectedIndex;
  final Color selectedIconColor;
  final Color unselectedIconColor;
  final double iconSize;
  final double labelFontSize;
  final double iconLabelSpacing;
  final TextStyle? textStyle;
  final EdgeInsets padding;
  final int itemCount;
  final Alignment alignment;
  final double thickness;
  final double expansion;
  final double borderRadius;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (tabs.isEmpty || itemCount <= 0 || size.isEmpty) return;

    final contentRect = padding.deflateRect(Offset.zero & size);
    if (contentRect.isEmpty) return;

    final tabWidth = contentRect.width / itemCount;
    for (var index = 0; index < tabs.length; index++) {
      final tab = tabs[index];
      final selected = index == selectedIndex;
      final color = selected ? selectedIconColor : unselectedIconColor;
      final rect = Rect.fromLTWH(
        contentRect.left + index * tabWidth,
        contentRect.top,
        tabWidth,
        contentRect.height,
      );
      _paintTab(canvas, size, rect, tab, selected, color);
    }
  }

  void _paintTab(
    Canvas canvas,
    Size size,
    Rect rect,
    GlassBottomBarTab tab,
    bool selected,
    Color color,
  ) {
    final iconWidget = selected ? (tab.activeIcon ?? tab.icon) : tab.icon;
    final iconData = _iconDataFor(iconWidget);
    final label = tab.label;

    final labelPainter = label == null
        ? null
        : (TextPainter(
            text: TextSpan(text: label, style: _labelStyle(color, selected)),
            textAlign: TextAlign.center,
            textDirection: textDirection,
            maxLines: 1,
            ellipsis: '',
          )..layout(maxWidth: rect.width));

    final hasIcon = iconData != null;
    final hasLabel = labelPainter != null;
    if (!hasIcon && !hasLabel) return;

    final labelHeight = labelPainter?.height ?? 0.0;
    final gap = hasIcon && hasLabel ? iconLabelSpacing : 0.0;
    final contentHeight = (hasIcon ? iconSize : 0.0) + gap + labelHeight;
    var y = rect.center.dy - contentHeight / 2;

    if (hasIcon) {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(iconData.codePoint),
          style: TextStyle(
            inherit: false,
            color: color,
            fontSize: iconSize,
            fontFamily: iconData.fontFamily,
            package: iconData.fontPackage,
          ),
        ),
        textDirection: textDirection,
      )..layout();

      final center = Offset(rect.center.dx, y + iconSize / 2);
      _paintWarpedText(canvas, size, iconPainter, center, color);
      y += iconSize + gap;
    }

    if (labelPainter != null) {
      final center = Offset(rect.center.dx, y + labelHeight / 2);
      _paintWarpedText(canvas, size, labelPainter, center, color);
    }
  }

  void _paintWarpedText(
    Canvas canvas,
    Size size,
    TextPainter painter,
    Offset center,
    Color color,
  ) {
    final edge = _edgeAmount(center, size);
    final warped = _warpPoint(center, size);
    final offset = Offset(
      warped.dx - painter.width / 2,
      warped.dy - painter.height / 2,
    );

    if (edge > 0.01) {
      final normal = _normalAt(center, size);
      final fringePx = math.min(0.65, 0.18 + edge * 0.42);
      _paintTextWithColor(
        canvas,
        painter,
        offset + normal * fringePx,
        Color.fromRGBO(255, 42, 34, 0.12 * edge),
      );
      _paintTextWithColor(
        canvas,
        painter,
        offset - normal * fringePx,
        Color.fromRGBO(32, 116, 255, 0.12 * edge),
      );
    }

    _paintTextWithColor(canvas, painter, offset, color);
  }

  void _paintTextWithColor(
    Canvas canvas,
    TextPainter painter,
    Offset offset,
    Color color,
  ) {
    final span = painter.text;
    if (span is! TextSpan) {
      painter.paint(canvas, offset);
      return;
    }

    final tinted = TextPainter(
      text: TextSpan(
        text: span.text,
        style: span.style?.copyWith(color: color),
      ),
      textAlign: painter.textAlign,
      textDirection: textDirection,
      maxLines: painter.maxLines,
      ellipsis: painter.ellipsis,
    )..layout(maxWidth: math.max(painter.width, 1.0));
    tinted.paint(canvas, offset);
  }

  TextStyle _labelStyle(Color color, bool selected) {
    final base = textStyle ??
        TextStyle(
          fontSize: labelFontSize,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        );
    return base.copyWith(color: color);
  }

  IconData? _iconDataFor(Widget widget) {
    if (widget is Icon) return widget.icon;
    return null;
  }

  Offset _warpPoint(Offset p, Size size) {
    final edge = _edgeAmount(p, size);
    if (edge <= 0.0) return p;

    final normal = _normalAt(p, size);
    final rect = _lensRect(size);
    final strength = edge * edge * (0.10 + thickness * 0.08);
    return p + normal * rect.height * strength;
  }

  double _edgeAmount(Offset p, Size size) {
    final rect = _lensRect(size);
    final sd = _roundedRectSdf(p, rect, borderRadius);
    final width = math.max(8.0, rect.height * 0.22);
    return _smoothstep(width, 0.0, sd.abs());
  }

  Offset _normalAt(Offset p, Size size) {
    const eps = 0.75;
    final rect = _lensRect(size);
    final dx = _roundedRectSdf(p + const Offset(eps, 0), rect, borderRadius) -
        _roundedRectSdf(p - const Offset(eps, 0), rect, borderRadius);
    final dy = _roundedRectSdf(p + const Offset(0, eps), rect, borderRadius) -
        _roundedRectSdf(p - const Offset(0, eps), rect, borderRadius);
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-4) return Offset.zero;
    return Offset(dx / len, dy / len);
  }

  Rect _lensRect(Size size) {
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

  double _roundedRectSdf(Offset p, Rect rect, double radius) {
    final center = rect.center;
    final half = Offset(rect.width / 2, rect.height / 2);
    final qx = (p.dx - center.dx).abs() - (half.dx - radius);
    final qy = (p.dy - center.dy).abs() - (half.dy - radius);
    final outside = Offset(math.max(qx, 0.0), math.max(qy, 0.0)).distance;
    final inside = math.min(math.max(qx, qy), 0.0);
    return outside + inside - radius;
  }

  double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  @override
  bool shouldRepaint(_BottomBarVectorForegroundPainter oldDelegate) {
    return tabs != oldDelegate.tabs ||
        selectedIndex != oldDelegate.selectedIndex ||
        selectedIconColor != oldDelegate.selectedIconColor ||
        unselectedIconColor != oldDelegate.unselectedIconColor ||
        iconSize != oldDelegate.iconSize ||
        labelFontSize != oldDelegate.labelFontSize ||
        iconLabelSpacing != oldDelegate.iconLabelSpacing ||
        textStyle != oldDelegate.textStyle ||
        padding != oldDelegate.padding ||
        itemCount != oldDelegate.itemCount ||
        alignment != oldDelegate.alignment ||
        thickness != oldDelegate.thickness ||
        expansion != oldDelegate.expansion ||
        borderRadius != oldDelegate.borderRadius ||
        textDirection != oldDelegate.textDirection;
  }
}
