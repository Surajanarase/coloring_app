// lib/pages/colouring_page.dart
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'dart:ui' as ui;

import '../services/db_service.dart';
import '../services/svg_service.dart';
import '../services/path_service.dart';
import '../services/hit_test_service.dart';
import '../services/color_service.dart';
import '../widgets/svg_viewer.dart';
import 'dashboard_page.dart';

class ColoringPage extends StatefulWidget {
  final String assetPath;
  final String? title;
  final String username;
  final int userId;

  const ColoringPage({
    super.key,
    required this.assetPath,
    this.title,
    required this.username,
    required this.userId,
  });

  @override
  State<ColoringPage> createState() => _ColoringPageState();
}

class _ColoringPageState extends State<ColoringPage> {
  late final SvgService _svgService;
  final PathService _pathService = PathService();
  HitTestService? _hitTestService;
  final ColorService _colorService = ColorService();
  final DbService _db = DbService();

  bool _loading = true;
  Color? _selectedColor;
  String _currentTool = 'color';

  static const double _viewerWidth = 360;
  static const double _viewerHeight = 600;

  final GlobalKey _containerKey = GlobalKey();
  final TransformationController _transformationController =
      TransformationController();

  final Map<String, String> _originalFills = {};

  @override
  void initState() {
    super.initState();
    _svgService = SvgService(assetPath: widget.assetPath);
    _load();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _svgService.load();

    if (_svgService.doc != null) {
      _rebuildPathService();

      final imageId = widget.assetPath;
      final title = widget.title ?? imageId.split('/').last;
      final pathIds = _pathServicePathsList();

      await _db.upsertImage(imageId, title, pathIds.length);
      await _db.ensurePathsForUser(imageId, pathIds, widget.userId);

      for (final pid in pathIds) {
        _originalFills[pid] = _getOriginalFillForElement(pid);
      }

      final coloredRows =
          await _db.getColoredPathsForImage(imageId, widget.userId);
      for (final row in coloredRows) {
        final pid = row['id'] as String;
        final colorHex = (row['color'] as String?) ?? '';
        if (colorHex.isNotEmpty) {
          _svgService.applyFillToElementById(pid, colorHex);
        }
      }

      _rebuildPathService();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<String> _pathServicePathsList() =>
      _pathService.paths.keys.map((k) => k.toString()).toList();

  void _rebuildPathService() {
    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService =
        HitTestService(paths: _pathService.paths, viewBox: _svgService.viewBox);
  }

  String _getOriginalFillForElement(String id) {
    final doc = _svgService.doc;
    if (doc == null) return 'none';
    try {
      for (final XmlElement elem in doc.findAllElements('*')) {
        final attrId = elem.getAttribute('id');
        if (attrId == id) {
          final attrFill = elem.getAttribute('fill');
          if (attrFill != null && attrFill.trim().isNotEmpty) return attrFill;
          final style = elem.getAttribute('style');
          if (style != null && style.trim().isNotEmpty) {
            final entries = style
                .split(';')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty);
            for (final entry in entries) {
              if (entry.startsWith('fill:')) {
                return entry.substring('fill:'.length).trim();
              }
            }
          }
          return 'none';
        }
      }
    } catch (_) {}
    return 'none';
  }

  Future<void> _handlePointerUp(Offset globalPos) async {
    final box = _containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      debugPrint('TAP: no container render box');
      return;
    }

    // 1. Convert global -> local widget coords
    final localInContainer = box.globalToLocal(globalPos);
    debugPrint(
        'TAP: localInContainer=$localInContainer containerSize=${box.size}');

    // 2. Undo InteractiveViewer transform (zoom/pan)
    final Matrix4 matrix = _transformationController.value;
    final Matrix4 inverse = Matrix4.copy(matrix);
    inverse.invert();
    final ui.Offset untransformed =
        MatrixUtils.transformPoint(inverse, localInContainer);
    debugPrint('INVERSE: untransformed=$untransformed');

    // 3. Hit test directly with widget coords → HitTestService handles mapping
    final Size widgetSize = Size(box.size.width, box.size.height);
    final hitId = _hitTestService?.hitTest(untransformed, widgetSize);
    debugPrint('HIT: hitId=$hitId');

    String? finalHit = hitId;
    if (finalHit == null) {
      const offsets = [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
        Offset(2, 0)
      ];
      for (final off in offsets) {
        final tryPt = untransformed + off;
        final tryHit = _hitTestService?.hitTest(tryPt, widgetSize);
        if (tryHit != null) {
          finalHit = tryHit;
          debugPrint('HIT: fallback hit at offset $off -> $tryHit');
          break;
        }
      }
    }

    if (finalHit == null) {
      debugPrint('HIT: no hit found for tap.');
      return;
    }

    // 4. Apply color or erase
    if (_currentTool == 'color') {
      if (_selectedColor == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select a color first')));
        return;
      }
      final colorHex = _colorService.colorToHex(_selectedColor!);
      debugPrint('APPLY: coloring id=$finalHit with $colorHex');
      _svgService.applyFillToElementById(finalHit, colorHex);
      await _db.markPathColored(finalHit, colorHex, widget.userId);
    } else {
      final orig = _originalFills[finalHit] ?? 'none';
      debugPrint('APPLY: erasing id=$finalHit restore to $orig');
      _svgService.applyFillToElementById(finalHit, orig);
      await _db.markPathUncolored(finalHit, widget.userId);
    }

    if (_svgService.doc != null) _rebuildPathService();
    if (!mounted) return;
    setState(() {});

    final svgNow = _svgService.getSvgString() ?? '';
    if (svgNow.isNotEmpty) {
      debugPrint(
        'SVG_AFTER: ${svgNow.substring(0, 300).replaceAll("\n", "")}...',
      );
    } else {
      debugPrint('SVG_AFTER: (empty)');
    }
  }

  void _onSelectColor(Color color) {
    setState(() {
      _selectedColor = color;
      _currentTool = 'color';
    });
  }

  Future<void> _clearCanvasAll() async {
    if (_svgService.doc == null) return;
    final allIds = _pathService.paths.keys.map((k) => k.toString()).toList();
    for (final pid in allIds) {
      final orig = _originalFills[pid] ?? 'none';
      _svgService.applyFillToElementById(pid, orig);
      await _db.markPathUncolored(pid, widget.userId);
    }
    _rebuildPathService();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Canvas cleared')));
  }

  Future<void> _saveProgress() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your coloring has been saved! 🎨')));
    Navigator.of(context).pop();
  }

  void _openDashboardShortcut() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            DashboardPage(username: widget.username, userId: widget.userId)));
  }

  Widget _pillButton(
      {required VoidCallback onPressed,
      required Color color,
      required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 4,
                  offset: Offset(0, 2))
            ],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      leadingWidth: 120,
      leading: _pillButton(
        onPressed: () => Navigator.of(context).pop(),
        color: const Color(0xFF657DF6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.arrow_back, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text('Back',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      title: Text(widget.title ?? 'Coloring'),
      centerTitle: true,
      actions: [
        _pillButton(
          onPressed: _saveProgress,
          color: const Color(0xFF2FC64D),
          child: Row(children: const [
            Icon(Icons.save_alt, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text('Save',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 8),
      ],
    );

    if (_loading) {
      return Scaffold(
          appBar: appBar, body: const Center(child: CircularProgressIndicator()));
    }

    final svgString = _svgService.getSvgString() ?? '';
    if (svgString.isEmpty) {
      return Scaffold(
          appBar: appBar,
          body: const Center(child: Text('Failed to load SVG')));
    }

    final ButtonStyle toolButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 4,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Scaffold(
      appBar: appBar,
      backgroundColor: const Color(0xFFFDF2F8),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  key: _containerKey,
                  width: _viewerWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x11000000), blurRadius: 12)
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            const SizedBox(width: 48),
                            Expanded(
                                child: Text(widget.title ?? 'Coloring',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18))),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      Container(
                        width: _viewerWidth,
                        height: _viewerHeight,
                        padding: const EdgeInsets.all(10),
                        color: Colors.transparent,
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                          panEnabled: false,
                          scaleEnabled: true,
                          minScale: 1.0,
                          maxScale: 6.0,
                          boundaryMargin: EdgeInsets.zero,
                          child: SvgViewer(
                            svgString: svgString,
                            onTapAt: (globalPos) => _handlePointerUp(globalPos),
                            viewBox: _svgService.viewBox,
                            showWidgetBorder: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Tools row
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    setState(() => _currentTool = 'color'),
                                style: toolButtonStyle,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.brush_rounded, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Color'),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: _selectedColor ??
                                            Colors.transparent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    setState(() => _currentTool = 'eraser'),
                                style: toolButtonStyle,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.cleaning_services, size: 18),
                                    SizedBox(width: 8),
                                    Text('Eraser'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _clearCanvasAll,
                                style: toolButtonStyle,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.delete_outline, size: 18),
                                    SizedBox(width: 8),
                                    Text('Clear'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Palette
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _colorService.palette.map((c) {
                            final isSelected = _selectedColor == c;
                            return GestureDetector(
                              onTap: () => _onSelectColor(c),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.deepPurple
                                        : Colors.grey.shade300,
                                    width: isSelected ? 3 : 1,
                                  ),
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
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openDashboardShortcut,
        child: const Icon(Icons.dashboard),
      ),
    );
  }
}
