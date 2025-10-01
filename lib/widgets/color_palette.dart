import 'package:flutter/material.dart';

class ColorPalette extends StatelessWidget {
  final List<Color> palette;
  final Color? selected;
  final void Function(Color) onSelect;
  final VoidCallback onClear;

  const ColorPalette({
    super.key,
    required this.palette,
    required this.selected,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Palette", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: palette.map((c) {
              final isSelected = c == selected;
              return GestureDetector(
                onTap: () => onSelect(c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? Colors.black : Colors.black26, width: isSelected ? 3 : 1),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: onClear, icon: const Icon(Icons.clear), label: const Text("Clear Selection")),
        ],
      ),
    );
  }
}