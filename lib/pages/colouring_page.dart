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
      _pathService.buildPathsFromDoc(_svgService.doc!);
      _hitTestService = HitTestService(
        paths: _pathService.paths,
        viewBox: _svgService.viewBox,
      );

      final imageId = widget.assetPath;
      final title = widget.title ?? imageId.split('/').last;
      final pathIds = _pathService.paths.keys.toList();

      await _db.upsertImage(imageId, title, pathIds.length);
      await _db.insertPathsForImage(imageId, pathIds);

      //  Restore previously colored paths
      final coloredRows = await _db.getColoredPathsForImage(imageId);
      for (final row in coloredRows) {
        final pid = row['id'] as String;
        final colorHex = (row['color'] as String?) ?? '';
        if (colorHex.isNotEmpty) {
          _svgService.applyFillToElementById(pid, colorHex);
        }
      }

      // rebuild after restore
      _pathService.buildPathsFromDoc(_svgService.doc!);
      _hitTestService = HitTestService(
        paths: _pathService.paths,
        viewBox: _svgService.viewBox,
      );
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _onTapAt(Offset localPos, Size widgetSize) async {
    if (_hitTestService == null) return;
    final hitId = _hitTestService!.hitTest(localPos, widgetSize);
    if (hitId == null) return;

    if (_selectedColor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a color first')),
      );
      return;
    }

    final colorHex = _colorService.colorToHex(_selectedColor!);

    _svgService.applyFillToElementById(hitId, colorHex);

    await _db.markPathColored(hitId, colorHex);

    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService = HitTestService(
      paths: _pathService.paths,
      viewBox: _svgService.viewBox,
    );

    if (!mounted) return;
    setState(() {});
  }

  void _onSelectColor(Color color) {
    setState(() => _selectedColor = color);
  }

  void _openDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DashboardPage()),
    );
  }

  Offset _computeLocalOffset(RenderBox containerBox, Offset globalPosition) {
    return containerBox.globalToLocal(globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: const Text('SVG Coloring'),
      actions: [
        IconButton(
          onPressed: _openDashboard,
          icon: const Icon(Icons.dashboard),
        ),
      ],
    );

    if (_loading) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final String? svgStringNullable = _svgService.getSvgString();
    if (svgStringNullable == null || svgStringNullable.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: const Center(
          child: Text('Failed to load SVG'),
        ),
      );
    }

    final String svgString = svgStringNullable;

    return Scaffold(
      appBar: appBar,
      backgroundColor: const Color(0xFFFDF2F8),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 18),
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final box = _containerKey.currentContext?.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final local = _computeLocalOffset(box, details.globalPosition);
                    _onTapAt(local, Size(box.size.width, box.size.height));
                  },
                  child: Container(
                    key: _containerKey,
                    width: _viewerWidth,
                    height: _viewerHeight,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade800, width: 1.2),
                      color: Colors.white,
                    ),
                    child: SvgViewer(
                      svgString: svgString,
                      onTapAt: (local) =>
                          _onTapAt(local, const Size(_viewerWidth, _viewerHeight)),
                      viewBox: _svgService.viewBox,
                      showWidgetBorder: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
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
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _selectedColor == null
                    ? null
                    : () => setState(() => _selectedColor = null),
                child: const Text('Clear Selection'),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              onPressed: _openDashboard,
              child: const Icon(Icons.dashboard),
            ),
          ),
        ],
      ),
    );
  }
}
