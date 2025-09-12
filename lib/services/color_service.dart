// lib/services/color_service.dart
import 'package:flutter/material.dart';

class ColorService {
  final List<Color> palette = [
    Colors.red,
    Colors.pink,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.purple,
    Colors.brown,
    Colors.grey,
    const Color(0xFFFFE0BD), // skin
    const Color(0xFF8D5524),
    Colors.black,
    Colors.white,
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
    // Use floating color components (.r, .g, .b, .a) as recommended by the SDK
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
