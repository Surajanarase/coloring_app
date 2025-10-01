// lib/services/hit_test_service.dart
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'svg_service.dart'; // same-folder import to access ViewBox

class HitTestService {
  final Map<String, ui.Path> paths;
  final ViewBox viewBox;

  HitTestService({required this.paths, required this.viewBox});

  /// localPos and widgetSize are in Flutter/widget coordinate space
  String? hitTest(ui.Offset localPos, ui.Size widgetSize) {
    if (paths.isEmpty || viewBox.width == 0 || viewBox.height == 0) return null;

    final sx = widgetSize.width / viewBox.width;
    final sy = widgetSize.height / viewBox.height;
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

      // contains expects an ui.Offset — localPos is ui.Offset
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