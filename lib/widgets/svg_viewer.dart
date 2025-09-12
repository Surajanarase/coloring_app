// lib/widgets/svg_viewer.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/svg_service.dart'; // <<-- provides ViewBox

class SvgViewer extends StatelessWidget {
  final String svgString;
  final void Function(Offset localPos) onTapAt;
  final ViewBox? viewBox; // optional; used to set aspect ratio

  const SvgViewer({
    super.key,
    required this.svgString,
    required this.onTapAt,
    this.viewBox,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          onTapAt(details.localPosition);
        },
        child: Center(
          child: AspectRatio(
            // if viewBox available, use its ratio; otherwise default to 1
            aspectRatio: (viewBox != null && viewBox!.width != 0 && viewBox!.height != 0)
                ? viewBox!.width / viewBox!.height
                : 1,
            child: SvgPicture.string(svgString, fit: BoxFit.contain),
          ),
        ),
      );
    });
  }
}
