import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import 'package:path_drawing/path_drawing.dart';
import 'dart:math' as math;

class ColoringPage extends StatefulWidget {
  const ColoringPage({super.key});
  @override
  State<ColoringPage> createState() => _ColoringPageState();
}

class _ColoringPageState extends State<ColoringPage> {
  String? _svgString;
  XmlDocument? _doc;

  final Map<String, ui.Path> _paths = {};
  double _vbMinX = 0, _vbMinY = 0, _vbWidth = 0, _vbHeight = 0;

  final List<Color> _palette = [
    Colors.red,
    Colors.pink,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.purple,
    Colors.brown,
    Colors.grey,
    const Color(0xFFFFE0BD), // skin
    const Color(0xFF8D5524),
    Colors.black,
    Colors.white,
  ];

  Color? _selectedColor;

  // History stack for undo
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  Future<void> _loadSvg() async {
    try {
      final raw = await rootBundle.loadString('assets/colouring_svg.svg');
      _svgString = raw;
      _doc = XmlDocument.parse(raw);
      _parseViewBox();
      _buildPathsFromDoc();
    } catch (_) {
      // fallback simple svg
      _svgString =
          "<svg viewBox='0 0 100 100'><rect id='rect1' x='10' y='10' width='80' height='80' fill='white' stroke='black'/></svg>";
      _doc = XmlDocument.parse(_svgString!);
      _parseViewBox();
      _buildPathsFromDoc();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _parseViewBox() {
    if (_doc == null) return;
    final root = _doc!.rootElement;
    final vb = root.getAttribute('viewBox');
    if (vb != null) {
      final parts = vb
          .split(RegExp(r'[\s,]+'))
          .map((s) => double.tryParse(s) ?? 0.0)
          .toList();
      if (parts.length >= 4) {
        _vbMinX = parts[0];
        _vbMinY = parts[1];
        _vbWidth = parts[2];
        _vbHeight = parts[3];
        return;
      }
    }
    _vbWidth = double.tryParse(root.getAttribute('width') ?? '') ?? 1000;
    _vbHeight = double.tryParse(root.getAttribute('height') ?? '') ?? 1000;
    _vbMinX = 0;
    _vbMinY = 0;
  }

  bool _isDrawableName(String name) {
    return name == 'path' ||
        name == 'rect' ||
        name == 'circle' ||
        name == 'ellipse' ||
        name == 'polygon' ||
        name == 'polyline';
  }

  ui.Path? pathFromElement(XmlElement el) {
    final name = el.name.local.toLowerCase();
    try {
      if (name == 'path') {
        final d = el.getAttribute('d');
        if (d != null && d.trim().isNotEmpty) return parseSvgPathData(d);
      } else if (name == 'rect') {
        final x = double.tryParse(el.getAttribute('x') ?? '0') ?? 0;
        final y = double.tryParse(el.getAttribute('y') ?? '0') ?? 0;
        final w = double.tryParse(el.getAttribute('width') ?? '0') ?? 0;
        final h = double.tryParse(el.getAttribute('height') ?? '0') ?? 0;
        final rx = double.tryParse(el.getAttribute('rx') ?? '0') ?? 0;
        final tmp = ui.Path();
        if (rx > 0) {
          tmp.addRRect(RRect.fromRectXY(Rect.fromLTWH(x, y, w, h), rx, rx));
        } else {
          tmp.addRect(Rect.fromLTWH(x, y, w, h));
        }
        return tmp;
      } else if (name == 'circle') {
        final cx = double.tryParse(el.getAttribute('cx') ?? '0') ?? 0;
        final cy = double.tryParse(el.getAttribute('cy') ?? '0') ?? 0;
        final r = double.tryParse(el.getAttribute('r') ?? '0') ?? 0;
        return ui.Path()
          ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      } else if (name == 'ellipse') {
        final cx = double.tryParse(el.getAttribute('cx') ?? '0') ?? 0;
        final cy = double.tryParse(el.getAttribute('cy') ?? '0') ?? 0;
        final rx = double.tryParse(el.getAttribute('rx') ?? '0') ?? 0;
        final ry = double.tryParse(el.getAttribute('ry') ?? '0') ?? 0;
        return ui.Path()
          ..addOval(Rect.fromCenter(
              center: Offset(cx, cy), width: rx * 2, height: ry * 2));
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
          return tmp;
        }
      }
    } catch (_) {}
    return null;
  }

  void _buildPathsFromDoc() {
    _paths.clear();
    if (_doc == null) return;

    for (final el in _doc!.descendants.whereType<XmlElement>()) {
      final name = el.name.local.toLowerCase();
      if (!_isDrawableName(name)) continue;
      final id = el.getAttribute('id');
      if (id != null && id.trim().isNotEmpty) {
        final p = pathFromElement(el);
        if (p == null) continue;
        _paths[id] = p;
      }
    }
  }

  String _colorToHex(Color c) {
    final ri = ((c.r * 255).round() & 0xFF);
    final gi = ((c.g * 255).round() & 0xFF);
    final bi = ((c.b * 255).round() & 0xFF);
    final ai = ((c.a * 255).round() & 0xFF);

    final r = ri.toRadixString(16).padLeft(2, '0').toUpperCase();
    final g = gi.toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = bi.toRadixString(16).padLeft(2, '0').toUpperCase();
    final a = ai.toRadixString(16).padLeft(2, '0').toUpperCase();

    if (ai == 0xFF) {
      return '#$r$g$b';
    }
    return '#$a$r$g$b';
  }

  void _setPartColor(String id, Color color) {
    if (_doc == null) return;

    // Save current state for undo
    _history.add(_doc!.toXmlString(pretty: false));

    final hex = _colorToHex(color);

    XmlElement? target;
    try {
      target = _doc!.descendants
          .whereType<XmlElement>()
          .firstWhere((e) => e.getAttribute('id') == id);
    } catch (_) {
      target = null;
    }

    if (target == null) return;

    _applyFillToElement(target, hex);

    _svgString = _doc!.toXmlString(pretty: false);
    if (mounted) {
      setState(() {
        _buildPathsFromDoc();
      });
    }
  }

  void _applyFillToElement(XmlElement elem, String hex) {
    final style = elem.getAttribute('style');
    if (style != null && style.trim().isNotEmpty) {
      final entries = style
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      var changed = false;
      for (int i = 0; i < entries.length; i++) {
        if (entries[i].startsWith('fill:')) {
          entries[i] = 'fill: $hex';
          changed = true;
          break;
        }
      }
      if (!changed) entries.add('fill: $hex');
      elem.setAttribute('style', entries.join('; '));
    } else {
      elem.setAttribute('fill', hex);
    }
  }

  Future<void> _reset() async {
    await _loadSvg();
    if (mounted) {
      setState(() {
        _selectedColor = null;
        _history.clear();
      });
    }
  }

  String? _hitTest(Offset localPos, Size widgetSize) {
    if (_paths.isEmpty || _vbWidth == 0 || _vbHeight == 0) return null;

    final sx = widgetSize.width / _vbWidth;
    final sy = widgetSize.height / _vbHeight;
    final scale = math.min(sx, sy);
    final drawnW = _vbWidth * scale;
    final drawnH = _vbHeight * scale;
    final offsetX = (widgetSize.width - drawnW) / 2.0;
    final offsetY = (widgetSize.height - drawnH) / 2.0;
    final tx = -_vbMinX * scale + offsetX;
    final ty = -_vbMinY * scale + offsetY;

    final Float64List matrix = Float64List.fromList([
      scale, 0, 0, 0, //
      0, scale, 0, 0, //
      0, 0, 1, 0, //
      tx, ty, 0, 1, //
    ]);

    String? bestId;
    double bestArea = double.infinity;

    for (final entry in _paths.entries) {
      final transformed = entry.value.transform(matrix);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SVG Coloring'),
        actions: [
          IconButton(
            onPressed: () {
              if (_history.isNotEmpty) {
                final prev = _history.removeLast();
                _svgString = prev;
                _doc = XmlDocument.parse(prev);
                setState(() {
                  _buildPathsFromDoc();
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nothing to undo')),
                );
              }
            },
            icon: const Icon(Icons.undo),
          ),
          IconButton(onPressed: _reset, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _svgString == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Image area
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final canvasSize =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          final pos = details.localPosition;
                          final hit = _hitTest(pos, canvasSize);
                          if (hit != null) {
                            if (_selectedColor != null) {
                              _setPartColor(hit, _selectedColor!);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Select a color first.')),
                              );
                            }
                          }
                        },
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _vbWidth != 0 && _vbHeight != 0
                                ? _vbWidth / _vbHeight
                                : 1,
                            child: SvgPicture.string(
                              _svgString!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                // Palette area at bottom
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  color: Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Palette",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: _palette.map((c) {
                          final selected = c == _selectedColor;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColor = c;
                              });
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Colors.black
                                      : Colors.black26,
                                  width: selected ? 3 : 1,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedColor = null;
                          });
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text("Clear Selection"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
