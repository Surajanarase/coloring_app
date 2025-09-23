// lib/pages/colouring_page.dart
import 'package:flutter/material.dart';
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

  const ColoringPage({
    super.key,
    this.assetPath = 'assets/colouring_svg.svg',
    this.title,
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
  String _currentTool = 'color'; // 'color' or 'eraser'

  static const double _viewerWidth = 360;
  static const double _viewerHeight = 600;

  final GlobalKey _containerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _svgService = SvgService(assetPath: widget.assetPath);
    _load();
  }

  Future<void> _load() async {
    await _svgService.load();

    if (_svgService.doc != null) {
      // Build paths and hit-test helper
      _pathService.buildPathsFromDoc(_svgService.doc!);

      _hitTestService = HitTestService(
        paths: _pathService.paths, // Map<String, Path>
        viewBox: _svgService.viewBox,
      );

      final imageId = widget.assetPath;
      final title = widget.title ?? imageId.split('/').last;
      final pathIds = _pathService.paths.keys.toList().cast<String>();

      await _db.upsertImage(imageId, title, pathIds.length);
      await _db.insertPathsForImage(imageId, pathIds);

      // Restore previously colored paths
      final coloredRows = await _db.getColoredPathsForImage(imageId);
      for (final row in coloredRows) {
        final pid = row['id'] as String;
        final colorHex = (row['color'] as String?) ?? '';
        if (colorHex.isNotEmpty) {
          _svgService.applyFillToElementById(pid, colorHex);
        }
      }

      // Rebuild after applying fills
      _pathService.buildPathsFromDoc(_svgService.doc!);
      _hitTestService = HitTestService(
        paths: _pathService.paths,
        viewBox: _svgService.viewBox,
      );
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Offset _computeLocalOffset(RenderBox containerBox, Offset globalPosition) {
    return containerBox.globalToLocal(globalPosition);
  }

  void _onTapAt(Offset localPos, Size widgetSize) async {
    if (_hitTestService == null) return;
    final hitId = _hitTestService!.hitTest(localPos, widgetSize);
    if (hitId == null) return;

    if (_currentTool == 'color') {
      if (_selectedColor == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a color first')),
        );
        return;
      }

      final colorHex = _colorServiceToHex(_selectedColor!);

      _svgService.applyFillToElementById(hitId, colorHex);
      await _db.markPathColored(hitId, colorHex);
    } else if (_currentTool == 'eraser') {
      _svgService.applyFillToElementById(hitId, 'none');
      await _db.markPathUncolored(hitId);
    }

    // Rebuild paths & hit-test after changes
    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService = HitTestService(
      paths: _pathService.paths,
      viewBox: _svgService.viewBox,
    );

    if (!mounted) return;
    setState(() {});
  }

  // wrapper for color->hex, left separate to make analyzer happy and keep intent clear
  String _colorServiceToHex(Color color) => _colorService.colorToHex(color);


  void _onSelectColor(Color color) {
    setState(() {
      _selectedColor = color;
      _currentTool = 'color';
    });
  }

  Future<void> _clearCanvasAll() async {
    if (_svgService.doc == null) return;

    final allIds = _pathService.paths.keys.toList().cast<String>();
    for (final pid in allIds) {
      _svgService.applyFillToElementById(pid, 'none');
      await _db.markPathUncolored(pid);
    }

    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService = HitTestService(
      paths: _pathService.paths,
      viewBox: _svgService.viewBox,
    );

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Canvas cleared')),
    );
  }

  Future<void> _saveProgress() async {
    // If you want to record a "saved at" timestamp, add a DB call here, e.g.:
    // await _db.setImageSavedAt(widget.assetPath, DateTime.now());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your coloring has been saved! 🎨')),
    );
    Navigator.of(context).pop(); // return to Dashboard (Dashboard will refresh)
  }

  void _openDashboardShortcut() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DashboardPage()),
    );
  }

  // Local helper to build pill AppBar buttons
  Widget _appBarPill({
    required VoidCallback onPressed,
    required Color color,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      // Back pill (blue) as leading
      leadingWidth: 120,
      leading: _appBarPill(
        onPressed: () => Navigator.of(context).pop(),
        color: const Color(0xFF657DF6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.arrow_back, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text('Back', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      title: Text(widget.title ?? 'Coloring'),
      centerTitle: true,
      actions: [
        _appBarPill(
          onPressed: _saveProgress,
          color: const Color(0xFF2FC64D),
          child: Row(
            children: const [
              Icon(Icons.save_alt, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ],
    );

    if (_loading) {
      return Scaffold(appBar: appBar, body: const Center(child: CircularProgressIndicator()));
    }

    final String svgString = _svgService.getSvgString() ?? '';
    if (svgString.isEmpty) {
      return Scaffold(appBar: appBar, body: const Center(child: Text('Failed to load SVG')));
    }

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
                  width: _viewerWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 12)],
                  ),
                  child: Column(
                    children: [
                      // Visual top spacing / title row
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            const SizedBox(width: 48),
                            Expanded(
                              child: Text(widget.title ?? 'Coloring',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),

                      // SVG canvas area
                      Container(
                        key: _containerKey,
                        width: _viewerWidth,
                        height: _viewerHeight,
                        padding: const EdgeInsets.all(10),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            final box = _containerKey.currentContext?.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            final local = _computeLocalOffset(box, details.globalPosition);
                            _onTapAt(local, Size(box.size.width, box.size.height));
                          },
                          child: SvgViewer(
                            svgString: svgString,
                            onTapAt: (local) => _onTapAt(local, const Size(_viewerWidth, _viewerHeight)),
                            viewBox: _svgService.viewBox,
                            showWidgetBorder: false,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Tools row: Color / Eraser toggle + Clear button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ToggleButtons(
                              isSelected: [_currentTool == 'color', _currentTool == 'eraser'],
                              onPressed: (index) {
                                setState(() {
                                  _currentTool = index == 0 ? 'color' : 'eraser';
                                });
                              },
                              children: const [
                                Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('🎨 Color')),
                                Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('🧹 Eraser')),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: _clearCanvasAll,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Clear'),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            )
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Color palette
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                    color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
                                    width: isSelected ? 3 : 1,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      ElevatedButton(
                        onPressed: _selectedColor == null ? null : () => setState(() => _selectedColor = null),
                        style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        child: const Text('Clear Selection'),
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
