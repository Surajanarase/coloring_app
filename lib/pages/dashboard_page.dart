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

  // ✅ COMPLETELY REDESIGNED: Progressive boost system for smooth, consistent progression
  // Lower value = more aggressive boost throughout the range
  static const double _progressGamma = 0.55; // Increased boost significantly
  static const double _minVisibleProgress = 12.0; // Minimum visible progress when any coloring is done

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

      // ✅ FIXED: Use same boost function for overall progress
      final totalAreaSum = _rows.fold<double>(0.0, (a, r) => a + ((r['total_area'] as num?)?.toDouble() ?? 0.0));
      final coloredAreaSum = _rows.fold<double>(0.0, (a, r) => a + ((r['colored_area'] as num?)?.toDouble() ?? 0.0));
      final overallRaw = totalAreaSum == 0 ? 0.0 : (coloredAreaSum / totalAreaSum * 100.0);
      
      // Use the exact same boost function for consistency
      _overall = _boostProgressPercent(overallRaw);

      _computeUnlockedStates();
    } catch (e, st) {
      debugPrint('Error loading dashboard rows: $e\n$st');
    }
    if (mounted) setState(() => _loading = false);
  }

  /// ✅ FIXED: Compute unlocked states using SAME boost function consistently
  void _computeUnlockedStates() {
    _unlocked = List<bool>.filled(_rows.length, false);
    if (_rows.isEmpty) return;
    _unlocked[0] = true;
    for (var i = 1; i < _rows.length; i++) {
      final prev = _rows[i - 1];
      final prevTotal = (prev['total_area'] as num?)?.toDouble() ?? 0.0;
      final prevColored = (prev['colored_area'] as num?)?.toDouble() ?? 0.0;
      final prevRawPercent = prevTotal == 0 ? 0.0 : (prevColored / prevTotal * 100.0);

      // ✅ Use same boost function for unlock logic - CONSISTENT everywhere
      final prevDisplay = _boostProgressPercent(prevRawPercent);

      if (_unlocked[i - 1] && prevDisplay >= _unlockThreshold) {
        _unlocked[i] = true;
      } else {
        _unlocked[i] = false;
      }
    }
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
    const titles = {
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
    final match = RegExp(r'\d+').firstMatch(name);
    if (match != null) {
      final n = int.parse(match.group(0)!);
      return titles[n] ?? name;
    }
    final words = name.replaceAll('-', ' ').replaceAll('_', ' ').split(' ').where((w) => w.isNotEmpty).toList();
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  // ✅ UPDATED: Color scheme for percentage boxes
  Color _percentColor(int percent) {
    if (percent == 0) return Colors.grey;
    if (percent <= 20) return Colors.red;
    if (percent <= 50) return Colors.blue;
    if (percent <= 85) return Colors.amber;
    return Colors.green;
  }

  /// ✅ COMPLETELY REDESIGNED: Smooth, consistent progress boost across ALL ranges
  /// This single function is used EVERYWHERE for consistency:
  /// - Individual image progress display
  /// - Overall progress calculation
  /// - Unlock logic
  /// NO MORE STUCK PROGRESS - smooth progression from 0 to 100%
  int _boostProgressPercent(double rawPercent) {
    // Handle edge cases
    if (rawPercent <= 0.0) return 0;
    if (rawPercent >= 99.5) return 100; // Almost complete = 100%
    
    // ✅ Apply consistent gamma boost across entire range
    final normalized = (rawPercent / 100.0).clamp(0.0, 1.0);
    double boosted = math.pow(normalized, _progressGamma) * 100.0;
    
    // ✅ Ensure minimum visible progress for ANY coloring activity
    if (rawPercent > 0.5 && boosted < _minVisibleProgress) {
      boosted = _minVisibleProgress;
    }
    
    // ✅ CRITICAL FIX: Add smoothing in mid-to-high ranges to prevent plateaus
    // This ensures continuous visible progress even when coloring small areas
    if (rawPercent >= 40.0 && rawPercent < 95.0) {
      // Blend with slightly more aggressive boost in this range
      final midRangeBoost = math.pow(normalized, _progressGamma * 0.85) * 100.0;
      final blendFactor = 0.3; // 30% more aggressive
      boosted = boosted * (1 - blendFactor) + midRangeBoost * blendFactor;
    }
    
    // ✅ Final smoothing: ensure we never show 100% unless truly near complete
    if (boosted >= 99.0 && rawPercent < 95.0) {
      boosted = 98.0;
    }
    
    final result = boosted.round().clamp(0, 100);
    
    // Debug logging to track progress consistency
    if (rawPercent > 0) {
      debugPrint('[Progress] Raw: ${rawPercent.toStringAsFixed(2)}% -> Display: $result%');
    }
    
    return result;
  }

  Future<void> _logout() async {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openRheumaticInfo() async {
    String content = _fallbackRheumaticInfoText;
    try {
      final md = await rootBundle.loadString('docs/rheumatic-heart-disease.md');
      if (md.isNotEmpty) content = md;
    } catch (_) {}
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rheumatic Disease Information'),
        content: SingleChildScrollView(child: Text(content)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row, int index) {
    final id = row['id'] as String;
    final title = row['title'] as String? ?? id;
    final totalArea = (row['total_area'] as num?)?.toDouble() ?? 0.0;
    final coloredArea = (row['colored_area'] as num?)?.toDouble() ?? 0.0;

    // ✅ Calculate raw percent and apply THE SAME boost function everywhere
    final rawPercent = totalArea == 0 ? 0.0 : (coloredArea / totalArea * 100.0);
    final displayPercent = _boostProgressPercent(rawPercent);

    // Debug log for this specific row
    debugPrint('[Row: $title] Total: $totalArea, Colored: $coloredArea, Raw: ${rawPercent.toStringAsFixed(2)}%, Display: $displayPercent%');

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
                    onTap: _logout,
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