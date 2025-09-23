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

class _HomePageState extends State<HomePage> {
  // Cover overlay: show on each app start, hide after _coverDuration or on tap.
  bool _showCover = true;
  static const Duration _coverDuration = Duration(seconds: 3);
  static const Duration _fadeDuration = Duration(milliseconds: 450);
  Timer? _timer;
  final String _coverAsset = 'assets/images/rhd_booklet_cover.png';

  // PageView controller for slide sequence
  final PageController _pageController = PageController(initialPage: 0);
  int _pageIndex = 0;

  // Slide contents (you can edit the text)
  final List<_SlideData> _slides = [
    _SlideData(
      title: 'Understanding Rheumatic Heart Disease',
      lines: [
        'Rheumatic Heart Disease (RHD) happens when the heart valves are damaged after a sickness called rheumatic fever.',
        'We use simple pictures and activities to help kids learn how the heart works.',
      ],
      icon: Icons.favorite,
      bgColor: const Color(0xFFF6E8FF),
    ),
    _SlideData(
      title: 'About RHD',
      lines: [
        'RHD can follow infections like untreated strep throat.',
        'If we treat sore throats early, we can help prevent RHD.',
      ],
      icon: Icons.info_outline,
      bgColor: const Color(0xFFEFF7F6),
    ),
    _SlideData(
      title: 'Symptoms',
      lines: [
        'Shortness of breath',
        'Tiredness and low energy',
        'Swelling in legs or tummy',
      ],
      icon: Icons.bloodtype,
      bgColor: const Color(0xFFFFF7E6),
    ),
    _SlideData(
      title: 'Prevention',
      lines: [
        'Treat sore throat quickly with medicine if needed.',
        'Finish the full course of prescribed antibiotics.',
        'Keep regular checkups if you had rheumatic fever.',
      ],
      icon: Icons.shield,
      bgColor: const Color(0xFFE6F3FF),
    ),
    _SlideData(
      title: 'Ready to Learn & Play?',
      lines: [
        'Tap Start Coloring to practice with fun interactive diagrams!',
        'You can also view progress and earn stickers in Dashboard.',
      ],
      icon: Icons.emoji_events,
      bgColor: const Color(0xFFFDECF2),
    ),
  ];

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
    _pageController.dispose();
    super.dispose();
  }

  void _dismissCoverEarly() {
    if (!_showCover) return;
    _timer?.cancel();
    setState(() => _showCover = false);
  }

  void openColoring() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ColoringPage()));
  }

  void openDashboard() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardPage()));
  }

  void _goToPage(int idx) {
    _pageController.animateToPage(idx, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  void _onNext() {
    final next = (_pageIndex + 1).clamp(0, _slides.length - 1);
    _goToPage(next);
  }

  void _onBack() {
    final prev = (_pageIndex - 1).clamp(0, _slides.length - 1);
    _goToPage(prev);
  }

  Widget _buildSlide(_SlideData slide, {required bool isLast}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Big card with icon + title + content
            Card(
              color: slide.bgColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28.0, horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromRGBO(0, 0, 0, 0.06),
                                blurRadius: 6,
                              )
                            ],
                          ),
                          child: Icon(slide.icon, size: 36, color: Colors.deepPurple),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            slide.title,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ...slide.lines.map((l) => Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(l, style: const TextStyle(fontSize: 16, height: 1.45)),
                        )),
                    if (isLast) ...[
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 12),
                      // Big CTAs for last slide
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: openColoring,
                          icon: const Icon(Icons.brush),
                          label: const Text('Start Coloring', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: openDashboard,
                          icon: const Icon(Icons.table_chart),
                          label: const Text('Open Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // small "progress" / instruction under the card
            Center(
              child: Text(
                isLast ? 'Tap a button to start or swipe back' : 'Swipe → to continue',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // MAIN: slides scaffold
        Scaffold(
          appBar: AppBar(
            title: const Text('Rheumatic Heart Disease'),
            actions: [
              IconButton(onPressed: openDashboard, icon: const Icon(Icons.dashboard)),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // PageView main area
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (i) {
                      if (!mounted) return;
                      setState(() => _pageIndex = i);
                    },
                    itemBuilder: (ctx, i) {
                      final slide = _slides[i];
                      final isLast = i == _slides.length - 1;
                      return _buildSlide(slide, isLast: isLast);
                    },
                  ),
                ),

                // Bottom controls: Back / Dots / Next
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _pageIndex == 0 ? null : _onBack,
                        tooltip: 'Back',
                      ),

                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_slides.length, (i) {
                            final isActive = i == _pageIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              width: isActive ? 18 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isActive ? Colors.deepPurple : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            );
                          }),
                        ),
                      ),

                      IconButton(
                        icon: Icon(_pageIndex == _slides.length - 1 ? Icons.check : Icons.chevron_right),
                        onPressed: _pageIndex == _slides.length - 1 ? openColoring : _onNext,
                        tooltip: _pageIndex == _slides.length - 1 ? 'Start Coloring' : 'Next',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // COVER overlay (3 seconds, tap to dismiss early). Over entire screen.
        if (_showCover)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _showCover ? 1.0 : 0.0,
              duration: _fadeDuration,
              onEnd: () {
                // no-op; state already updated by timer or tap
              },
              child: GestureDetector(
                onTap: _dismissCoverEarly,
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
                              Semantics(
                                label: 'RHD booklet cover',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
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
                              const Text('Tap to continue', style: TextStyle(fontSize: 14, color: Colors.black54)),
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

// small helper class for slide content
class _SlideData {
  final String title;
  final List<String> lines;
  final IconData icon;
  final Color bgColor;
  const _SlideData({
    required this.title,
    required this.lines,
    required this.icon,
    required this.bgColor,
  });
}
