// lib/pages/dashboard_page.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../services/db_service.dart';
import '../services/svg_service.dart';
import '../services/path_service.dart';
import 'colouring_page.dart';
import '../auth/login_screen.dart';

class DashboardPage extends StatefulWidget {
  final String username;

  const DashboardPage({super.key, required this.username});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DbService _db = DbService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _overall = 0;

  List<bool> _unlocked = [];
  static const int _unlockThreshold = 90;

  // Boost parameters (optional visual boost)
  static const double _progressGamma = 0.60;
  static const double _minVisibleProgress = 8.0;
  static const double _eps = 0.000001; // tolerance for floating comparisons

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _debugPrintAssetManifest();
    await discoverAndSeedSvgs();
    await _loadRows();
    try {
      await _db.debugDumpImages();
    } catch (_) {}
  }

  Future<void> _loadRows() async {
    setState(() => _loading = true);
    try {
      final originalRows = await _db.getDashboardRows();
      final rows = List<Map<String, dynamic>>.from(originalRows);

      rows.sort((a, b) {
        final idAFull = (a['id'] as String?) ?? '';
        final idBFull = (b['id'] as String?) ?? '';

        final baseA = _basenameWithoutExtension(idAFull);
        final baseB = _basenameWithoutExtension(idBFull);

        final numA = _firstNumberInString(baseA) ?? 999999;
        final numB = _firstNumberInString(baseB) ?? 999999;

        if (numA != numB) return numA.compareTo(numB);
        return baseA.toLowerCase().compareTo(baseB.toLowerCase());
      });

      if (!mounted) return;
      setState(() => _rows = rows);

      // Compute overall using area sums but clamp & handle zero-area safely
      final totalAreaSum = _rows.fold<double>(0.0, (a, r) => a + ((r['total_area'] as num?)?.toDouble() ?? 0.0));
      final coloredAreaSum = _rows.fold<double>(0.0, (a, r) => a + ((r['colored_area'] as num?)?.toDouble() ?? 0.0));
      final overallRaw = totalAreaSum == 0 ? 0.0 : (coloredAreaSum / totalAreaSum * 100.0);

      // Boost and clamp, but guarantee 100 when nearly complete
      _overall = _boostProgressPercent(overallRaw, coloredAreaSum, totalAreaSum);

      _computeUnlockedStates();
    } catch (e, st) {
      debugPrint('Error loading dashboard rows: $e\n$st');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _debugPrintAssetManifest() async {
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final map = json.decode(manifest) as Map<String, dynamic>;
      final svgs = map.keys.where((k) => k.startsWith('assets/svgs/') && k.endsWith('.svg')).toList();
      debugPrint('[manifest svgs] ${svgs.join(", ")}');
    } catch (e) {
      debugPrint('[manifest error] $e');
    }
  }

  Future<void> discoverAndSeedSvgs() async {
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final map = json.decode(manifest) as Map<String, dynamic>;
      final svgs = map.keys.where((k) => k.startsWith('assets/svgs/') && k.endsWith('.svg')).toList()..sort();

      for (final asset in svgs) {
        final svgService = SvgService(assetPath: asset);
        await svgService.load();
        if (svgService.doc == null) continue;

        final pathService = PathService();
        pathService.buildPathsFromDoc(svgService.doc!);

        final pathAreas = <String, double>{};
        for (final pid in pathService.paths.keys) {
          final b = pathService.paths[pid]!.getBounds();
          final area = (b.width * b.height);
          pathAreas[pid] = area.isFinite ? area : 0.0;
        }
        final totalArea = pathAreas.values.fold(0.0, (a, b) => a + b);
        await _db.upsertImage(asset, _titleFromAsset(asset), pathAreas.length, totalArea: totalArea);
        await _db.insertPathsForImage(asset, pathAreas);
      }
    } catch (e) {
      debugPrint('[discoverAndSeedSvgs] error: $e');
    }
  }

  String _titleFromAsset(String asset) {
    final name = asset.split('/').last.replaceAll('.svg', '');
    return name.replaceAll('-', ' ').replaceAll('_', ' ');
  }

  Color _percentColor(int percent) {
    if (percent == 0) return Colors.grey;
    if (percent <= 20) return Colors.red;
    if (percent <= 50) return Colors.blue;
    if (percent <= 85) return Colors.amber;
    return Colors.green;
  }

  int _boostProgressPercent(double rawPercent, double coloredAreaSum, double totalAreaSum) {
    // Guarantee exact 100% in two cases:
    // 1) coloredAreaSum >= totalAreaSum - eps
    // 2) rawPercent >= 99.5 (very close to complete)
    if (totalAreaSum > 0 && (coloredAreaSum + _eps >= totalAreaSum)) {
      debugPrint('[Progress] All area colored -> 100%');
      return 100;
    }
    if (rawPercent <= 0.0) return 0;
    if (rawPercent >= 99.5) return 100;

    final normalized = (rawPercent / 100.0).clamp(0.0, 1.0);
    double boosted = math.pow(normalized, _progressGamma) * 100.0;

    if (rawPercent > 0.5 && boosted < _minVisibleProgress) {
      boosted = _minVisibleProgress;
    }

    // light mid-range smoothing to keep monotonic behaviour
    if (rawPercent >= 30.0 && rawPercent < 95.0) {
      final midRangeBoost = math.pow(normalized, _progressGamma * 0.9) * 100.0;
      final blendFactor = 0.2;
      boosted = boosted * (1 - blendFactor) + midRangeBoost * blendFactor;
    }

    if (boosted >= 99.0 && rawPercent < 95.0) {
      boosted = 98.0;
    }

    final result = boosted.round().clamp(0, 100);
    debugPrint('[Progress] Raw: ${rawPercent.toStringAsFixed(2)}% -> Display: $result% (coloredAreaSum=${coloredAreaSum.toStringAsFixed(2)}, totalAreaSum=${totalAreaSum.toStringAsFixed(2)})');
    return result;
  }

  void _computeUnlockedStates() {
    _unlocked = List<bool>.filled(_rows.length, false);
    if (_rows.isEmpty) return;
    _unlocked[0] = true;
    for (var i = 1; i < _rows.length; i++) {
      final prev = _rows[i - 1];
      final prevTotal = (prev['total_area'] as num?)?.toDouble() ?? 0.0;
      final prevColored = (prev['colored_area'] as num?)?.toDouble() ?? 0.0;

      final prevRawPercent = prevTotal == 0 ? 0.0 : (prevColored / prevTotal * 100.0);
      final prevDisplay = _boostProgressPercent(prevRawPercent, prevColored, prevTotal);

      if (_unlocked[i - 1] && prevDisplay >= _unlockThreshold) {
        _unlocked[i] = true;
      } else {
        _unlocked[i] = false;
      }
    }
  }

  Future<void> _openRheumaticInfo() async {
    String content = '';
    try {
      final md = await rootBundle.loadString('docs/rheumatic-heart-disease.md');
      if (md.isNotEmpty) content = md;
    } catch (_) {}
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rheumatic Disease Information'),
        content: SingleChildScrollView(child: Text(content.isNotEmpty ? content : 'Information not available')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row, int index) {
    final id = row['id'] as String;
    final title = row['title'] as String? ?? id;
    final totalArea = (row['total_area'] as num?)?.toDouble() ?? 0.0;
    final coloredArea = (row['colored_area'] as num?)?.toDouble() ?? 0.0;

    final rawPercent = totalArea == 0 ? 0.0 : (coloredArea / totalArea * 100.0);

    // Guarantee 100% if colored_area >= total_area - eps
    int displayPercent = _boostProgressPercent(rawPercent, coloredArea, totalArea);

    final unlocked = (index < _unlocked.length) ? _unlocked[index] : (index == 0);
    final rowOpacity = unlocked ? 1.0 : 0.45;
    final pillColor = _percentColor(displayPercent);

    return Opacity(
      opacity: rowOpacity,
      child: GestureDetector(
        onTap: unlocked
            ? () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ColoringPage(assetPath: id, title: title, username: widget.username)),
                );
                await _loadRows();
              }
            : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 8)],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Builder(builder: (ctx) {
                      try {
                        return SvgPicture.asset(
                          id,
                          fit: BoxFit.cover,
                          placeholderBuilder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      } catch (_) {
                        return const Center(child: Text('🎨', style: TextStyle(fontSize: 32)));
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: totalArea == 0 ? 0 : math.min(1.0, (displayPercent / 100.0)),
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade200,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: pillColor,
                            ),
                            child: Text(
                              '$displayPercent%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayPercent == 0 
                            ? 'Not started • Tap to open' 
                            : (displayPercent < 100 ? 'In progress ($displayPercent%) • Tap to continue' : 'Completed • Tap to view'),
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _learnMoreEmbedded() {
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _openRheumaticInfo,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF58D3C7), Color(0xFF4BB0D6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.menu_book, color: Colors.white),
              SizedBox(width: 8),
              Text('Learn More', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              SizedBox(width: 6),
              Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double headingSize = 24;
    const double percentSize = 24;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 80,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text('Hi, ${widget.username} 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
              Image.asset('assets/logo2.png', height: 140, width: 140, fit: BoxFit.contain),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(25),
                    onTap: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFFFF6B6B), borderRadius: BorderRadius.circular(25), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 3))]),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.logout, size: 18, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Logout', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF84FAB0), Color(0xFF8FD3F4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('Your colouring progress', style: TextStyle(color: Color(0xFF2D7A72), fontSize: headingSize, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)), 
                            child: Text('$_overall%', style: TextStyle(fontSize: percentSize, fontWeight: FontWeight.w700, color: Color(0xFF2D7A72)))
                          ),
                        ]),
                        const SizedBox(height: 8),
                        _learnMoreEmbedded(),
                        const SizedBox(height: 6),
                        const Text('Keep coloring to unlock new pages!', style: TextStyle(color: Color(0xFF2D7A72), fontSize: 14, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ..._rows.asMap().entries.map((e) => _buildRow(e.value, e.key)),
              ],
            ),
    );
  }

  String _basenameWithoutExtension(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(0, dot) : name;
  }

  int? _firstNumberInString(String s) {
    final match = RegExp(r'\d+').firstMatch(s);
    return match != null ? int.tryParse(match.group(0)!) : null;
  }
}
