// lib/services/hit_test_service.dart
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'svg_service.dart'; // to access your custom ViewBox

class HitTestService {
  /// `paths` must be a map of id -> ui.Path where the Path coordinates are in SVG/viewBox coordinate space.
  final Map<String, ui.Path> paths;
  final ViewBox viewBox;

  HitTestService({required this.paths, required this.viewBox});

  /// [localPos] is in widget coordinate space (after undoing zoom/pan transform).
  /// Converts to SVG coords using viewBox and widget size,
  /// then checks which path contains the point.
  String? hitTest(ui.Offset localPos, ui.Size widgetSize) {
    if (paths.isEmpty || viewBox.width == 0 || viewBox.height == 0) return null;

    // --- Step 1: compute scale used when SVG is fit into the widget ---
    final double sx = widgetSize.width / viewBox.width;
    final double sy = widgetSize.height / viewBox.height;
    final double scale = math.min(sx, sy);

    // --- Step 2: compute the actual drawn size inside the widget ---
    final double drawnW = viewBox.width * scale;
    final double drawnH = viewBox.height * scale;
    final double offsetX = (widgetSize.width - drawnW) / 2.0;
    final double offsetY = (widgetSize.height - drawnH) / 2.0;

    // --- Step 3: compute translation applied when drawing ---
    final double tx = -viewBox.minX * scale + offsetX;
    final double ty = -viewBox.minY * scale + offsetY;

    // --- Step 4: map widget coords → SVG coords ---
    final double svgX = (localPos.dx - tx) / scale;
    final double svgY = (localPos.dy - ty) / scale;
    final ui.Offset svgPoint = ui.Offset(svgX, svgY);

    // --- Step 5: test against paths ---
    String? bestId;
    double bestArea = double.infinity;

    for (final entry in paths.entries) {
      final id = entry.key;
      final path = entry.value;

      try {
        if (path.contains(svgPoint)) {
          final bounds = path.getBounds();
          final area = bounds.width * bounds.height;
          if (area < bestArea) {
            bestArea = area;
            bestId = id;
          }

          // Debug (optional)
          // debugPrint('HIT: id=$id svgPoint=$svgPoint bounds=$bounds');
        }
      } catch (_) {
        // ignore any path errors for robustness
      }
    }

    return bestId;
  }
}
