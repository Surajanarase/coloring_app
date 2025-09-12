// lib/services/path_service.dart
import 'package:xml/xml.dart';
import 'package:path_drawing/path_drawing.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';

/// PathService: converts drawable SVG elements into ui.Path objects.
/// Supports element-level `transform` (translate, scale, rotate, matrix).
class PathService {
  final Map<String, ui.Path> paths = {};

  bool _isDrawableName(String name) {
    return name == 'path' ||
        name == 'rect' ||
        name == 'circle' ||
        name == 'ellipse' ||
        name == 'polygon' ||
        name == 'polyline';
  }

  ui.Path? _pathFromElement(XmlElement el) {
    final name = el.name.local.toLowerCase();
    try {
      ui.Path? p;
      if (name == 'path') {
        final d = el.getAttribute('d');
        if (d != null && d.trim().isNotEmpty) p = parseSvgPathData(d);
      } else if (name == 'rect') {
        final x = double.tryParse(el.getAttribute('x') ?? '0') ?? 0;
        final y = double.tryParse(el.getAttribute('y') ?? '0') ?? 0;
        final w = double.tryParse(el.getAttribute('width') ?? '0') ?? 0;
        final h = double.tryParse(el.getAttribute('height') ?? '0') ?? 0;
        final rx = double.tryParse(el.getAttribute('rx') ?? '0') ?? 0;
        final tmp = ui.Path();
        if (rx > 0) {
          tmp.addRRect(ui.RRect.fromRectXY(ui.Rect.fromLTWH(x, y, w, h), rx, rx));
        } else {
          tmp.addRect(ui.Rect.fromLTWH(x, y, w, h));
        }
        p = tmp;
      } else if (name == 'circle') {
        final cx = double.tryParse(el.getAttribute('cx') ?? '0') ?? 0;
        final cy = double.tryParse(el.getAttribute('cy') ?? '0') ?? 0;
        final r = double.tryParse(el.getAttribute('r') ?? '0') ?? 0;
        p = ui.Path()..addOval(ui.Rect.fromCircle(center: ui.Offset(cx, cy), radius: r));
      } else if (name == 'ellipse') {
        final cx = double.tryParse(el.getAttribute('cx') ?? '0') ?? 0;
        final cy = double.tryParse(el.getAttribute('cy') ?? '0') ?? 0;
        final rx = double.tryParse(el.getAttribute('rx') ?? '0') ?? 0;
        final ry = double.tryParse(el.getAttribute('ry') ?? '0') ?? 0;
        p = ui.Path()
          ..addOval(ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: rx * 2, height: ry * 2));
      } else if (name == 'polygon' || name == 'polyline') {
        final pts = el.getAttribute('points') ?? '';
        final coords = pts
            .split(RegExp(r'[\s,]+'))
            .map((s) => double.tryParse(s))
            .where((v) => v != null)
            .map((v) => v!)
            .toList();
        if (coords.length >= 4) {
          final tmp = ui.Path();
          tmp.moveTo(coords[0], coords[1]);
          for (int i = 2; i + 1 < coords.length; i += 2) {
            tmp.lineTo(coords[i], coords[i + 1]);
          }
          if (name == 'polygon') tmp.close();
          p = tmp;
        }
      }

      if (p == null) return null;

      // parse and apply element transform if present
      final tf = el.getAttribute('transform');
      if (tf != null && tf.trim().isNotEmpty) {
        final mat = _parseTransform(tf);
        if (mat != null) {
          final Float64List matrix4 = Float64List.fromList([
            mat[0], mat[1], 0, 0, // m00, m10, m20, m30
            mat[2], mat[3], 0, 0, // m01, m11, m21, m31
            0, 0, 1, 0,           // m02, m12, m22, m32
            mat[4], mat[5], 0, 1, // m03 (tx), m13 (ty), m23, m33
          ]);
          p = p.transform(matrix4);
        }
      }

      return p;
    } catch (_) {
      return null;
    }
  }

  /// parse transform attribute and return affine params [a,b,c,d,e,f]
  /// where x' = a*x + c*y + e ; y' = b*x + d*y + f
  List<double>? _parseTransform(String tf) {
    double a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;

    List<double> mul(List<double> A, List<double> B) {
      final a1 = A[0], b1 = A[1], c1 = A[2], d1 = A[3], e1 = A[4], f1 = A[5];
      final a2 = B[0], b2 = B[1], c2 = B[2], d2 = B[3], e2 = B[4], f2 = B[5];
      final na = a1 * a2 + c1 * b2;
      final nb = b1 * a2 + d1 * b2;
      final nc = a1 * c2 + c1 * d2;
      final nd = b1 * c2 + d1 * d2;
      final ne = a1 * e2 + c1 * f2 + e1;
      final nf = b1 * e2 + d1 * f2 + f1;
      return [na, nb, nc, nd, ne, nf];
    }

    final re = RegExp(r'([a-zA-Z]+)\s*\(([^)]+)\)');
    final matches = re.allMatches(tf);
    for (final m in matches) {
      final cmd = m.group(1)!.toLowerCase();
      final content = m.group(2)!;
      final parts = content
          .replaceAll(',', ' ')
          .split(RegExp(r'[\s]+'))
          .where((s) => s.trim().isNotEmpty)
          .map((s) => double.tryParse(s.trim()))
          .toList();

      if (cmd == 'translate') {
        final tx = parts.isNotEmpty && parts[0] != null ? parts[0]! : 0.0;
        final ty = parts.length > 1 && parts[1] != null ? parts[1]! : 0.0;
        final T = [1.0, 0.0, 0.0, 1.0, tx, ty];
        final res = mul(T, [a, b, c, d, e, f]);
        a = res[0]; b = res[1]; c = res[2]; d = res[3]; e = res[4]; f = res[5];
      } else if (cmd == 'scale') {
        final sx = parts.isNotEmpty && parts[0] != null ? parts[0]! : 1.0;
        final sy = parts.length > 1 && parts[1] != null ? parts[1]! : sx;
        final S = [sx, 0.0, 0.0, sy, 0.0, 0.0];
        final res = mul(S, [a, b, c, d, e, f]);
        a = res[0]; b = res[1]; c = res[2]; d = res[3]; e = res[4]; f = res[5];
      } else if (cmd == 'rotate') {
        final angle = parts.isNotEmpty && parts[0] != null ? parts[0]! : 0.0;
        final rad = angle * math.pi / 180.0;
        final cosT = math.cos(rad);
        final sinT = math.sin(rad);
        final R = [cosT, sinT, -sinT, cosT, 0.0, 0.0];
        if (parts.length >= 3 && parts[1] != null && parts[2] != null) {
          final cx = parts[1]!;
          final cy = parts[2]!;
          // translate(cx,cy) * R * translate(-cx,-cy)
          final t1 = [1.0, 0.0, 0.0, 1.0, cx, cy];
          final t2 = [1.0, 0.0, 0.0, 1.0, -cx, -cy];
          final temp = mul(R, t2);
          final total = mul(t1, temp);
          final res = mul(total, [a, b, c, d, e, f]);
          a = res[0]; b = res[1]; c = res[2]; d = res[3]; e = res[4]; f = res[5];
        } else {
          final res = mul(R, [a, b, c, d, e, f]);
          a = res[0]; b = res[1]; c = res[2]; d = res[3]; e = res[4]; f = res[5];
        }
      } else if (cmd == 'matrix') {
        if (parts.length >= 6 &&
            parts[0] != null &&
            parts[1] != null &&
            parts[2] != null &&
            parts[3] != null &&
            parts[4] != null &&
            parts[5] != null) {
          final mat = [parts[0]!, parts[1]!, parts[2]!, parts[3]!, parts[4]!, parts[5]!];
          final res = mul(mat, [a, b, c, d, e, f]);
          a = res[0]; b = res[1]; c = res[2]; d = res[3]; e = res[4]; f = res[5];
        }
      } else {
        // ignore unknown transforms
      }
    }

    return [a, b, c, d, e, f];
  }

  void buildPathsFromDoc(XmlDocument doc) {
    paths.clear();
    for (final el in doc.descendants.whereType<XmlElement>()) {
      final name = el.name.local.toLowerCase();
      if (!_isDrawableName(name)) continue;
      var id = el.getAttribute('id');
      if (id == null || id.trim().isEmpty) {
        id = '__auto_${paths.length}';
        el.setAttribute('id', id);
      }
      final p = _pathFromElement(el);
      if (p != null) {
        paths[id] = p;
      }
    }
  }
}
