import 'package:flutter_test/flutter_test.dart';
import 'package:demo/main.dart';

void main() {
  testWidgets('SVG coloring page loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle(); // now settles quickly, even without asset
    expect(find.text('SVG Coloring'), findsOneWidget);
  });
}