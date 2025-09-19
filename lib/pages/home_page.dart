// lib/pages/home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'colouring_page.dart';
import 'dashboard_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  bool _showCover = true;
  static const _coverDuration = Duration(seconds: 3);
  static const _fadeDuration = Duration(milliseconds: 450);
  Timer? _timer;

  final String _coverAsset = 'assets/images/rhd_booklet_cover.png';

  @override
  void initState() {
    super.initState();
    // start timer to hide cover after 3 seconds
    _timer = Timer(_coverDuration, () {
      if (!mounted) return;
      setState(() => _showCover = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismissCoverEarly() {
    if (!_showCover) return;
    _timer?.cancel();
    setState(() => _showCover = false);
  }

  // ===== Keep this function identical to your existing homepage content =====
  Widget _buildMainContent(BuildContext context) {
    // --- begin original content ---
    void openColoring() {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ColoringPage()));
    }

    void openDashboard() {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardPage()));
    }

    Widget infoCard(String title, String text, {IconData? icon}) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12.0, top: 4),
                  child: Icon(icon, size: 28, color: Colors.deepPurple),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(text, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    const about =
        'Rheumatic heart disease (RHD) is a chronic condition caused by rheumatic fever that damages the heart valves. Early diagnosis and treatment of strep throat and rheumatic fever can prevent RHD. This app provides educational material and interactive coloring activities to help people (and children) learn about heart anatomy and RHD.';

    const symptoms =
        'Common signs and symptoms: shortness of breath, chest pain, swelling in legs or abdomen, tiredness, palpitations.';
    const prevention =
        'Prevention: treat streptococcal infections early, regular follow-up for rheumatic fever, antibiotic prophylaxis when recommended.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rheumatic Heart Disease — Info'),
        actions: [
          IconButton(
            tooltip: 'Dashboard',
            onPressed: openDashboard,
            icon: const Icon(Icons.dashboard),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                      radius: 34, backgroundColor: Colors.deepPurple, child: Icon(Icons.favorite, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Understanding Rheumatic Heart Disease',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 6),
                        Text('Learn key facts, prevention tips and practice with interactive diagrams.',
                            style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            infoCard('About RHD', about, icon: Icons.info_outline),
            infoCard('Symptoms', symptoms, icon: Icons.bloodtype),
            infoCard('Prevention', prevention, icon: Icons.shield),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Text('Get started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: openColoring,
                            icon: const Icon(Icons.brush),
                            label: const Text('Open Coloring'),
                            style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: openDashboard,
                            icon: const Icon(Icons.table_chart),
                            label: const Text('Dashboard'),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 40),
            Text(
              'Credits: This application is aimed to raise awareness about RHD. Use it for educational purposes only.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
    // --- end original content ---
  }

  @override
  Widget build(BuildContext context) {
    // We use a Stack: main content at bottom, cover image overlaid on top while _showCover is true.
    return Stack(
      children: [
        // MAIN (unchanged) content
        _buildMainContent(context),

        // COVER OVERLAY
        if (_showCover)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _showCover ? 1.0 : 0.0,
              duration: _fadeDuration,
              onEnd: () {
                // When fade finishes and cover is invisible, ensure it's removed
                if (!_showCover && mounted) setState(() {}); // rebuild to remove cover via if
              },
              child: GestureDetector(
                onTap: _dismissCoverEarly, // allow early dismiss by tapping
                child: AbsorbPointer(
                  absorbing: _showCover,
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Image display (fits nicely on screen)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Semantics(
                                  label: 'RHD booklet cover',
                                  child: Image.asset(
                                    _coverAsset,
                                    fit: BoxFit.contain,
                                    width: MediaQuery.of(context).size.width * 0.92,
                                    errorBuilder: (c, e, s) => Container(
                                      padding: const EdgeInsets.all(24),
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.broken_image, size: 64, color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Tap to continue',
                                style: TextStyle(fontSize: 14, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
