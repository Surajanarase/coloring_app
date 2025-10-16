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

  final GlobalKey _containerKey = GlobalKey();
  final Map<String, String> _originalFills = {};

  final TransformationController _transformationController = TransformationController();
    // keep current viewer size to compute clamping bounds
  Size _viewerSize = Size.zero;

  bool _isZoomed = false;
  AnimationController? _animController;

  String? _originalSvgString;

  static const double _progressGamma = 0.85;
  static const double _minVisibleProgress = 5.0;
  static const double _eps = 0.01;

  // Enhanced gesture handling
  final ScrollController _scrollController = ScrollController();
  bool _isScaleGesture = false;
  int _pointerCount = 0;
  // ignore: unused_field
  Offset? _lastFocalPoint;
  double _lastScale = 1.0;

  @override
  void initState() {
    super.initState();
    _db.setCurrentUser(widget.username);
    _svgService = SvgService(assetPath: widget.assetPath);
    _transformationController.addListener(_onTransformChanged);
    _load();
  }

    void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);

    // When zoomed (or after panning) keep the translation clamped so the image
    // cannot be moved outside the viewer box. This preserves your existing
    // zoom detection logic while enforcing the panning bounds (old-file behavior).
    _clampTransform();
  }
    void _clampTransform() {
  // if viewer size is unknown, nothing to do yet
  if (_viewerSize == Size.zero) return;

  final matrix = Matrix4.copy(_transformationController.value);
  final scale = matrix.getMaxScaleOnAxis();

  // Only clamp when zoomed in
  if (scale <= 1.01) return;

  // translation components
  final tx = matrix.storage[12];
  final ty = matrix.storage[13];

  // scaled content size
  final contentW = _viewerSize.width * scale;
  final contentH = _viewerSize.height * scale;

  double minTx, maxTx, minTy, maxTy;

  // horizontal bounds - CORRECTED LOGIC
  if (contentW > _viewerSize.width) {
    final diffX = (contentW - _viewerSize.width);
    maxTx = 0.0;  // Right edge at container edge
    minTx = -diffX;  // Left edge limit
  } else {
    minTx = maxTx = 0.0;
  }

  // vertical bounds - CORRECTED LOGIC
  if (contentH > _viewerSize.height) {
    final diffY = (contentH - _viewerSize.height);
    maxTy = 0.0;  // Top edge at container edge
    minTy = -diffY;  // Bottom edge limit
  } else {
    minTy = maxTy = 0.0;
  }

  // clamp translations
  final clampedTx = tx.clamp(minTx, maxTx);
  final clampedTy = ty.clamp(minTy, maxTy);

  // only set controller if there is a difference to avoid noisy updates
  if (clampedTx != tx || clampedTy != ty) {
    matrix.setTranslationRaw(clampedTx, clampedTy, 0.0);
    _transformationController.value = matrix;
  }
}


  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _animController?.dispose();
    _transformationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    debugPrint('[Load] ============ STARTING LOAD FOR ${widget.assetPath} ============');

    await _svgService.load();
    _originalSvgString = _svgService.getSvgString();

    if (_svgService.doc == null) {
      debugPrint('[Load] ERROR: Failed to load SVG document');
      if (mounted) setState(() => _loading = false);
      return;
    }

    _captureOriginalFills();
    debugPrint('[Load] Captured ${_originalFills.length} original fills');

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

    final allAreas = pathAreas.values.where((a) => a > 0).toList();
    if (allAreas.isNotEmpty) {
      final avgArea = allAreas.fold<double>(0.0, (a, b) => a + b) / allAreas.length;
      final minSignificantArea = avgArea * 0.001;
      
      final filteredAreas = <String, double>{};
      int filteredCount = 0;
      for (final entry in pathAreas.entries) {
        if (entry.value >= minSignificantArea) {
          filteredAreas[entry.key] = entry.value;
        } else {
          filteredCount++;
        }
      }
      
      if (filteredCount > 0) {
        debugPrint('[Load] Filtered out $filteredCount tiny paths (< ${minSignificantArea.toStringAsFixed(2)} area)');
        pathAreas.clear();
        pathAreas.addAll(filteredAreas);
      }
    }

    final totalArea = pathAreas.values.fold<double>(0.0, (a, b) => a + b);
    final imageId = widget.assetPath;

    debugPrint('[Load] Total paths: ${pathAreas.length}, Total area: $totalArea');

    await _db.upsertImage(
      imageId,
      widget.title ?? imageId.split('/').last,
      pathAreas.length,
      totalArea: totalArea,
    );
    await _db.insertPathsForImage(imageId, pathAreas);

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

    _buildPathsAndHitTest();

    debugPrint('[Load] ============ LOAD COMPLETE ============');
    

    

    if (!mounted) return;

     // ensure transform is clamped to initial viewer bounds (keeps image fitted)
    _clampTransform();

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
      viewBox: _svgService.viewBox,
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

  String _getComputedFillForElement(XmlElement elem) {
    XmlElement? cur = elem;
    while (cur != null) {
      final attr = cur.getAttribute('fill');
      if (attr != null && attr.trim().isNotEmpty) return attr.trim();

      final style = cur.getAttribute('style');
      if (style != null && style.trim().isNotEmpty) {
        for (final entry in style.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
          if (entry.startsWith('fill:')) {
            return entry.substring(5).trim();
          }
        }
      }

      final parent = cur.parent;
      if (parent is XmlElement) {
        cur = parent;
      } else {
        cur = null;
      }
    }
    return 'none';
  }

  Offset _computeLocalOffset(RenderBox box, Offset globalPos) => box.globalToLocal(globalPos);

  Future<void> _onTapAt(Offset localPos, Size widgetSize) async {
  if (_hitTestService == null) return;

  // CRITICAL FIX: Transform tap position through inverse matrix when zoomed
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
      final int r = (c.r * 255.0).round() & 0xff;
      final int g = (c.g * 255.0).round() & 0xff;
      final int b = (c.b * 255.0).round() & 0xff;
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    debugPrint('[Clear] Starting canvas clear for ${widget.assetPath}');
    _tryPushSnapshot(_svgService.getSvgString());

    final imageId = widget.assetPath;

    try {
      await _db.resetImageProgress(imageId);
      debugPrint('[Clear] Database reset complete');

      if (_originalSvgString != null) {
        _svgService.setSvgString(_originalSvgString!);
      } else {
        await _svgService.load();
        _originalSvgString = _svgService.getSvgString();
      }

      _buildPathsAndHitTest();
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
        duration: Duration(seconds: 2),
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

    await _syncDbWithCurrentSvgState();

    final imageId = widget.assetPath;
    final coloredAreaQuery = await _db.getDashboardRows();
    final row = coloredAreaQuery.firstWhere((r) => r['id'] == imageId, orElse: () => {});

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
        duration: const Duration(seconds: 2),
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
    int skippedCount = 0;

    final imageId = widget.assetPath;
    final allPathRows = await _db.getPathsForImage(imageId);
    final validPathIds = allPathRows.map((r) => r['id'] as String).toSet();

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

      if (!validPathIds.contains(id)) {
        skippedCount++;
        continue;
      }

      final currentFillRaw = _getComputedFillForElement(elem);
      final originalFill = _originalFills[id] ?? 'none';

      final bool isColored = _isPathColored(currentFillRaw, originalFill);

      if (isColored) {
        final toStore = _normalizeColor(currentFillRaw) ?? currentFillRaw;
        await _db.markPathColored(id, toStore, imageId: imageId);
        coloredCount++;
      } else {
        skippedCount++;
      }
    }

    debugPrint('[Sync] ✓ Complete: $coloredCount colored, $skippedCount skipped (not auto-uncolored)');
  }

  String? _normalizeColor(String? raw) {
    if (raw == null) return null;
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) return null;
    if (s == 'none' || s == 'transparent') return null;

    final rgb = RegExp(r'rgb\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)').firstMatch(s);
    if (rgb != null) {
      final r = int.parse(rgb.group(1)!).clamp(0, 255);
      final g = int.parse(rgb.group(2)!).clamp(0, 255);
      final b = int.parse(rgb.group(3)!).clamp(0, 255);
      return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
    }

    final rgba = RegExp(r'rgba\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*[\d.]+\s*\)').firstMatch(s);
    if (rgba != null) {
      final r = int.parse(rgba.group(1)!).clamp(0, 255);
      final g = int.parse(rgba.group(2)!).clamp(0, 255);
      final b = int.parse(rgba.group(3)!).clamp(0, 255);
      return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
    }

    final hexShort = RegExp(r'^#([0-9a-f]{3})$').firstMatch(s);
    if (hexShort != null) {
      final h = hexShort.group(1)!;
      final r = h[0] + h[0];
      final g = h[1] + h[1];
      final b = h[2] + h[2];
      return '#$r$g$b';
    }

    final hexFull = RegExp(r'^#([0-9a-f]{6})$').firstMatch(s);
    if (hexFull != null) return '#${hexFull.group(1)!}';

    final colorNames = {
      'black': '#000000',
      'white': '#ffffff',
      'red': '#ff0000',
      'green': '#008000',
      'blue': '#0000ff',
      'yellow': '#ffff00',
      'cyan': '#00ffff',
      'magenta': '#ff00ff',
      'gray': '#808080',
      'grey': '#808080',
      'silver': '#c0c0c0',
      'maroon': '#800000',
      'olive': '#808000',
      'lime': '#00ff00',
      'aqua': '#00ffff',
      'teal': '#008080',
      'navy': '#000080',
      'fuchsia': '#ff00ff',
      'purple': '#800080',
      'orange': '#ffa500',
      'pink': '#ffc0cb',
      'brown': '#a52a2a',
    };

    if (colorNames.containsKey(s)) {
      return colorNames[s]!;
    }

    return s;
  }

  bool _isPathColored(String currentFill, String originalFill) {
    final nCurr = _normalizeColor(currentFill);
    final nOrig = _normalizeColor(originalFill);

    if (nCurr == null || nCurr.isEmpty) return false;

    if (nOrig != null && nCurr == nOrig) return false;

    if (nOrig == null) return true;

    return true;
  }

  void _undoOneStep() async {
    String? xml;
    try {
      xml = _colorService.popSnapshot();
    } catch (_) {}

    if (xml == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to undo')));
      return;
    }

    _svgService.setSvgString(xml);
    _buildPathsAndHitTest();
    await _syncDbWithCurrentSvgState();

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Undone one step')));
  }

  void _animateResetZoom() {
    if (_transformationController.value.isIdentity()) {
      setState(() => _isZoomed = false);
      return;
    }

    _animController?.dispose();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    final tween = Matrix4Tween(begin: Matrix4.copy(_transformationController.value), end: Matrix4.identity());

    final animation = tween.animate(CurvedAnimation(parent: _animController!, curve: Curves.easeOut));

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
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFFBED) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? Colors.deepPurple : Colors.grey.shade300, width: active ? 1.8 : 1.0),
          boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 4))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: active ? Colors.deepPurple : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(icon, size: 16, color: active ? Colors.white : Colors.black54),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: active ? Colors.deepPurple : Colors.black87,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _circleHeaderButton({
    required VoidCallback onTap,
    required IconData icon,
    required List<Color> gradient,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))],
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
        title: Text(widget.title ?? widget.assetPath.split('/').last,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87)),
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

    return Scaffold(
      appBar: header,
      backgroundColor: const Color(0xFFFFFBFE),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            

            final horizontalPadding = screenWidth * 0.03;
            final availableWidth = screenWidth - (2 * horizontalPadding);
            
            final viewerWidth = math.min(availableWidth, screenWidth * 0.95);
            // NOTE: removed the extra fixed +32 padding on viewer height to avoid overflow on small screens
            final viewerHeight = math.min(screenHeight * 0.80, viewerWidth * 1.6);
             // keep current viewer size for clamping logic (no setState — value-only)
            _viewerSize = Size(viewerWidth, viewerHeight);

            
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Only block scroll when actively zoomed or during scale gesture
                if (_isScaleGesture) {
                  return true;
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: _isScaleGesture 
                    ? const NeverScrollableScrollPhysics() 
                    : const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    SizedBox(height: screenHeight * 0.015),
                    
                    // Undo button
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))],
                              ),
                              child: const Icon(Icons.undo, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.005),

                    // SVG Viewer with ENHANCED smooth zoom
                    Center(
                      child: SizedBox(
                        width: viewerWidth,
                        // use viewerHeight exactly to avoid unexpected overflow on small devices
                        height: viewerHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                key: _containerKey,
                                width: viewerWidth,
                                height: viewerHeight,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.grey.shade200, width: 1.4),
                                  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 6))],
                                ),
                                child: Listener(
                                  onPointerDown: (event) {
                                    _pointerCount++;
                                    debugPrint('[Gesture] Pointer down: $_pointerCount pointers');
                                    
                                    // Two or more fingers = scale gesture
                                    if (_pointerCount >= 2) {
                                      setState(() {
                                        _isScaleGesture = true;
                                      });
                                      debugPrint('[Gesture] Scale gesture started');
                                    }
                                  },
                                  onPointerUp: (event) {
                                    _pointerCount--;
                                    debugPrint('[Gesture] Pointer up: $_pointerCount pointers remaining');
                                    
                                    // Reset when all fingers lifted
                                    if (_pointerCount <= 0) {
                                      _pointerCount = 0;
                                      setState(() {
                                        _isScaleGesture = false;
                                      });
                                      _lastFocalPoint = null;
                                      _lastScale = 1.0;
                                      debugPrint('[Gesture] All fingers lifted, scale gesture ended');
                                    }
                                  },
                                  onPointerCancel: (event) {
                                    _pointerCount = math.max(0, _pointerCount - 1);
                                    if (_pointerCount <= 0) {
                                      _pointerCount = 0;
                                      setState(() {
                                        _isScaleGesture = false;
                                      });
                                      _lastFocalPoint = null;
                                      _lastScale = 1.0;
                                    }
                                  },
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) {
  // Only block taps during active scale gesture (two fingers)
  if (_isScaleGesture) return;
  
  final box = _containerKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return;
  
  // Get local position
  final local = _computeLocalOffset(box, details.globalPosition);
  
  // Transform through inverse matrix to get SVG coordinates
  final inv = Matrix4.copy(_transformationController.value);
  try {
    inv.invert();
    final scene = MatrixUtils.transformPoint(inv, local);
    debugPrint('[Tap] Local: $local → Scene: $scene (scale: ${_transformationController.value.getMaxScaleOnAxis().toStringAsFixed(2)})');
    _onTapAt(scene, box.size);
  } catch (e) {
    debugPrint('[Tap] Matrix invert failed: $e');
    _onTapAt(local, box.size);
  }
},
                                   child: InteractiveViewer(
                                      transformationController: _transformationController,
                                      panEnabled:_isZoomed, // Always allow panning
                                      scaleEnabled: true, // Always allow scale
                                      minScale: 1.0,
                                      maxScale: 6.0,
                                      boundaryMargin: EdgeInsets.zero, // No extra boundary
                                       panAxis: PanAxis.free, // Free panning in all directions
                                       constrained: true, // Allow panning within bounds
                                      // CRITICAL: These callbacks handle smooth zoom
                                      onInteractionStart: (details) {
                                        debugPrint('[InteractiveViewer] Interaction started');
                                        if (details.pointerCount >= 2) {
                                          setState(() {
                                            _isScaleGesture = true;
                                          });
                                          _lastFocalPoint = details.focalPoint;
                                          _lastScale = _transformationController.value.getMaxScaleOnAxis();
                                        }
                                      },
                                        
                                      onInteractionUpdate: (details) {
                                        // Track scale changes for smooth zoom
                                        if (details.pointerCount >= 2) {
                                          final currentScale = _transformationController.value.getMaxScaleOnAxis();
                                          
                                          // Log scale changes for debugging
                                          if ((currentScale - _lastScale).abs() > 0.01) {
                                            debugPrint('[InteractiveViewer] Scale: ${currentScale.toStringAsFixed(2)}');
                                            _lastScale = currentScale;
                                          }
                                          
                                          _lastFocalPoint = details.focalPoint;
                                        }
                                      },
                                        
                                      onInteractionEnd: (details) {
                                        debugPrint('[InteractiveViewer] Interaction ended');
                                        
                                        // Small delay to ensure gesture completes smoothly
                                        Future.delayed(const Duration(milliseconds: 100), () {
                                          if (mounted) {
                                            setState(() {
                                              _isScaleGesture = false;
                                            });
                                            _lastFocalPoint = null;
                                            _lastScale = 1.0;
                                          }
                                        });
                                      },
                                        
                                      child: SvgViewer(
                                        svgString: svgString,
                                        viewBox: _svgService.viewBox,
                                        showWidgetBorder: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Reset zoom button when zoomed
                            if (_isZoomed)
                              Positioned(
                                top: viewerHeight - 47,
                                left: (viewerWidth - 40) / 2,
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

                    SizedBox(height: screenHeight * 0.020),

                    // Tool Pills - Responsive
                    Builder(builder: (context) {
                      final pillSpacing = screenWidth * 0.02;
                      final totalPadding = 2 * horizontalPadding + 16;
                      final availableWidthForPills = viewerWidth - totalPadding - (pillSpacing * 2);
                      final pillWidth = (availableWidthForPills / 3).clamp(100.0, 200.0);

                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                        child: Container(
                          width: viewerWidth,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF0E9FF), Color(0xFFE8F7FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 6))],
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
                                  active: _currentTool == 'color',
                                ),
                              ),
                              SizedBox(width: pillSpacing),
                              SizedBox(
                                width: pillWidth,
                                child: _toolPill(
                                  onTap: () => setState(() => _currentTool = 'eraser'),
                                  icon: Icons.cleaning_services_outlined,
                                  label: 'Eraser',
                                  active: _currentTool == 'eraser',
                                ),
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

                    SizedBox(height: screenHeight * 0.02),

                    // Color Palette - Responsive
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                      child: Container(
                        width: viewerWidth,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFF0F4), Color(0xFFEFFCF4)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 6))],
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final availableWidth = constraints.maxWidth - 24;
                            final colorSize = (availableWidth / 7 - 8).clamp(35.0, 50.0);
                            
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: _colorService.palette.map((c) {
                                final isSelected = _selectedColor == c;
                                return GestureDetector(
                                  onTap: () => _onSelectColor(c),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    width: colorSize,
                                    height: colorSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: isSelected
                                          ? [const BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))]
                                          : [const BoxShadow(color: Color(0x11000000), blurRadius: 4)],
                                      border: Border.all(
                                        color: isSelected ? Colors.deepPurple : Colors.grey.shade200,
                                        width: isSelected ? 3.0 : 1.0,
                                      ),
                                    ),
                                    child: ClipOval(child: Container(color: c)),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.03),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }}
