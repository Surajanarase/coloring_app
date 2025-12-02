// lib/widgets/svg_viewer.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/svg_service.dart';

class SvgViewer extends StatelessWidget {
  final String svgString;
  final void Function(Offset localPos)? onTapAt;
  final ViewBox? viewBox;
  final bool showWidgetBorder;

  const SvgViewer({
    super.key,
    required this.svgString,
    this.onTapAt,
    this.viewBox,
    this.showWidgetBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: showWidgetBorder
          ? BoxDecoration(
              border: Border.all(color: Colors.black26, width: 1),
              color: Colors.transparent,
            )
          : null,
      child: SvgPicture.string(
        svgString,
        width: double.infinity,
        height: double.infinity,
        fit:  BoxFit.contain, // Changed from contain to cover
        alignment: Alignment.center,
      ),
    );
  }
}