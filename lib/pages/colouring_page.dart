// lib/pages/colouring_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../services/db_service.dart';
import '../services/svg_service.dart';
import '../services/path_service.dart';
import '../services/hit_test_service.dart';
import '../services/color_service.dart';
import '../widgets/svg_viewer.dart';

class ColoringPage extends StatefulWidget {
  final String assetPath;
  final String? title;
  final String username;

  const ColoringPage({
    super.key,
    required this.assetPath,
    this.title,
    required this.username,
  });

  @override
  State<ColoringPage> createState() => _ColoringPageState();
}

class _ColoringPageState extends State<ColoringPage> with SingleTickerProviderStateMixin {
  late final SvgService _svgService;
  final PathService _pathService = PathService();
  HitTestService? _hitTestService;
  final ColorService _colorService = ColorService();
  final DbService _db = DbService();

  bool _loading = true;
  Color? _selectedColor;
  String _currentTool = 'color'; // 'color' | 'eraser' | 'clear'

  static const double _viewerWidth = 360;
  static const double _viewerHeight = 520;

  final GlobalKey _containerKey = GlobalKey();
  final Map<String, String> _originalFills = {};

  // transformation controller for InteractiveViewer
  final TransformationController _transformationController = TransformationController();

  // zoom state & animation controller for reset
  bool _isZoomed = false;
  AnimationController? _animController;

  @override
  void initState() {
    super.initState();
    _svgService = SvgService(assetPath: widget.assetPath);

    // listen for transform changes to track zoom state (used to show/hide reset button and enable pan)
    _transformationController.addListener(_onTransformChanged);

    _load();
  }

  void _onTransformChanged() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final newIsZoomed = currentScale > 1.01; // small epsilon
    if (newIsZoomed != _isZoomed) setState(() => _isZoomed = newIsZoomed);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _animController?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _svgService.load();

    if (_svgService.doc != null) {
      _buildPathsAndHitTest();

      final imageId = widget.assetPath;
      final pathIds = _pathService.paths.keys.map((k) => k.toString()).toList();
      await _db.upsertImage(
          imageId, widget.title ?? imageId.split('/').last, pathIds.length);
      await _db.insertPathsForImage(imageId, pathIds);

      for (final pid in pathIds) {
        _originalFills[pid] = _getOriginalFillForElement(pid);
      }

      final coloredRows = await _db.getColoredPathsForImage(imageId);
      for (final row in coloredRows) {
        final pid = row['id'] as String;
        final colorHex = (row['color'] as String?) ?? '';
        if (colorHex.isNotEmpty) {
          _svgService.applyFillToElementById(pid, colorHex);
        }
      }

      _buildPathsAndHitTest();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _buildPathsAndHitTest() {
    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService =
        HitTestService(paths: _pathService.paths, viewBox: _svgService.viewBox);
  }

  String _getOriginalFillForElement(String id) {
    final doc = _svgService.doc;
    if (doc == null) return 'none';
    try {
      for (final XmlElement elem in doc.findAllElements('*')) {
        if (elem.getAttribute('id') == id) {
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

  Offset _computeLocalOffset(RenderBox containerBox, Offset globalPosition) {
    return containerBox.globalToLocal(globalPosition);
  }

  /// Tap handler: converts the tapped point (in the widget's coordinate space)
  /// into the SVG child local coordinates by applying the inverse of the
  /// current InteractiveViewer transform and then calls the existing logic.
  Future<void> _onTapAt(Offset localPos, Size widgetSize) async {
    if (_hitTestService == null) return;
    final hitId = _hitTestService!.hitTest(localPos, widgetSize);
    if (hitId == null) return;

    if (_currentTool == 'color' && _selectedColor == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick a color first!')));
      return;
    }

    _tryPushSnapshot(_svgService.getSvgString());

    if (_currentTool == 'color') {
      final colorHex = _colorToHex(_selectedColor!);
      _svgService.applyFillToElementById(hitId, colorHex);
      await _db.markPathColored(hitId, colorHex);
    } else if (_currentTool == 'eraser') {
      final orig = _originalFills[hitId] ?? 'none';
      _svgService.applyFillToElementById(hitId, orig);
      await _db.markPathUncolored(hitId);
    }

    if (_svgService.doc != null) {
      _buildPathsAndHitTest();
    }

    if (!mounted) return;
    setState(() {});
  }

  void _tryPushSnapshot(String? xml) {
    try {
      _colorService.pushSnapshot(xml);
    } catch (_) {}
  }

  String _colorToHex(Color c) {
    try {
      return _colorService.colorToHex(c);
    } catch (_) {
      final int r = (c.r * 255).round() & 0xff;
      final int g = (c.g * 255).round() & 0xff;
      final int b = (c.b * 255).round() & 0xff;
      final rr = r.toRadixString(16).padLeft(2, '0');
      final gg = g.toRadixString(16).padLeft(2, '0');
      final bb = b.toRadixString(16).padLeft(2, '0');
      return '#$rr$gg$bb';
    }
  }

  // This is referenced by palette grid taps.
  void _onSelectColor(Color color) {
    setState(() {
      _selectedColor = color;
      _currentTool = 'color';
    });
  }

  // This is referenced by the Clear tool pill
  Future<void> _clearCanvasAll() async {
    if (_svgService.doc == null) return;
    _tryPushSnapshot(_svgService.getSvgString());

    final allIds = _pathService.paths.keys.map((k) => k.toString()).toList();
    for (final pid in allIds) {
      final orig = _originalFills[pid] ?? 'none';
      _svgService.applyFillToElementById(pid, orig);
      await _db.markPathUncolored(pid);
    }

    _buildPathsAndHitTest();

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Canvas cleared')));
  }

  Future<void> _saveProgress() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved! 🎉')));
    Navigator.of(context).pop();
  }

  Future<void> _restoreDbFromSvg() async {
    final doc = _svgService.doc;
    if (doc == null) return;
    for (final elem in doc.findAllElements('*')) {
      final id = elem.getAttribute('id');
      if (id == null || id.isEmpty) continue;
      String? fill;
      final f = elem.getAttribute('fill');
      if (f != null && f.trim().isNotEmpty) {
        fill = f.trim();
      } else {
        final style = elem.getAttribute('style');
        if (style != null && style.trim().isNotEmpty) {
          final entries = style
              .split(';')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty);
          for (final entry in entries) {
            if (entry.startsWith('fill:')) {
              fill = entry.substring('fill:'.length).trim();
              break;
            }
          }
        }
      }
      if (fill == null || fill.isEmpty || fill == 'none') {
        await _db.markPathUncolored(id);
      } else {
        await _db.markPathColored(id, fill);
      }
    }
  }

  void _undoOneStep() async {
    String? xml;
    try {
      xml = _colorService.popSnapshot();
    } catch (_) {
      xml = null;
    }

    if (xml == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nothing to undo')));
      return;
    }

    _svgService.setSvgString(xml);
    _buildPathsAndHitTest();

    await _restoreDbFromSvg();

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Undone one step')));
  }

  // animate reset robustly and ensure identity at end
  void _animateResetZoom() {
    if (_transformationController.value.isIdentity()) {
      setState(() => _isZoomed = false);
      return;
    }

    _animController?.dispose();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

    final begin = Matrix4.copy(_transformationController.value);
    final end = Matrix4.identity();
    final tween = Matrix4Tween(begin: begin, end: end);
    final animation = tween.animate(CurvedAnimation(parent: _animController!, curve: Curves.easeOut));

    animation.addListener(() {
      _transformationController.value = animation.value;
    });

    _animController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // ensure exact identity and hide reset UI
        _transformationController.value = Matrix4.identity();
        _animController?.dispose();
        _animController = null;
        setState(() => _isZoomed = false);
      }
    });

    _animController!.forward();
  }

  Widget _toolPill({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFFBED) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active ? Colors.deepPurple : Colors.grey.shade300,
              width: active ? 1.8 : 1.0),
          boxShadow: const [
            BoxShadow(
                color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 4))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: active ? Colors.deepPurple : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 18, color: active ? Colors.white : Colors.black54),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.deepPurple : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleHeaderButton(
      {required VoidCallback onTap, required IconData icon, required List<Color> gradient}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = PreferredSize(
      preferredSize: const Size.fromHeight(96),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFE8F2), Color(0xFFE8F7FF), Color(0xFFEFF7EE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
        ),
        title: const Text('Maria likes to play',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87)),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: _circleHeaderButton(onTap: () => Navigator.of(context).pop(), icon: Icons.arrow_back, gradient: const [Color(0xFFFF8A80), Color(0xFFFFC1A7)]),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _circleHeaderButton(onTap: _saveProgress, icon: Icons.save, gradient: const [Color(0xFF6EE7B7), Color(0xFF4DD0E1)]),
          )
        ],
      ),
    );

    if (_loading) {
      return Scaffold(appBar: header, body: const Center(child: CircularProgressIndicator()));
    }

    final svgString = _svgService.getSvgString() ?? '';
    if (svgString.isEmpty) {
      return Scaffold(appBar: header, body: const Center(child: Text('Failed to load SVG')));
    }

    const horizontalMargin = 12.0;
    final screenW = MediaQuery.of(context).size.width;
    final effectiveWidth = math.min(_viewerWidth, screenW - 2 * horizontalMargin);

    return Scaffold(
      appBar: header,
      backgroundColor: const Color(0xFFFFFBFE),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  GestureDetector(
                    onTap: _undoOneStep,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFFFFF59D), Color(0xFFFFCC80)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))],
                      ),
                      child: const Icon(Icons.undo, color: Colors.black87),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              // Stack that contains the image container and the reset button positioned just under it (centered)
              Center(
                child: SizedBox(
                  width: effectiveWidth,
                  // height contains image height plus a small overlap area for the reset button
                  height: _viewerHeight + 32,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Image container positioned at top
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          key: _containerKey,
                          width: effectiveWidth,
                          height: _viewerHeight,
                          padding: EdgeInsets.zero,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.grey.shade200, width: 1.4),
                            boxShadow: const [
                              BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 6))
                            ],
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) {
                              final box = _containerKey.currentContext?.findRenderObject() as RenderBox?;
                              if (box == null) return;
                              final local = _computeLocalOffset(box, details.globalPosition);
                              final inv = Matrix4.copy(_transformationController.value)..invert();
                              final scene = MatrixUtils.transformPoint(inv, local);
                              _onTapAt(scene, box.size);
                            },
                            child: InteractiveViewer(
                              transformationController: _transformationController,
                              panEnabled: _isZoomed,
                              scaleEnabled: true,
                              minScale: 1.0,
                              maxScale: 6.0,
                              boundaryMargin: const EdgeInsets.all(80),
                              child: SvgViewer(svgString: svgString, viewBox: _svgService.viewBox, showWidgetBorder: false),
                            ),
                          ),
                        ),
                      ),

                      // Reset button: centered horizontally, positioned slightly overlapping the image bottom
                      if (_isZoomed)
                        Positioned(
                          top: _viewerHeight - 20, // overlaps bottom edge of image container
                          left: (screenW - 40) / 2, // center relative to screen (matches image center)
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              // single tap resets immediately
                              _animateResetZoom();
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
                              ),
                              child: const Icon(Icons.center_focus_strong, size: 18, color: Colors.black87),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // TOOLS CARD (unchanged) - note: Eraser is the middle pill, reset button visually sits above it
              Builder(builder: (context) {
                final pillSpacing = 8.0;
                final totalPadding = 2 * horizontalMargin + 16;
                final availableWidth = effectiveWidth - totalPadding - (pillSpacing * 2);
                final pillWidth = (availableWidth / 3).clamp(110.0, 220.0);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
                  child: Container(
                    width: effectiveWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFF0E9FF), Color(0xFFE8F7FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 6))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: pillWidth, child: _toolPill(onTap: () => setState(() => _currentTool = 'color'), icon: Icons.color_lens, label: 'Color', active: _currentTool == 'color')),
                        SizedBox(width: pillSpacing),
                        SizedBox(width: pillWidth, child: _toolPill(onTap: () => setState(() => _currentTool = 'eraser'), icon: Icons.cleaning_services_outlined, label: 'Eraser', active: _currentTool == 'eraser')),
                        SizedBox(width: pillSpacing),
                        SizedBox(
                          width: pillWidth,
                          child: _toolPill(
                            onTap: () {
                              setState(() => _currentTool = 'clear');
                              _clearCanvasAll();
                            },
                            icon: Icons.delete_outline,
                            label: 'Clear',
                            active: _currentTool == 'clear',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Palette
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
                child: Container(
                  width: effectiveWidth,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFF0F4), Color(0xFFEFFCF4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 6))],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44 * 2 + 12,
                    child: GridView.count(
                      crossAxisCount: 7,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1,
                      padding: EdgeInsets.zero,
                      children: _colorService.palette.map((c) {
                        final isSelected = _selectedColor == c;
                        return GestureDetector(
                          onTap: () => _onSelectColor(c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: isSelected
                                  ? [const BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0,4))]
                                  : [const BoxShadow(color: Color(0x11000000), blurRadius: 4)],
                              border: Border.all(color: isSelected ? Colors.deepPurple : Colors.grey.shade200, width: isSelected ? 3.0 : 1.0),
                            ),
                            child: ClipOval(child: Container(color: c)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
    );
  }
}
