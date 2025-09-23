// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import 'colouring_page.dart';
import '../auth/phone_entry.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DbService _db = DbService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _overall = 0;

  // Replace or extend this text with the actual information your manager supplied
  static const String rheumaticInfoText = '''
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
    _loadRows();
  }

  Future<void> _loadRows() async {
    setState(() => _loading = true);
    try {
      final r = await _db.getDashboardRows();
      if (!mounted) return;
      setState(() {
        _rows = r;
      });

      final totalProgress = _rows.fold<int>(0, (sum, row) {
        final total = (row['total_paths'] as int?) ?? 0;
        final colored = (row['colored'] as int?) ?? 0;
        final percent = total == 0 ? 0 : ((colored / total) * 100).round();
        return sum + percent;
      });

      if (_rows.isNotEmpty) {
        _overall = (totalProgress / _rows.length).round();
      } else {
        _overall = 0;
      }
    } catch (e) {
      debugPrint('Error loading dashboard rows: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final title = (row['title'] as String?) ?? id;
    final total = (row['total_paths'] as int?) ?? 0;
    final colored = (row['colored'] as int?) ?? 0;
    final percent = total == 0 ? 0 : ((colored / total) * 100).round();

    String emoji = '🖼️';
    final lower = id.toLowerCase();
    if (lower.contains('butter')) {
      emoji = '🦋';
    } else if (lower.contains('flower')) {
      emoji = '🌸';
    } else if (lower.contains('cat')) {
      emoji = '🐱';
    } else if (lower.contains('house')) {
      emoji = '🏠';
    } else if (lower.contains('tree')) {
      emoji = '🌳';
    } else if (lower.contains('car')) {
      emoji = '🚗';
    }

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ColoringPage(assetPath: id, title: title),
          ),
        );
        // After returning from ColoringPage, reload dashboard data
        await _loadRows();
      },
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
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 32))),
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
                            gradient: const LinearGradient(colors: [Color(0xFFFF9A9E), Color(0xFFFECFEF)]),
                          ),
                          child: Text('$percent%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : (colored / total),
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      color: Colors.teal,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      total == 0 ? 'Not started • Tap to open' : (percent < 100 ? 'In progress • Tap to continue' : 'Completed • Tap to view'),
                      style: TextStyle(color: Colors.grey.shade700),
                    )
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'reset') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reset progress?'),
                        content: const Text('This will clear all coloring for this image. Are you sure?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reset')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _db.resetImageProgress(id);
                      await _loadRows();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Progress reset')));
                    }
                  }
                },
                itemBuilder: (ctx) => const [PopupMenuItem(value: 'reset', child: Text('Reset progress'))],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _openRheumaticInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rheumatic Disease Information'),
        content: SingleChildScrollView(child: Text(rheumaticInfoText)),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  void _logout() {
    // Clear any session data here if needed, then go back to login (clearing stack)
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
      (route) => false,
    );
  }

  // Helper that builds a rounded pill button used in AppBar
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
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0,2))],
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
        title: const Text('Dashboard'),
        actions: [
          // Logout pill (pink)
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
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadRows,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Container(
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
                        ..._rows.map(_buildRow),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
          Positioned(
            left: 10,
            top: MediaQuery.of(context).size.height * 0.25,
            child: Material(
              elevation: 6,
              shape: const CircleBorder(),
              color: Colors.white,
              child: IconButton(
                onPressed: _openRheumaticInfo,
                icon: const Icon(Icons.health_and_safety, color: Colors.deepPurple),
                tooltip: 'Rheumatic disease info',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
