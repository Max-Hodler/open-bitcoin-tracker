import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:open_bitcoin_tracker/theme/theme.dart';
import 'package:open_bitcoin_tracker/widgets/stack_avatar.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppThemes.light(),
    home: Scaffold(body: Center(child: child)),
  ));
}

String _tinyJpegBase64() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(255, 147, 26));
  return base64Encode(Uint8List.fromList(img.encodeJpg(image)));
}

void main() {
  group('StackAvatar', () {
    testWidgets('renders uppercase first character when imageData is null',
        (tester) async {
      await _pump(tester, const StackAvatar(name: 'savings'));
      expect(find.text('S'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('uses first grapheme of an emoji name', (tester) async {
      await _pump(tester, const StackAvatar(name: '🚀 Moon'));
      expect(find.text('🚀'), findsOneWidget);
    });

    testWidgets('uses first CJK character', (tester) async {
      await _pump(tester, const StackAvatar(name: '北極星'));
      expect(find.text('北'), findsOneWidget);
    });

    testWidgets('falls back to ? when name is blank', (tester) async {
      await _pump(tester, const StackAvatar(name: '   '));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders an Image when imageData is set', (tester) async {
      await _pump(
        tester,
        StackAvatar(name: 'Cold', imageData: _tinyJpegBase64()),
      );
      expect(find.byType(Image), findsOneWidget);
      // No initial-letter fallback when an image is present.
      expect(find.text('C'), findsNothing);
    });

    testWidgets('invokes onTap when tapped', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        StackAvatar(name: 'Cold', onTap: () => taps++),
      );
      await tester.tap(find.byType(StackAvatar));
      expect(taps, 1);
    });
  });
}
