import 'package:flutter/material.dart';
import '../services/svg_service.dart';
import '../services/path_service.dart';
import '../services/hit_test_service.dart';
import '../services/color_service.dart';
import '../widgets/svg_viewer.dart';
import '../widgets/color_palette.dart';

class ColoringPage extends StatefulWidget {
  const ColoringPage({super.key});
  @override
  State<ColoringPage> createState() => _ColoringPageState();
}

class _ColoringPageState extends State<ColoringPage> {
  final SvgService _svgService = SvgService(assetPath: 'assets/colouring_svg.svg');
  final PathService _pathService = PathService();
  final ColorService _colorService = ColorService();
  HitTestService? _hitTestService;

  // UI state
  Color? _selectedColor;

  @override
  void initState() {
    super.initState();
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
      setState(() {});
    }
  }

  void _onTapAt(Offset localPos, Size widgetSize) {
    if (_hitTestService == null) return;
    final id = _hitTestService!.hitTest(localPos, widgetSize);
    if (id == null) return;
    if (_selectedColor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a color first.')),
      );
      return;
    }
    // push history and apply color
    _colorService.pushSnapshot(_svgService.getSvgString());
    final hex = _colorService.colorToHex(_selectedColor!);
    _svgService.applyFillToElementById(id, hex);
    // rebuild paths (only needed if geometry changes)
    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService = HitTestService(paths: _pathService.paths, viewBox: _svgService.viewBox);
    setState(() {}); // update UI
  }

  void _undo() {
    final prev = _colorService.popSnapshot();
    if (prev == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to undo')));
      return;
    }
    _svgService.setSvgString(prev);
    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService = HitTestService(paths: _pathService.paths, viewBox: _svgService.viewBox);
    setState(() {});
  }

  void _reset() async {
    await _svgService.reload();
    _pathService.buildPathsFromDoc(_svgService.doc!);
    _hitTestService = HitTestService(paths: _pathService.paths, viewBox: _svgService.viewBox);
    _colorService.clearHistory();
    setState(() {
      _selectedColor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final svgString = _svgService.getSvgString();
    return Scaffold(
      appBar: AppBar(
        title: const Text('SVG Coloring'),
        actions: [
          IconButton(onPressed: _undo, icon: const Icon(Icons.undo)),
          IconButton(onPressed: _reset, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: svgString == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LayoutBuilder(builder: (ctx, cons) {
                      return SvgViewer(
                        svgString: svgString,
                        viewBox: _svgService.viewBox,
                        onTapAt: (pos) => _onTapAt(pos, Size(cons.maxWidth, cons.maxHeight)),
                      );
                    }),
                  ),
                ),
                ColorPalette(
                  palette: _colorService.palette,
                  selected: _selectedColor,
                  onSelect: (c) => setState(() => _selectedColor = c),
                  onClear: () => setState(() => _selectedColor = null),
                ),
              ],
            ),
    );
  }
}
