import 'package:flutter_test/flutter_test.dart';
import 'package:open_bitcoin_tracker/data/data.dart';

void main() {
  group('Stack', () {
    test('toJson omits imageData when null', () {
      const s = Stack(id: 'a', name: 'Cold', sats: 100000000);
      expect(s.toJson().containsKey('imageData'), isFalse);
    });

    test('toJson includes imageData when set', () {
      const s = Stack(
        id: 'a',
        name: 'Cold',
        sats: 100000000,
        imageData: 'AAAB',
      );
      expect(s.toJson()['imageData'], 'AAAB');
    });

    test('fromJson reads imageData when present', () {
      final s = Stack.fromJson({
        'id': 'a',
        'name': 'Cold',
        'sats': 100000000,
        'imageData': 'AAAB',
      });
      expect(s, isNotNull);
      expect(s!.imageData, 'AAAB');
    });

    test('fromJson ignores non-string imageData', () {
      final s = Stack.fromJson({
        'id': 'a',
        'name': 'Cold',
        'sats': 100000000,
        'imageData': 123,
      });
      expect(s, isNotNull);
      expect(s!.imageData, isNull);
    });

    test('round-trips through JSON with imageData', () {
      const original = Stack(
        id: 'a',
        name: 'Cold',
        sats: 100000000,
        imageData: 'AAAB',
      );
      final restored = Stack.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, 'a');
      expect(restored.name, 'Cold');
      expect(restored.sats, 100000000);
      expect(restored.imageData, 'AAAB');
    });

    test('copyWith leaves imageData unchanged by default', () {
      const s = Stack(
        id: 'a',
        name: 'Cold',
        sats: 1,
        imageData: 'AAAB',
      );
      expect(s.copyWith(name: 'Hot').imageData, 'AAAB');
    });

    test('copyWith(imageData:) updates the field', () {
      const s = Stack(id: 'a', name: 'Cold', sats: 1);
      expect(s.copyWith(imageData: 'BBBC').imageData, 'BBBC');
    });

    test('copyWith(clearImage: true) nulls imageData', () {
      const s = Stack(
        id: 'a',
        name: 'Cold',
        sats: 1,
        imageData: 'AAAB',
      );
      expect(s.copyWith(clearImage: true).imageData, isNull);
    });

    test('copyWith(clearImage: true) wins over imageData arg', () {
      const s = Stack(
        id: 'a',
        name: 'Cold',
        sats: 1,
        imageData: 'AAAB',
      );
      expect(
        s.copyWith(imageData: 'BBBC', clearImage: true).imageData,
        isNull,
      );
    });

    test('toJson omits colorKey when null', () {
      const s = Stack(id: 'a', name: 'Cold', sats: 1);
      expect(s.toJson().containsKey('colorKey'), isFalse);
    });

    test('toJson includes colorKey when set', () {
      const s = Stack(id: 'a', name: 'Cold', sats: 1, colorKey: 'amber');
      expect(s.toJson()['colorKey'], 'amber');
    });

    test('fromJson reads colorKey', () {
      final s = Stack.fromJson(const {
        'id': 'a',
        'name': 'Cold',
        'sats': 1,
        'colorKey': 'rust',
      });
      expect(s!.colorKey, 'rust');
    });

    test('fromJson ignores non-string colorKey', () {
      final s = Stack.fromJson(const {
        'id': 'a',
        'name': 'Cold',
        'sats': 1,
        'colorKey': 42,
      });
      expect(s!.colorKey, isNull);
    });

    test('copyWith(clearColor: true) nulls colorKey', () {
      const s = Stack(id: 'a', name: 'Cold', sats: 1, colorKey: 'amber');
      expect(s.copyWith(clearColor: true).colorKey, isNull);
    });

    test('copyWith(clearColor: true) wins over colorKey arg', () {
      const s = Stack(id: 'a', name: 'Cold', sats: 1, colorKey: 'amber');
      expect(
        s.copyWith(colorKey: 'rust', clearColor: true).colorKey,
        isNull,
      );
    });
  });
}
