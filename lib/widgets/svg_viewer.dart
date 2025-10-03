// lib/widgets/svg_viewer.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/svg_service.dart';

class SvgViewer extends StatelessWidget {
  final String svgString;
  // Note: onTapAt left as optional but not used inside to avoid double-handling.
  final void Function(Offset localPos)? onTapAt;
  final ViewBox? viewBox;
  final bool showWidgetBorder; // if true, draws a UI border around the widget

  const SvgViewer({
    super.key,
    required this.svgString,
    this.onTapAt,
    this.viewBox,
    this.showWidgetBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    // Keep aspect ratio of the original svg viewBox so scaling and hit-testing match
    final aspect = (viewBox != null && viewBox!.width != 0 && viewBox!.height != 0)
        ? viewBox!.width / viewBox!.height
        : 1.0;

    // NOTE: removed internal GestureDetector so parent will control tap + coordinate transform.
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Container(
          // Optional UI border so the widget box is visible regardless of artwork stroke
          decoration: showWidgetBorder
              ? BoxDecoration(
                  border: Border.all(color: Colors.black26, width: 1),
                  color: Colors.transparent,
                )
              : null,
          child: ClipRect(
            // Clip so SvgPicture doesn't paint outside the widget bounds
            child: SvgPicture.string(
              svgString,
              fit: BoxFit.contain,        // show whole image, preserves aspect ratio
              alignment: Alignment.topCenter, // pin image to top (reduces perceived top-gap)
            ),
          ),
        ),
      ),
    );
  }
}
