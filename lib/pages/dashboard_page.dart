// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import 'colouring_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DbService _db = DbService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

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
    } catch (e) {
      debugPrint('Error loading dashboard rows: $e');
    }
    // no return in finally, just set loading false
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final title = (row['title'] as String?) ?? id;
    final total = (row['total_paths'] as int?) ?? 0;
    final colored = (row['colored'] as int?) ?? 0;
    final percent = total == 0 ? 0 : ((colored / total) * 100).round();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.image, size: 28, color: Colors.black54),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 10.0, right: 8.0),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (colored / total),
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            color: Colors.teal,
          ),
        ),
        trailing: SizedBox(
          width: 110,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'reset') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reset progress?'),
                        content: const Text(
                          'This will clear all coloring for this image. Are you sure?',
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Reset')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _db.resetImageProgress(id);
                      await _loadRows();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Progress reset')),
                      );
                    }
                  }
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'reset', child: Text('Reset progress')),
                ],
              ),
            ],
          ),
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ColoringPage(assetPath: id)),
          );
          await _loadRows();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: _loadRows,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 40),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 48, color: Colors.black38),
                                const SizedBox(height: 12),
                                Text(
                                  'No images tracked yet.\nOpen a coloring image to populate the dashboard.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding:
                        const EdgeInsets.only(top: 16, bottom: 32),
                    children: [
                      Container(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 8)
                          ],
                        ),
                        child: Row(
                          children: const [
                            CircleAvatar(
                                radius: 28, backgroundColor: Colors.purple),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Understanding Rheumatoid Cardiac Disease',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._rows.map(_buildRow),
                      const SizedBox(height: 24),
                    ],
                  ),
      ),
    );
  }
}
