// lib/services/svg_service.dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';
import 'dart:async';
import 'dart:developer' as developer; // use developer.log instead of print

class ViewBox {
  final double minX, minY, width, height;
  const ViewBox(this.minX, this.minY, this.width, this.height);
}

class SvgService {
  final String assetPath;
  String? _svgString;
  XmlDocument? doc;
  ViewBox viewBox = const ViewBox(0, 0, 1000, 1000);

  SvgService({required this.assetPath});

  Future<void> load() async {
    try {
      // Try load from assets
      _svgString = await rootBundle.loadString(assetPath);
      doc = XmlDocument.parse(_svgString!);
      developer.log('Loaded SVG from $assetPath, length=${_svgString?.length}', name: 'SvgService');
    } catch (e, st) {
      // If asset not found or XML invalid → fallback
      developer.log('Error loading SVG from $assetPath: $e\n$st', name: 'SvgService', level: 1000);
      _svgString = _defaultFallbackSvg();
      try {
        doc = XmlDocument.parse(_svgString!);
        developer.log('Parsed fallback SVG', name: 'SvgService');
      } catch (parseError, pst) {
        developer.log('Fallback parse failed: $parseError\n$pst', name: 'SvgService', level: 1000);
        doc = null;
      }
    }

    _parseViewBox();
  }

  Future<void> reload() async => await load();

  String? getSvgString() => _svgString;

  void setSvgString(String xml) {
    try {
      _svgString = xml;
      doc = XmlDocument.parse(xml);
      _parseViewBox();
    } catch (e, st) {
      developer.log('Error parsing provided SVG string: $e\n$st', name: 'SvgService', level: 1000);
    }
  }

  void _parseViewBox() {
    if (doc == null) return;
    final root = doc!.rootElement;
    final vb = root.getAttribute('viewBox');
    if (vb != null) {
      final parts = vb
          .split(RegExp(r'[\s,]+'))
          .map((s) => double.tryParse(s) ?? 0.0)
          .toList();
      if (parts.length >= 4) {
        viewBox = ViewBox(parts[0], parts[1], parts[2], parts[3]);
        return;
      }
    }
    final w = double.tryParse(root.getAttribute('width') ?? '') ?? 1000;
    final h = double.tryParse(root.getAttribute('height') ?? '') ?? 1000;
    viewBox = ViewBox(0, 0, w, h);
  }

  void applyFillToElementById(String id, String hex) {
    if (doc == null) {
      developer.log('applyFillToElementById called but doc is null', name: 'SvgService', level: 900);
      return;
    }
    XmlElement? target;
    try {
      target = doc!.descendants
          .whereType<XmlElement>()
          .firstWhere((e) => e.getAttribute('id') == id);
    } catch (_) {
      target = null;
    }
    if (target == null) {
      developer.log('No element found with id=$id', name: 'SvgService', level: 800);
      return;
    }
    _applyFill(target, hex);
    _svgString = doc!.toXmlString(pretty: false);
  }

  void _applyFill(XmlElement elem, String hex) {
    final style = elem.getAttribute('style');
    if (style != null && style.trim().isNotEmpty) {
      final entries = style
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      var changed = false;
      for (int i = 0; i < entries.length; i++) {
        if (entries[i].startsWith('fill:')) {
          entries[i] = 'fill: $hex';
          changed = true;
          break;
        }
      }
      if (!changed) entries.add('fill: $hex');
      elem.setAttribute('style', entries.join('; '));
    } else {
      elem.setAttribute('fill', hex);
    }
  }

  /// Simple fallback rectangle SVG if real asset fails
  String _defaultFallbackSvg() {
    return """
    <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
      <rect id="rect1" x="10" y="10" width="80" height="80" 
            fill="white" stroke="black" />
    </svg>
    """;
  }
}