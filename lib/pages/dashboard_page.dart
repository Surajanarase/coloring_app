// lib/pages/dashboard_page.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/db_service.dart';
import '../services/svg_service.dart';
import '../services/path_service.dart';
import 'colouring_page.dart';
import 'quiz_page.dart';
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
  bool _quizAvailable = false;

  List<bool> _unlocked = [];
  static const int _unlockThreshold = 90;
  static const int _quizUnlockThreshold = 80;

  static const double _progressGamma = 0.85;
  static const double _minVisibleProgress = 5.0;
  static const double _eps = 0.01;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    debugPrint('[Dashboard] ============ INITIALIZING DASHBOARD ============');
    await _debugPrintAssetManifest();
    await discoverAndSeedSvgs();
    await _loadRows();
    try {
      await _db.debugDumpImages();
    } catch (e) {
      debugPrint('[Dashboard] Debug dump failed: $e');
    }
    
    _checkAndShowQuizIfAvailable();
    
    debugPrint('[Dashboard] ============ INITIALIZATION COMPLETE ============');
  }

  Future<void> _loadRows() async {
    setState(() => _loading = true);
    try {
      final originalRows = await _db.getDashboardRows();
      final rows = List<Map<String, dynamic>>.from(originalRows);

      debugPrint('[Dashboard] Loaded ${rows.length} images from database');

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

      final totalAreaSum = _rows.fold<double>(
        0.0, 
        (a, r) => a + ((r['total_area'] as num?)?.toDouble() ?? 0.0)
      );
      final coloredAreaSum = _rows.fold<double>(
        0.0, 
        (a, r) => a + ((r['colored_area'] as num?)?.toDouble() ?? 0.0)
      );
      
      final overallRaw = totalAreaSum == 0 ? 0.0 : (coloredAreaSum / totalAreaSum * 100.0);
      _overall = _boostProgressPercent(overallRaw, coloredAreaSum, totalAreaSum);

      debugPrint('[Dashboard] Overall progress: $_overall% (raw: ${overallRaw.toStringAsFixed(2)}%)');

      _computeUnlockedStates();
    } catch (e, st) {
      debugPrint('[Dashboard] Error loading rows: $e\n$st');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _checkAndShowQuizIfAvailable() {
    if (_rows.isEmpty) {
      setState(() => _quizAvailable = false);
      return;
    }

    final lastImage = _rows.last;
    final totalArea = (lastImage['total_area'] as num?)?.toDouble() ?? 0.0;
    final coloredArea = (lastImage['colored_area'] as num?)?.toDouble() ?? 0.0;
    final storedPercent = (lastImage['display_percent'] as num?)?.toDouble() ?? 0.0;

    int displayPercent;
    if (storedPercent > 0 && storedPercent <= 100) {
      displayPercent = storedPercent.round();
    } else {
      final rawPercent = totalArea == 0 ? 0.0 : (coloredArea / totalArea * 100.0);
      displayPercent = _boostProgressPercent(rawPercent, coloredArea, totalArea);
    }

    final wasAvailable = _quizAvailable;
    final isNowAvailable = displayPercent >= _quizUnlockThreshold;
    
    setState(() {
      _quizAvailable = isNowAvailable;
    });

    debugPrint('[Dashboard] Quiz available: $_quizAvailable (last image: $displayPercent%)');

    if (isNowAvailable && !wasAvailable && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showQuizUnlockedDialog();
      });
    }
  }

  Future<void> _showQuizUnlockedDialog() async {
    final shouldTakeQuiz = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.emoji_events, color: Colors.amber, size: 32),
            SizedBox(width: 12),
            Flexible(
              child: Text(
                'Quiz Unlocked! 🎉',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Congratulations!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'You have completed most of the colouring pages! 🎨',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
            SizedBox(height: 16),
            Text(
              'Would you like to take a fun quiz to test what you learned about keeping your heart healthy? ❤️',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Take Quiz Now!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (shouldTakeQuiz == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuizPage(username: widget.username),
        ),
      );
      await _loadRows();
    }
  }

  String _getMotivationalMessage() {
    if (_rows.isEmpty) return 'Start your coloring journey! 🎨';
    
    if (_quizAvailable) {
      return 'Amazing! Quiz unlocked! Tap the button below to test your knowledge!';
    }
    
    if (_overall == 0) {
      return 'Welcome! Start coloring the first page to begin your learning adventure!';
    } else if (_overall < 20) {
      return 'Great start! Keep coloring to learn more about keeping your heart healthy!';
    } else if (_overall < 40) {
      return 'You\'re doing wonderful! Continue coloring to unlock new pages!';
    } else if (_overall < 60) {
      return 'Fantastic progress! You\'re learning so much about heart health!';
    } else if (_overall < 80) {
      return 'Almost there! Keep going to unlock the quiz and test your knowledge!';
    } else if (_overall < 95) {
      return 'Excellent work! Just a little more to complete all pages!';
    } else if (_overall < 100) {
      return 'So close to 100%! Finish strong!';
    } else {
      return 'Perfect! You completed everything! You\'re a heart health champion!';
    }
  }

  Future<void> _debugPrintAssetManifest() async {
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final map = json.decode(manifest) as Map<String, dynamic>;
      final svgs = map.keys
        .where((k) => k.startsWith('assets/svgs/') && k.endsWith('.svg'))
        .toList()
        ..sort();
      debugPrint('[Dashboard] Found ${svgs.length} SVG assets: ${svgs.join(", ")}');
    } catch (e) {
      debugPrint('[Dashboard] Manifest error: $e');
    }
  }

  Future<void> discoverAndSeedSvgs() async {
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final map = json.decode(manifest) as Map<String, dynamic>;
      final svgs = map.keys
        .where((k) => k.startsWith('assets/svgs/') && k.endsWith('.svg'))
        .toList()
        ..sort();

      debugPrint('[Dashboard] Seeding ${svgs.length} SVG files to database...');

      for (final asset in svgs) {
        try {
          final svgService = SvgService(assetPath: asset);
          await svgService.load();
          
          if (svgService.doc == null) {
            debugPrint('[Dashboard] ✗ Failed to load: $asset');
            continue;
          }

          final pathService = PathService();
          pathService.buildPathsFromDoc(svgService.doc!);

          final pathAreas = <String, double>{};
          for (final pid in pathService.paths.keys) {
            try {
              final b = pathService.paths[pid]!.getBounds();
              final area = (b.width * b.height);
              pathAreas[pid] = area.isFinite ? area : 0.0;
            } catch (_) {
              pathAreas[pid] = 0.0;
            }
          }
          
          final totalArea = pathAreas.values.fold(0.0, (a, b) => a + b);
          
          await _db.upsertImage(
            asset, 
            _titleFromAsset(asset), 
            pathAreas.length, 
            totalArea: totalArea
          );
          await _db.insertPathsForImage(asset, pathAreas);
          
          debugPrint('[Dashboard] ✓ Seeded: $asset (${pathAreas.length} paths, area: ${totalArea.toStringAsFixed(2)})');
        } catch (e) {
          debugPrint('[Dashboard] ✗ Error seeding $asset: $e');
        }
      }
      
      debugPrint('[Dashboard] Seeding complete');
    } catch (e, st) {
      debugPrint('[Dashboard] discoverAndSeedSvgs error: $e\n$st');
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
      9: 'Maria goes to health clinic',
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
    final words = name
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  Color _percentColor(int percent) {
    if (percent == 0) return Colors.grey;
    if (percent <= 20) return Colors.red;
    if (percent <= 50) return Colors.blue;
    if (percent <= 85) return Colors.amber;
    return Colors.green;
  }

  int _boostProgressPercent(double rawPercent, double coloredAreaSum, double totalAreaSum) {
    if (totalAreaSum > 0 && (coloredAreaSum + _eps >= totalAreaSum)) {
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

  void _computeUnlockedStates() {
    _unlocked = List<bool>.filled(_rows.length, false);
    if (_rows.isEmpty) return;
    
    _unlocked[0] = true;
    debugPrint('[Dashboard] Image 0 unlocked by default');
    
    for (var i = 1; i < _rows.length; i++) {
      final prev = _rows[i - 1];
      final prevTotal = (prev['total_area'] as num?)?.toDouble() ?? 0.0;
      final prevColored = (prev['colored_area'] as num?)?.toDouble() ?? 0.0;
      final prevStored = (prev['display_percent'] as num?)?.toDouble() ?? 0.0;

      int prevDisplay;
      if (prevStored > 0 && prevStored <= 100) {
        prevDisplay = prevStored.round();
      } else {
        final prevRaw = prevTotal == 0 ? 0.0 : (prevColored / prevTotal * 100.0);
        prevDisplay = _boostProgressPercent(prevRaw, prevColored, prevTotal);
      }

      if (_unlocked[i - 1] && prevDisplay >= _unlockThreshold) {
        _unlocked[i] = true;
        debugPrint('[Dashboard] Image $i unlocked (prev progress: $prevDisplay%)');
      } else {
        _unlocked[i] = false;
        debugPrint('[Dashboard] Image $i locked (prev progress: $prevDisplay% < $_unlockThreshold%)');
      }
    }
  }

  Future<void> _openRheumaticInfo() async {
    String content = '';
    try {
      final md = await rootBundle.loadString('docs/rheumatic-heart-disease.md');
      if (md.isNotEmpty) content = md;
    } catch (e) {
      debugPrint('[Dashboard] Failed to load rheumatic info: $e');
      content = '# Information Not Available\n\nSorry, we could not load the information at this time. Please try again later.';
    }
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            maxWidth: MediaQuery.of(ctx).size.width * 0.95,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF84FAB0), Color(0xFF8FD3F4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.favorite, 
                        color: Color(0xFF2D7A72), 
                        size: 28
                      ),
                    ),
                    const SizedBox(width: 12),
                 Flexible(
  child: FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: const Text(
      'Rheumatic Heart Disease',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2D7A72),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  ),
),

                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF2D7A72)),
                      onPressed: () => Navigator.pop(ctx),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              
              // Markdown Content
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Markdown(
                    data: content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      h1: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D7A72),
                        height: 1.4,
                      ),
                      h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
                      h2: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D7A72),
                        height: 1.4,
                      ),
                      h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
                      h3: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4BB0D6),
                        height: 1.3,
                      ),
                      h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
                      h4: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4BB0D6),
                      ),
                      p: const TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: Colors.black87,
                      ),
                      pPadding: const EdgeInsets.only(bottom: 12),
                      listBullet: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF2D7A72),
                        fontWeight: FontWeight.bold,
                      ),
                      listBulletPadding: const EdgeInsets.only(right: 8),
                      listIndent: 24.0,
                      blockSpacing: 12.0,
                      strong: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D7A72),
                      ),
                      em: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.black87,
                      ),
                      blockquote: const TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: const Color(0xFFF0F9F8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(
                            color: const Color(0xFF4BB0D6),
                            width: 4,
                          ),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.all(12),
                      code: const TextStyle(
                        fontSize: 14,
                        backgroundColor: Color(0xFFF5F5F5),
                        fontFamily: 'monospace',
                      ),
                      a: const TextStyle(
                        color: Color(0xFF4BB0D6),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    onTapLink: (text, url, title) async {
                      if (url != null && url.isNotEmpty) {
                        try {
                          final uri = Uri.parse(url);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(
                              uri, 
                              mode: LaunchMode.externalApplication
                            );
                          } else {
                            debugPrint('[Dashboard] Cannot launch URL: $url');
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Could not open link: $url'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          debugPrint('[Dashboard] Error launching URL: $e');
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row, int index) {
    final id = row['id'] as String;
    final title = row['title'] as String? ?? id;
    final totalArea = (row['total_area'] as num?)?.toDouble() ?? 0.0;
    final coloredArea = (row['colored_area'] as num?)?.toDouble() ?? 0.0;
    final storedPercent = (row['display_percent'] as num?)?.toDouble() ?? 0.0;

    final rawPercent = totalArea == 0 ? 0.0 : (coloredArea / totalArea * 100.0);

    int displayPercent;
    
    if (storedPercent > 0 && storedPercent <= 100) {
      displayPercent = storedPercent.round();
    } else {
      displayPercent = _boostProgressPercent(rawPercent, coloredArea, totalArea);
    }

    final unlocked = (index < _unlocked.length) ? _unlocked[index] : (index == 0);
    final rowOpacity = unlocked ? 1.0 : 0.45;
    final pillColor = _percentColor(displayPercent);

    return Opacity(
      opacity: rowOpacity,
      child: GestureDetector(
        onTap: unlocked
            ? () async {
                debugPrint('[Dashboard] Opening image: $id');
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ColoringPage(
                      assetPath: id, 
                      title: title, 
                      username: widget.username
                    )
                  ),
                );
                debugPrint('[Dashboard] Returned from coloring page, reloading...');
                await _loadRows();
                _checkAndShowQuizIfAvailable();
              }
            : () {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Complete previous image to $_unlockThreshold% to unlock'),
                      duration: const Duration(seconds: 2),
                    )
                  );
                }
              },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x11000000), blurRadius: 8)
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: LayoutBuilder(builder: (context, constraints) {
              // compute thumbnail size responsive to available width
              final thumbSize = (constraints.maxWidth * 0.18).clamp(56.0, 96.0);

              return Row(
                children: [
                  Container(
                    width: thumbSize,
                    height: thumbSize,
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
                            placeholderBuilder: (_) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)
                            ),
                          );
                        } catch (e) {
                          debugPrint('[Dashboard] Failed to load thumbnail for $id: $e');
                          return const Center(
                            child: Text('🎨', style: TextStyle(fontSize: 32))
                          );
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title, 
                          style: const TextStyle(
                            fontWeight: FontWeight.w700, 
                            fontSize: 15
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: displayPercent / 100.0,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade200,
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10, 
                                vertical: 4
                              ),
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
                              ? (unlocked ? 'Not started • Tap to open' : 'Locked • Complete previous image')
                              : (displayPercent < 100 
                                  ? 'In progress ($displayPercent%) • Tap to continue' 
                                  : 'Completed • Tap to view'),
                          style: TextStyle(
                            color: Colors.grey.shade700, 
                            fontSize: 12
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isSmallScreen = screenWidth < 600;
        
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: isSmallScreen ? 14 : 18,
              horizontal: isSmallScreen ? 12 : 16,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF84FAB0), Color(0xFF8FD3F4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                )
              ],
            ),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Your colouring progress',
                      style: TextStyle(
                        color: const Color(0xFF2D7A72),
                        fontSize: isSmallScreen ? 18 : 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 10 : 12,
                        vertical: isSmallScreen ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_overall%',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 20 : 24,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2D7A72),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Motivational Message
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 10 : 14,
                    vertical: isSmallScreen ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF2D7A72).withValues(alpha: 0.15),
                        const Color(0xFF4BB0D6).withValues(alpha: 0.15),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Icon(
                          Icons.emoji_events,
                          color: const Color(0xFFFFB800),
                          size: isSmallScreen ? 18 : 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _getMotivationalMessage(),
                          style: TextStyle(
                            color: const Color(0xFF1A5F57),
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Buttons Row
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Learn More Button
                    InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: _openRheumaticInfo,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF58D3C7), Color(0xFF4BB0D6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 14 : 16,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book, color: Colors.white, size: isSmallScreen ? 16 : 18),
                            const SizedBox(width: 8),
                            Text(
                              'Learn More',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: isSmallScreen ? 13 : 15,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, color: Colors.white, size: isSmallScreen ? 16 : 18),
                          ],
                        ),
                      ),
                    ),

                    // Quiz Button (if available)
                    if (_quizAvailable)
                      InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => QuizPage(username: widget.username),
                            ),
                          );
                          await _loadRows();
                          _checkAndShowQuizIfAvailable();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x44FF6B6B),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              )
                            ],
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 14 : 16,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.quiz, color: Colors.white, size: isSmallScreen ? 16 : 18),
                              const SizedBox(width: 8),
                              Text(
                                'Take Quiz',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: isSmallScreen ? 13 : 15,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 90,
        titleSpacing: 0,
        title: LayoutBuilder(
          builder: (context, constraints) {
            String displayUsername = widget.username;
            final maxUsernameLength = constraints.maxWidth > 600 ? 15 : 10;
            if (displayUsername.length > maxUsernameLength) {
              displayUsername = '${displayUsername.substring(0, maxUsernameLength)}...';
            }

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: constraints.maxWidth * 0.03),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: constraints.maxWidth > 600 ? 80 : 64,
                          width: constraints.maxWidth > 600 ? 80 : 64,
                          child: Image.asset(
                            'assets/logo2.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hi, $displayUsername 👋',
                          style: TextStyle(
                            fontSize: constraints.maxWidth > 600 ? 18 : 15,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Transform.translate(
                        offset: const Offset(0, -10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(25),
                          onTap: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (route) => false,
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: constraints.maxWidth > 600 ? 16 : 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B6B),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.logout, size: constraints.maxWidth > 600 ? 18 : 17, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  'Logout',
                                  style: TextStyle(
                                    fontSize: constraints.maxWidth > 600 ? 16 : 15,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                return ListView(
                  padding: EdgeInsets.symmetric(
                    vertical: constraints.maxHeight * 0.02,
                    horizontal: constraints.maxWidth * 0.02,
                  ),
                  children: [
                    _buildProgressHeader(),
                    const SizedBox(height: 8),
                    ..._rows.asMap().entries.map((e) => _buildRow(e.value, e.key)),
                    SizedBox(height: constraints.maxHeight * 0.08),
                  ],
                );
              },
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
