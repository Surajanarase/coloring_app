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
  String _currentTool = 'color';

  static const double _viewerWidth = 360;
  static const double _viewerHeight = 520;

  final GlobalKey _containerKey = GlobalKey();
  final Map<String, String> _originalFills = {};

  final TransformationController _transformationController = TransformationController();
  bool _isZoomed = false;
  AnimationController? _animController;

  String? _originalSvgString;

  static const double _progressGamma = 0.85;
  static const double _minVisibleProgress = 5.0;
  static const double _eps = 0.01;

  @override
  void initState() {
    super.initState();
    _svgService = SvgService(assetPath: widget.assetPath);
    _transformationController.addListener(_onTransformChanged);
    _load();
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _animController?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    debugPrint('[Load] ============ STARTING LOAD FOR ${widget.assetPath} ============');
    
    // Step 1: Load pristine SVG
    await _svgService.load();
    _originalSvgString = _svgService.getSvgString();
    
    if (_svgService.doc == null) {
      debugPrint('[Load] ERROR: Failed to load SVG document');
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Step 2: Capture ORIGINAL fills from pristine SVG (before any modifications)
    _captureOriginalFills();
    debugPrint('[Load] Captured ${_originalFills.length} original fills');

    // Step 3: Build paths and calculate areas
    final tmp = PathService();
    tmp.buildPathsFromDoc(_svgService.doc!);
    
    final Map<String, double> pathAreas = {};
    for (final pid in tmp.paths.keys) {
      try {
        final b = tmp.paths[pid]!.getBounds();
        final area = b.width * b.height;
        pathAreas[pid] = area.isFinite ? area : 0.0;
      } catch (_) {
        pathAreas[pid] = 0.0;
      }
    }

    final totalArea = pathAreas.values.fold<double>(0.0, (a, b) => a + b);
    final imageId = widget.assetPath;
    
    debugPrint('[Load] Total paths: ${pathAreas.length}, Total area: $totalArea');

    // Step 4: Upsert to database
    await _db.upsertImage(
      imageId, 
      widget.title ?? imageId.split('/').last, 
      pathAreas.length, 
      totalArea: totalArea
    );
    await _db.insertPathsForImage(imageId, pathAreas);

    // Step 5: Restore colored paths from database
    final coloredRows = await _db.getColoredPathsForImage(imageId);
    debugPrint('[Load] Found ${coloredRows.length} colored paths in database');
    
    int restoredCount = 0;
    for (final row in coloredRows) {
      final pid = row['id'] as String;
      final colorHex = (row['color'] as String?) ?? '';
      
      if (colorHex.isNotEmpty && colorHex != 'none') {
        _svgService.applyFillToElementById(pid, colorHex);
        restoredCount++;
        debugPrint('[Load] ✓ Restored $pid with color $colorHex');
      }
    }
    
    debugPrint('[Load] Successfully restored $restoredCount/${coloredRows.length} paths');

    // Step 6: Build paths and hit test from modified SVG
    _buildPathsAndHitTest();
    
    debugPrint('[Load] ============ LOAD COMPLETE ============');

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _captureOriginalFills() {
    _originalFills.clear();
    final doc = _svgService.doc;
    if (doc == null) return;

    for (final elem in doc.findAllElements('*')) {
      final id = elem.getAttribute('id');
      if (id == null || id.isEmpty) continue;

      final name = elem.name.local.toLowerCase();
      if (!['path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline'].contains(name)) {
        continue;
      }

      final originalFill = _getOriginalFillForElement(elem);
      _originalFills[id] = originalFill;
    }
  }

  void _buildPathsAndHitTest() {
    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService = HitTestService(
      paths: _pathService.paths, 
      viewBox: _svgService.viewBox
    );
  }

  String _getOriginalFillForElement(XmlElement elem) {
    final attrFill = elem.getAttribute('fill');
    if (attrFill != null && attrFill.trim().isNotEmpty) {
      return attrFill.trim();
    }
    
    final style = elem.getAttribute('style');
    if (style != null && style.trim().isNotEmpty) {
      for (final entry in style.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
        if (entry.startsWith('fill:')) {
          return entry.substring(5).trim();
        }
      }
    }
    
    return 'none';
  }

  Offset _computeLocalOffset(RenderBox box, Offset globalPos) => 
    box.globalToLocal(globalPos);

  Future<void> _onTapAt(Offset localPos, Size widgetSize) async {
    if (_hitTestService == null) return;
    
    final hitId = _hitTestService!.hitTest(localPos, widgetSize);
    if (hitId == null) {
      debugPrint('[Tap] No path hit');
      return;
    }

    debugPrint('[Tap] Hit path: $hitId, Tool: $_currentTool');

    if (_currentTool == 'color' && _selectedColor == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a color first!'))
      );
      return;
    }

    _tryPushSnapshot(_svgService.getSvgString());

    if (_currentTool == 'color') {
      final colorHex = _colorToHex(_selectedColor!);
      _svgService.applyFillToElementById(hitId, colorHex);
      await _db.markPathColored(hitId, colorHex, imageId: widget.assetPath);
      debugPrint('[Tap] ✓ Colored path $hitId with $colorHex');
    } else if (_currentTool == 'eraser') {
      final orig = _originalFills[hitId] ?? 'none';
      _svgService.applyFillToElementById(hitId, orig);
      await _db.markPathUncolored(hitId, imageId: widget.assetPath);
      debugPrint('[Tap] ✓ Erased path $hitId back to: $orig');
    }

    _buildPathsAndHitTest();
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
      final int r = (c.r * 255.0).round() & 0xFF;
      final int g = (c.g * 255.0).round() & 0xFF;
      final int b = (c.b * 255.0).round() & 0xFF;
      return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
    }
  }

  void _onSelectColor(Color c) {
    setState(() {
      _selectedColor = c;
      _currentTool = 'color';
    });
  }

  Future<void> _clearCanvasAll() async {
    if (_svgService.doc == null) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Canvas?'),
        content: const Text('This will remove all colors from this image. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), 
            child: const Text('Cancel')
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red), 
            child: const Text('Clear')
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    debugPrint('[Clear] Starting canvas clear for ${widget.assetPath}');
    _tryPushSnapshot(_svgService.getSvgString());
    
    final imageId = widget.assetPath;

    try {
      // Reset database first
      await _db.resetImageProgress(imageId);
      debugPrint('[Clear] Database reset complete');

      // Reload pristine SVG
      if (_originalSvgString != null) {
        _svgService.setSvgString(_originalSvgString!);
      } else {
        await _svgService.load();
        _originalSvgString = _svgService.getSvgString();
      }

      // Rebuild paths
      _buildPathsAndHitTest();

      // Re-capture original fills
      _captureOriginalFills();
      
      debugPrint('[Clear] ✓ Canvas cleared, ${_originalFills.length} paths reset');

    } catch (e, st) {
      debugPrint('[Clear] ✗ Error: $e\n$st');
    }

    if (!mounted) return;
    setState(() {});
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Canvas cleared! All progress reset to 0%'), 
        duration: Duration(seconds: 2)
      ),
    );
  }

  int _calculateDisplayPercent(double rawPercent, double coloredArea, double totalArea) {
    if (totalArea > 0 && (coloredArea + _eps >= totalArea)) {
      return 100;
    }
    
    if (rawPercent >= 99.0) {
      return 100;
    }
    
    if (rawPercent <= 0.0) return 0;

    final normalized = (rawPercent / 100.0).clamp(0.0, 1.0);
    double boosted = math.pow(normalized, _progressGamma).toDouble() * 100.0;

    if (rawPercent > 0.5 && boosted < _minVisibleProgress) {
      boosted = _minVisibleProgress;
    }

    if (rawPercent >= 30.0 && rawPercent < 95.0) {
      final midRangeBoost = math.pow(normalized, _progressGamma * 0.95).toDouble() * 100.0;
      final blendFactor = 0.15;
      boosted = boosted * (1 - blendFactor) + midRangeBoost * blendFactor;
    }

    if (boosted >= 99.0 && rawPercent < 97.0) {
      boosted = 98.0;
    }
    
    if (boosted > 98.0 && rawPercent < 98.0) {
      boosted = 98.0;
    }

    return boosted.round().clamp(0, 99);
  }

  Future<void> _saveProgress() async {
    debugPrint('[Save] ============ STARTING SAVE FOR ${widget.assetPath} ============');
    
    // Sync database with current SVG state
    await _syncDbWithCurrentSvgState();

    // Calculate display percentage
    final imageId = widget.assetPath;
    final coloredAreaQuery = await _db.getDashboardRows();
    final row = coloredAreaQuery.firstWhere(
      (r) => r['id'] == imageId, 
      orElse: () => {}
    );
    
    int displayPercent = 0;
    
    if (row.isNotEmpty) {
      final totalArea = (row['total_area'] as num?)?.toDouble() ?? 0.0;
      final coloredArea = (row['colored_area'] as num?)?.toDouble() ?? 0.0;
      
      final rawPercent = totalArea > 0 ? ((coloredArea / totalArea) * 100) : 0.0;
      displayPercent = _calculateDisplayPercent(rawPercent, coloredArea, totalArea);
      
      await _db.updateImageDisplayPercent(imageId, displayPercent.toDouble());
      
      debugPrint('[Save] ✓ Saved: display=$displayPercent%, raw=${rawPercent.toStringAsFixed(2)}%, '
          'colored=${coloredArea.toStringAsFixed(2)}, total=${totalArea.toStringAsFixed(2)}');
    }

    debugPrint('[Save] ============ SAVE COMPLETE ============');

    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Progress saved! $displayPercent% complete'), 
        duration: const Duration(seconds: 2)
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _syncDbWithCurrentSvgState() async {
    final doc = _svgService.doc;
    if (doc == null) {
      debugPrint('[Sync] ERROR: No SVG document');
      return;
    }

    debugPrint('[Sync] Starting DB sync...');
    int coloredCount = 0;
    int uncoloredCount = 0;
    int skippedCount = 0;

    for (final elem in doc.findAllElements('*')) {
      final id = elem.getAttribute('id');
      if (id == null || id.isEmpty) {
        skippedCount++;
        continue;
      }

      final name = elem.name.local.toLowerCase();
      if (!['path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline'].contains(name)) {
        skippedCount++;
        continue;
      }

      // Get current fill from SVG
      final currentFill = _getOriginalFillForElement(elem);
      
      // Get original fill
      final originalFill = _originalFills[id] ?? 'none';
      final imageId = widget.assetPath;

      // Determine if colored
      final isColored = _isPathColored(currentFill, originalFill);

      if (isColored) {
        await _db.markPathColored(id, currentFill, imageId: imageId);
        coloredCount++;
      } else {
        await _db.markPathUncolored(id, imageId: imageId);
        uncoloredCount++;
      }
    }

    debugPrint('[Sync] ✓ Complete: $coloredCount colored, $uncoloredCount uncolored, $skippedCount skipped');
  }

  bool _isPathColored(String currentFill, String originalFill) {
    // Normalize fills
    final current = currentFill.toLowerCase().trim();
    final original = originalFill.toLowerCase().trim();
    
    // Not colored if empty or none
    if (current.isEmpty || current == 'none' || current == 'transparent') {
      return false;
    }
    
    // Not colored if same as original
    if (current == original) {
      return false;
    }
    
    // Check if it's a valid color (hex or rgb)
    if (current.startsWith('#') || current.startsWith('rgb')) {
      return true;
    }
    
    return false;
  }

  void _undoOneStep() async {
    String? xml;
    try {
      xml = _colorService.popSnapshot();
    } catch (_) {}
    
    if (xml == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to undo'))
      );
      return;
    }

    _svgService.setSvgString(xml);
    _buildPathsAndHitTest();
    await _syncDbWithCurrentSvgState();

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Undone one step'))
    );
  }

  void _animateResetZoom() {
    if (_transformationController.value.isIdentity()) {
      setState(() => _isZoomed = false);
      return;
    }

    _animController?.dispose();
    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 260)
    );
    
    final tween = Matrix4Tween(
      begin: Matrix4.copy(_transformationController.value), 
      end: Matrix4.identity()
    );
    
    final animation = tween.animate(
      CurvedAnimation(parent: _animController!, curve: Curves.easeOut)
    );
    
    animation.addListener(() => _transformationController.value = animation.value);
    
    _animController!.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
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
    required bool active
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
            width: active ? 1.8 : 1.0
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000), 
              blurRadius: 6, 
              offset: Offset(0, 4)
            )
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
                shape: BoxShape.circle
              ),
              child: Icon(
                icon, 
                size: 18, 
                color: active ? Colors.white : Colors.black54
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label, 
              style: TextStyle(
                fontWeight: FontWeight.w700, 
                color: active ? Colors.deepPurple : Colors.black87
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleHeaderButton({
    required VoidCallback onTap, 
    required IconData icon, 
    required List<Color> gradient
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient, 
            begin: Alignment.topLeft, 
            end: Alignment.bottomRight
          ),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000), 
              blurRadius: 8, 
              offset: Offset(0, 4)
            )
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
              end: Alignment.bottomRight
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
        ),
        title: Text(
          widget.title ?? widget.assetPath.split('/').last, 
          style: const TextStyle(
            fontSize: 20, 
            fontWeight: FontWeight.w800, 
            color: Colors.black87
          )
        ),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: _circleHeaderButton(
            onTap: () => Navigator.of(context).pop(), 
            icon: Icons.arrow_back, 
            gradient: const [Color(0xFFFF8A80), Color(0xFFFFC1A7)]
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _circleHeaderButton(
              onTap: _saveProgress, 
              icon: Icons.save, 
              gradient: const [Color(0xFF6EE7B7), Color(0xFF4DD0E1)]
            ),
          )
        ],
      ),
    );

    if (_loading) {
      return Scaffold(
        appBar: header, 
        body: const Center(child: CircularProgressIndicator())
      );
    }

    final svgString = _svgService.getSvgString() ?? '';
    if (svgString.isEmpty) {
      return Scaffold(
        appBar: header, 
        body: const Center(child: Text('Failed to load SVG'))
      );
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end, 
                  children: [
                    GestureDetector(
                      onTap: _undoOneStep,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFF59D), Color(0xFFFFCC80)], 
                            begin: Alignment.topLeft, 
                            end: Alignment.bottomRight
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000), 
                              blurRadius: 8, 
                              offset: Offset(0, 4)
                            )
                          ],
                        ),
                        child: const Icon(Icons.undo, color: Colors.black87),
                      ),
                    ),
                  ]
                ),
              ),

              const SizedBox(height: 8),

              Center(
                child: SizedBox(
                  width: effectiveWidth,
                  height: _viewerHeight + 32,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          key: _containerKey,
                          width: effectiveWidth,
                          height: _viewerHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.grey.shade200, 
                              width: 1.4
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000), 
                                blurRadius: 12, 
                                offset: Offset(0, 6)
                              )
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
                              child: SvgViewer(
                                svgString: svgString, 
                                viewBox: _svgService.viewBox, 
                                showWidgetBorder: false
                              ),
                            ),
                          ),
                        ),
                      ),

                      if (_isZoomed)
                        Positioned(
                          top: _viewerHeight - 20,
                          left: (screenW - 40) / 2,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _animateResetZoom,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x22000000), 
                                    blurRadius: 6, 
                                    offset: Offset(0, 2)
                                  )
                                ],
                              ),
                              child: const Icon(
                                Icons.center_focus_strong, 
                                size: 18, 
                                color: Colors.black87
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

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
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF0E9FF), Color(0xFFE8F7FF)], 
                        begin: Alignment.topLeft, 
                        end: Alignment.bottomRight
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x11000000), 
                          blurRadius: 10, 
                          offset: Offset(0, 6)
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: pillWidth, 
                          child: _toolPill(
                            onTap: () => setState(() => _currentTool = 'color'), 
                            icon: Icons.color_lens, 
                            label: 'Color', 
                            active: _currentTool == 'color'
                          )
                        ),
                        SizedBox(width: pillSpacing),
                        SizedBox(
                          width: pillWidth, 
                          child: _toolPill(
                            onTap: () => setState(() => _currentTool = 'eraser'), 
                            icon: Icons.cleaning_services_outlined, 
                            label: 'Eraser', 
                            active: _currentTool == 'eraser'
                          )
                        ),
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

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
                child: Container(
                  width: effectiveWidth,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFF0F4), Color(0xFFEFFCF4)], 
                      begin: Alignment.topLeft, 
                      end: Alignment.bottomRight
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x11000000), 
                        blurRadius: 10, 
                        offset: Offset(0, 6)
                      )
                    ],
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
                                ? [const BoxShadow(
                                    color: Color(0x33000000), 
                                    blurRadius: 8, 
                                    offset: Offset(0, 4)
                                  )] 
                                : [const BoxShadow(
                                    color: Color(0x11000000), 
                                    blurRadius: 4
                                  )],
                              border: Border.all(
                                color: isSelected ? Colors.deepPurple : Colors.grey.shade200, 
                                width: isSelected ? 3.0 : 1.0
                              ),
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