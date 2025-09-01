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
  List<String> _ids = [];
  String? _selectedId;

  final Map<String, ui.Path> _paths = {};
  double _vbMinX = 0, _vbMinY = 0, _vbWidth = 0, _vbHeight = 0;

  final List<Color> _palette = [
    Colors.red, Colors.pink, Colors.orange, Colors.yellow,
    Colors.green, Colors.teal, Colors.blue, Colors.purple,
    Colors.brown, Colors.grey, const Color(0xFFFFE0BD), // skin
    const Color(0xFF8D5524), Colors.black, Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  /// Load the SVG from assets, but fall back to a dummy one in tests.
  Future<void> _loadSvg() async {
    try {
      final raw = await rootBundle.loadString('assets/colouring_svg.svg');
      _svgString = raw;
      _doc = XmlDocument.parse(raw);
      _extractIds();
      _parseViewBox();
      _buildPathsFromDoc();
    } catch (_) {
      // Fallback in tests (asset not available in test bundle)
      _svgString = "<svg viewBox='0 0 100 100'></svg>";
    }
    if (mounted) setState(() {});
  }

  void _extractIds() {
    _ids = [];
    if (_doc == null) return;
    for (final el in _doc!.descendants.whereType<XmlElement>()) {
      final id = el.getAttribute('id');
      if (id != null && id.trim().isNotEmpty) _ids.add(id);
    }
  }

  void _parseViewBox() {
    if (_doc == null) return;
    final root = _doc!.rootElement;
    final vb = root.getAttribute('viewBox');
    if (vb != null) {
      final parts = vb.split(RegExp(r'[\s,]+')).map((s) => double.tryParse(s) ?? 0.0).toList();
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

  void _buildPathsFromDoc() {
    _paths.clear();
    if (_doc == null) return;
    final all = _doc!.descendants.whereType<XmlElement>();
    for (final el in all) {
      final id = el.getAttribute('id');
      if (id == null) continue;
      final name = el.name.local.toLowerCase();
      try {
        ui.Path? p;
        if (name == 'path') {
          final d = el.getAttribute('d');
          if (d != null) p = parseSvgPathData(d);
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
          p = tmp;
        } else if (name == 'circle') {
          final cx = double.tryParse(el.getAttribute('cx') ?? '0') ?? 0;
          final cy = double.tryParse(el.getAttribute('cy') ?? '0') ?? 0;
          final r = double.tryParse(el.getAttribute('r') ?? '0') ?? 0;
          final tmp = ui.Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
          p = tmp;
        } else if (name == 'ellipse') {
          final cx = double.tryParse(el.getAttribute('cx') ?? '0') ?? 0;
          final cy = double.tryParse(el.getAttribute('cy') ?? '0') ?? 0;
          final rx = double.tryParse(el.getAttribute('rx') ?? '0') ?? 0;
          final ry = double.tryParse(el.getAttribute('ry') ?? '0') ?? 0;
          final tmp = ui.Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));
          p = tmp;
        } else if (name == 'polygon' || name == 'polyline') {
          final pts = el.getAttribute('points') ?? '';
          final coords = pts.split(RegExp(r'[\s,]+')).map((s) => double.tryParse(s) ?? double.nan).toList();
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
        if (p != null) _paths[id] = p;
      } catch (_) {}
    }
  }

  String _colorToHex(Color c) {
    return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _setPartColor(String id, Color color) {
    if (_doc == null) return;

    XmlElement? elem;
    try {
      elem = _doc!.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.getAttribute('id') == id,
      );
    } catch (_) {
      elem = null;
    }

    if (elem == null) return;
    elem.setAttribute('fill', _colorToHex(color));
    if (elem.getAttribute('stroke') == null) elem.setAttribute('stroke', 'none');

    _svgString = _doc!.toXmlString(pretty: false);
    setState(() {});
  }

  Future<void> _reset() async {
    await _loadSvg();
    _selectedId = null;
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
      scale, 0, 0, 0,
      0, scale, 0, 0,
      0, 0, 1, 0,
      tx, ty, 0, 1,
    ]);

    for (final entry in _paths.entries) {
      final transformed = entry.value.transform(matrix);
      if (transformed.contains(localPos)) return entry.key;
      if (transformed.getBounds().contains(localPos)) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SVG Coloring'),
        actions: [
          IconButton(onPressed: _reset, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _svgString == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          final pos = details.localPosition;
                          final hit = _hitTest(pos, canvasSize);
                          if (hit != null) {
                            setState(() {
                              _selectedId = hit;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Selected: $hit')),
                            );
                          }
                        },
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _vbWidth != 0 && _vbHeight != 0 ? _vbWidth / _vbHeight : 1,
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
                Expanded(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const Text('Parts (tap canvas or choose):', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _ids.length,
                          itemBuilder: (context, i) {
                            final id = _ids[i];
                            final selected = id == _selectedId;
                            return ListTile(
                              title: Text(id),
                              selected: selected,
                              onTap: () => setState(() => _selectedId = id),
                            );
                          },
                        ),
                      ),
                      const Divider(),
                      const Text('Palette', style: TextStyle(fontWeight: FontWeight.bold)),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _palette.map((c) {
                            return GestureDetector(
                              onTap: () {
                                final id = _selectedId;
                                if (id != null) {
                                  _setPartColor(id, c);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Select a part first (tap or pick from list)')),
                                  );
                                }
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black12),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
