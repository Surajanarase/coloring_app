import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';
import 'dart:async';

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
      _svgString = await rootBundle.loadString(assetPath);
      doc = XmlDocument.parse(_svgString!);
    } catch (_) {
      // fallback
      _svgString = "<svg viewBox='0 0 100 100'><rect id='rect1' x='10' y='10' width='80' height='80' fill='white' stroke='black'/></svg>";
      doc = XmlDocument.parse(_svgString!);
    }
    _parseViewBox();
  }

  Future<void> reload() async => await load();

  String? getSvgString() {
    return _svgString;
  }

  void setSvgString(String xml) {
    _svgString = xml;
    doc = XmlDocument.parse(xml);
    _parseViewBox();
  }

  void _parseViewBox() {
    if (doc == null) return;
    final root = doc!.rootElement;
    final vb = root.getAttribute('viewBox');
    if (vb != null) {
      final parts = vb.split(RegExp(r'[\s,]+')).map((s) => double.tryParse(s) ?? 0.0).toList();
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
    if (doc == null) return;
    XmlElement? target;
    try {
      target = doc!.descendants.whereType<XmlElement>().firstWhere((e) => e.getAttribute('id') == id);
    } catch (_) {
      target = null;
    }
    if (target == null) return;
    _applyFill(target, hex);
    _svgString = doc!.toXmlString(pretty: false);
  }

  void _applyFill(XmlElement elem, String hex) {
    final style = elem.getAttribute('style');
    if (style != null && style.trim().isNotEmpty) {
      final entries = style.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
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
}
