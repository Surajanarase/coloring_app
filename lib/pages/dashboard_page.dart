// Full file: lib/pages/dashboard_page.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../services/db_service.dart';
import '../services/svg_service.dart';
import '../services/path_service.dart';
import 'colouring_page.dart';
import '../auth/login_screen.dart';
import 'package:flutter_svg/flutter_svg.dart'; // used for thumbnails

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

  /// unlocked states for each row in _rows
  List<bool> _unlocked = [];

  /// percent threshold to unlock the next image (prev percent >= this).
  static const int _unlockThreshold = 90;

  static const String _fallbackRheumaticInfoText = '''
Rheumatic diseases (rheumatoid conditions) are autoimmune disorders that cause inflammation of joints and other organs.

Common signs:
• Persistent joint pain and swelling
• Morning stiffness lasting longer than 30 minutes
• Fatigue, low-grade fever

When to see a doctor:
If you experience persistent joint pain, stiffness or swelling, consult a healthcare professional for evaluation and timely management.

This app is for educational/demo purposes only.
''';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _debugPrintAssetManifest();
    await discoverAndSeedSvgs();
    await _loadRows();
    await _db.debugDumpImages();
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

      // compute overall by area-weighted average (sum colored_area / sum total_area)
      final totalAreaSum = _rows.fold<double>(0.0, (acc, r) => acc + ((r['total_area'] as num?)?.toDouble() ?? 0.0));
      final coloredAreaSum = _rows.fold<double>(0.0, (acc, r) => acc + ((r['colored_area'] as num?)?.toDouble() ?? 0.0));
      _overall = totalAreaSum == 0 ? 0 : (coloredAreaSum / totalAreaSum * 100).round();

      // compute unlocked states (now uses display percent)
      _computeUnlockedStates();
    } catch (e, st) {
      debugPrint('Error loading dashboard rows: $e\n$st');
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Option A: compute unlocked states using the same perceptual/display percent
  /// that `_buildRow` uses, so what the user sees is what unlocks the next item.
  void _computeUnlockedStates() {
    _unlocked = List<bool>.filled(_rows.length, false);
    if (_rows.isEmpty) return;
    _unlocked[0] = true;

    // keep these values in sync with the display scaling in _buildRow
    const double gamma = 0.28;
    const double autoCompleteRawThreshold = 95.0;
    const double smallNudgeMinimum = 10.0;

    for (var i = 1; i < _rows.length; i++) {
      final prev = _rows[i - 1];
      final prevTotalArea = (prev['total_area'] as num?)?.toDouble() ?? 0.0;
      final prevColoredArea = (prev['colored_area'] as num?)?.toDouble() ?? 0.0;
      final prevRawPercent = prevTotalArea == 0 ? 0.0 : (prevColoredArea / prevTotalArea * 100.0);

      // compute display percent for previous row using same rules as _buildRow
      final double scaled = math.pow((prevRawPercent.clamp(0.0, 100.0) / 100.0), gamma) * 100.0;
      double displayDouble;
      if (prevRawPercent >= autoCompleteRawThreshold) {
        displayDouble = 100.0;
      } else {
        displayDouble = scaled;
      }
      if (prevRawPercent > 0 && displayDouble < smallNudgeMinimum) displayDouble = displayDouble + smallNudgeMinimum;
      final prevDisplayPercent = displayDouble.round().clamp(0, 100);

      if (_unlocked[i - 1] && prevDisplayPercent >= _unlockThreshold) {
        _unlocked[i] = true;
      } else {
        _unlocked[i] = false;
      }
    }
  }

  Future<void> _debugPrintAssetManifest() async {
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> map = json.decode(manifest) as Map<String, dynamic>;
      final svgs = map.keys
          .where((k) => k.startsWith('assets/svgs/') && k.toLowerCase().endsWith('.svg'))
          .toList();
      debugPrint('[manifest svgs] ${svgs.join(", ")}');
    } catch (e, st) {
      debugPrint('[manifest error] $e\n$st');
    }
  }

  Future<void> discoverAndSeedSvgs() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestJson) as Map<String, dynamic>;
      final svgAssets = manifestMap.keys
          .where((k) => k.startsWith('assets/svgs/') && k.toLowerCase().endsWith('.svg'))
          .toList()
        ..sort();

      for (final asset in svgAssets) {
        try {
          final svgService = SvgService(assetPath: asset);
          await svgService.load();

          if (svgService.doc == null) continue;

          final tmpPathService = PathService();
          tmpPathService.buildPathsFromDoc(svgService.doc!);

          // compute per-path area (bounding-box area approximation)
          final Map<String, double> pathAreas = {};
          for (final pid in tmpPathService.paths.keys) {
            final bounds = tmpPathService.paths[pid]!.getBounds();
            final area = bounds.width * bounds.height;
            pathAreas[pid] = area;
          }
          final pathCount = pathAreas.length;
          final totalArea = pathAreas.values.fold<double>(0.0, (a, b) => a + b);
          final title = _titleFromAsset(asset);

          await _db.upsertImage(asset, title, pathCount, totalArea: totalArea);
          await _db.insertPathsForImage(asset, pathAreas);

          debugPrint('[discoverAndSeedSvgs] seeded: $asset (paths: $pathCount, totalArea=${totalArea.toStringAsFixed(2)})');
        } catch (e, st) {
          debugPrint('[discoverAndSeedSvgs: asset error] $asset -> $e\n$st');
        }
      }
    } catch (e, st) {
      debugPrint('[discoverAndSeedSvgs error] $e\n$st');
    }
  }

  String _titleFromAsset(String asset) {
    const Map<int, String> titles = {
      1: 'Maria likes to play',
      2: 'Maria has a sore throat',
      3: 'Maria go to a health clinic',
      4: 'Parents decided to give a home remedy',
      5: 'Maria feels sick again',
      6: 'Elbows and knees joints hurt',
      7: 'She gets tired easily',
      8: 'Hard for Maria to breathe',
      10: 'May need surgery',
      11: 'Clinic importance',
      12: 'Home remedy is dangerous',
      13: 'Proper clinical medicine',
      14: 'You can grow up and healthy',
    };

    final name = asset.split('/').last.replaceAll('.svg', '');
    final reg = RegExp(r'\d+');
    final m = reg.firstMatch(name);
    if (m != null) {
      try {
        final num = int.parse(m.group(0)!);
        if (titles.containsKey(num)) return titles[num]!;
      } catch (_) {}
    }

    final words = name
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();

    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  Color _paddedPercentColor(int percent) {
    if (percent <= 20) return Colors.red;
    if (percent <= 50) return Colors.blue;
    if (percent <= 90) return Colors.yellow.shade700;
    return Colors.green;
  }

  Widget _buildRow(Map<String, dynamic> row, int index) {
    final id = row['id'] as String;
    final title = (row['title'] as String?) ?? id;
    final totalArea = (row['total_area'] as num?)?.toDouble() ?? 0.0;
    final coloredArea = (row['colored_area'] as num?)?.toDouble() ?? 0.0;
    // raw percent (area-based)
    final rawPercent = totalArea == 0 ? 0.0 : (coloredArea / totalArea * 100.0);

    // --- perceptual rescaling (tunable) ---
    // gamma < 1 boosts mid/low values so they look more "filled" to the eye.
    // Lower gamma => stronger boost. 0.28 gives a stronger boost than 0.35.
    const double gamma = 0.28;

    // map rawPercent (0..100) to scaledPercent (0..100)
    final double scaled = math.pow((rawPercent.clamp(0.0, 100.0) / 100.0), gamma) * 100.0;

    // small remainder rule: if nearly complete, show 100% (avoid tiny leftovers looking unfinished)
    // If rawPercent >= 95% treat as complete for display purposes
    double displayDouble;
    if (rawPercent >= 95.0) {
      displayDouble = 100.0;
    } else {
      displayDouble = scaled;
    }

    // Stronger visual nudge for small rawPercent so initial coloring looks more visible
    if (rawPercent > 0 && displayDouble < 10) displayDouble = displayDouble + 10;

    final displayPercent = displayDouble.round().clamp(0, 100);


    final unlocked = (index < _unlocked.length) ? _unlocked[index] : (index == 0);
    final rowOpacity = unlocked ? 1.0 : 0.45;
    final pillColor = _paddedPercentColor(displayPercent);

    return Opacity(
      opacity: rowOpacity,
      child: GestureDetector(
        onTap: unlocked
            ? () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          ColoringPage(assetPath: id, title: title, username: widget.username)),
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
                          placeholderBuilder: (_) =>
                              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
                      Row(
                        children: [
                          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: pillColor,
                            ),
                            child: Text('$displayPercent%',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: totalArea == 0 ? 0 : (coloredArea / totalArea),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        color: Colors.teal,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        totalArea == 0 ? 'Not started • Tap to open' : (displayPercent < 100 ? 'In progress • Tap to continue' : 'Completed • Tap to view'),
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 3-dot menu removed
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRheumaticInfo() async {
    String content = _fallbackRheumaticInfoText;

    try {
      final md = await rootBundle.loadString('docs/rheumatic-heart-disease.md');
      if (md.trim().isNotEmpty) content = md;
    } catch (e, st) {
      debugPrint('[openRheumaticInfo] failed to load docs asset: $e\n$st');
    }

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rheumatic Disease Information'),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))
        ],
      ),
    );
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _pillButton({required Widget child, required VoidCallback onPressed, required Color color}) {
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
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Hi, ${widget.username} 👋', style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          _pillButton(
            onPressed: _logout,
            color: const Color(0xFFFF6B6B),
            child: Row(
              children: const [
                Icon(Icons.logout, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRows,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(28),
                              color: Colors.white,
                              child: InkWell(
                                onTap: _openRheumaticInfo,
                                borderRadius: BorderRadius.circular(28),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  constraints: const BoxConstraints(minHeight: 48),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      CircleAvatar(
                                        backgroundColor: Color(0xFF6C4DFF),
                                        radius: 16,
                                        child: Icon(Icons.health_and_safety, color: Colors.white, size: 18),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Rheumatic disease information', style: TextStyle(fontWeight: FontWeight.w600)),
                                      SizedBox(width: 6),
                                      Icon(Icons.chevron_right, size: 20, color: Colors.black54),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF84FAB0), Color(0xFF8FD3F4)]),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('Your Progress', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text('$_overall%', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white)),
                              const SizedBox(height: 6),
                              const Text('Keep coloring to unlock new pages!', style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              const Icon(Icons.info_outline, size: 48, color: Colors.black38),
                              const SizedBox(height: 12),
                              Text('No images tracked yet.\nOpen a coloring image to populate the dashboard.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ..._rows.asMap().entries.map((e) => _buildRow(e.value, e.key)),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  String _basenameWithoutExtension(String assetPath) {
    final parts = assetPath.split('/');
    final filename = parts.isNotEmpty ? parts.last : assetPath;
    final dot = filename.lastIndexOf('.');
    return dot >= 0 ? filename.substring(0, dot) : filename;
  }

  int? _firstNumberInString(String s) {
    final reg = RegExp(r'\d+');
    final m = reg.firstMatch(s);
    if (m == null) return null;
    try {
      return int.parse(m.group(0)!);
    } catch (_) {
      return null;
    }
  }
}
