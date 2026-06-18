import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:open_bitcoin_tracker/screens/home/header/area_chart.dart';
import 'package:open_bitcoin_tracker/theme/theme.dart';

void main() {
  group('AreaChart Scale Fade Transition', () {
    testWidgets('fades out and fades in when toggling logScale', (tester) async {
      const data = [
        PricePoint(1000, 10.0),
        PricePoint(2000, 100.0),
        PricePoint(3000, 1000.0),
      ];

      // Pump AreaChart initially with logScale = false.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemes.light(),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: AreaChart(
                data: data,
                windowStartMs: 1000,
                windowEndMs: 3000,
                color: Colors.orange,
                logScale: false,
                rangeKey: 'key',
                onHover: (_) {},
              ),
            ),
          ),
        ),
      );

      // Verify that initially the Opacity widget is at 1.0.
      Finder opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsOneWidget);
      Opacity opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, 1.0);

      // Now toggle logScale.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemes.light(),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: AreaChart(
                data: data,
                windowStartMs: 1000,
                windowEndMs: 3000,
                color: Colors.orange,
                logScale: true, // Toggled!
                rangeKey: 'key',
                onHover: (_) {},
              ),
            ),
          ),
        ),
      );

      // Pump 150ms. Opacity should decrease to 0.0.
      await tester.pump(const Duration(milliseconds: 150));
      opacityWidget = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacityWidget.opacity, 0.0);

      // Pump to trigger the status listener microtask, rebuild and start forward().
      await tester.pump();
      await tester.pump();

      // Pump to complete the fade-in.
      await tester.pumpAndSettle();
      opacityWidget = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacityWidget.opacity, 1.0);
    });
  });
}
