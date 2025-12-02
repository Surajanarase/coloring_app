// lib/services/hit_test_service.dart
// ====================================
// CRITICAL FIX: Changed from math.max to math.min to match BoxFit.contain
// This ensures hit-testing works correctly on ALL device sizes

import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'svg_service.dart';

class HitTestService {
  final Map<String, ui.Path> paths;
  final ViewBox viewBox;

  HitTestService({required this.paths, required this.viewBox});

  /// localPos and widgetSize are in Flutter/widget coordinate space
  String? hitTest(ui.Offset localPos, ui.Size widgetSize) {
    if (paths.isEmpty || viewBox.width == 0 || viewBox.height == 0) return null;

    final sx = widgetSize.width / viewBox.width;
    final sy = widgetSize.height / viewBox.height;

    // ✅ FIXED: Use math.min for BoxFit.contain (was math.max for cover)
    // This ensures the entire SVG fits within the widget without cropping
    final scale = math.min(sx, sy);

    final drawnW = viewBox.width * scale;
    final drawnH = viewBox.height * scale;
    final offsetX = (widgetSize.width - drawnW) / 2.0;
    final offsetY = (widgetSize.height - drawnH) / 2.0;
    final tx = -viewBox.minX * scale + offsetX;
    final ty = -viewBox.minY * scale + offsetY;

    final Float64List matrix = Float64List.fromList([
      scale, 0, 0, 0,
      0, scale, 0, 0,
      0, 0, 1, 0,
      tx, ty, 0, 1,
    ]);

    String? bestId;
    double bestArea = double.infinity;

    for (final entry in paths.entries) {
      // transform path into widget space
      final transformed = entry.value.transform(matrix);

      // contains expects an ui.Offset – localPos is ui.Offset (widget coords)
      if (transformed.contains(localPos)) {
        final b = transformed.getBounds();
        final area = b.width * b.height;
        if (area < bestArea) {
          bestArea = area;
          bestId = entry.key;
        }
      }
    }
    return bestId;
  }
}