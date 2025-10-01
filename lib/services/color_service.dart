// lib/services/color_service.dart
import 'package:flutter/material.dart';

class ColorService {
  // arranged to form 2 rows x 7 when shown in a GridView.count (7 columns)
  final List<Color> palette = [
    Colors.red,
    Colors.pink,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.teal,
    Colors.blue, // row 1 (7)

    Colors.purple,
    Colors.brown,
    Colors.grey,
    const Color(0xFFFFE0BD), // skin
    const Color(0xFF8D5524),
    Colors.black,
    Colors.white, // row 2 (7)
  ];

  final List<String> _history = [];

  void pushSnapshot(String? xml) {
    if (xml == null) return;
    _history.add(xml);
  }

  String? popSnapshot() {
    if (_history.isEmpty) return null;
    return _history.removeLast();
  }

  void clearHistory() => _history.clear();

  String colorToHex(Color c) {
    // Use float r/g/b/a (0.0..1.0) scaled to 0..255 for modern SDKs
    final ri = ((c.r * 255).round() & 0xFF);
    final gi = ((c.g * 255).round() & 0xFF);
    final bi = ((c.b * 255).round() & 0xFF);
    final ai = ((c.a * 255).round() & 0xFF);

    final r = ri.toRadixString(16).padLeft(2, '0').toUpperCase();
    final g = gi.toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = bi.toRadixString(16).padLeft(2, '0').toUpperCase();
    final a = ai.toRadixString(16).padLeft(2, '0').toUpperCase();

    if (ai == 0xFF) {
      return '#$r$g$b';
    }
    return '#$a$r$g$b';
  }
}
