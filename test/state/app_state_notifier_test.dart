import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStateNotifier> _build() async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  return AppStateNotifier(AppStateRepository(prefs));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hydrates from repository on construction', () async {
    SharedPreferences.setMockInitialValues(const {
      'btc_tracker':
          '{"currency":"EUR","stacks":[{"id":"a","name":"Cold","sats":100}]}',
    });
    final prefs = await SharedPreferences.getInstance();
    final n = AppStateNotifier(AppStateRepository(prefs));

    expect(n.currency, Currency.eur);
    expect(n.stacks.single.name, 'Cold');
  });

  test('setCurrency notifies and persists', () async {
    final n = await _build();
    var notifies = 0;
    n.addListener(() => notifies++);

    n.setCurrency(Currency.gbp);
    await Future<void>.delayed(Duration.zero);

    expect(notifies, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('btc_tracker'), contains('"currency":"GBP"'));
  });

  test('addStack appends in order', () async {
    final n = await _build();
    n.addStack(const Stack(id: 'a', name: 'A', sats: 1));
    n.addStack(const Stack(id: 'b', name: 'B', sats: 2));
    expect(n.stacks.map((s) => s.id), ['a', 'b']);
  });

  test('updateStack mutates only the targeted stack', () async {
    final n = await _build();
    n.addStack(const Stack(id: 'a', name: 'A', sats: 1));
    n.addStack(const Stack(id: 'b', name: 'B', sats: 2));

    n.updateStack('b', (s) => s.copyWith(sats: 99));

    expect(n.stacks.firstWhere((s) => s.id == 'a').sats, 1);
    expect(n.stacks.firstWhere((s) => s.id == 'b').sats, 99);
  });

  test('removeStack drops by id', () async {
    final n = await _build();
    n.addStack(const Stack(id: 'a', name: 'A', sats: 1));
    n.addStack(const Stack(id: 'b', name: 'B', sats: 2));
    n.removeStack('a');
    expect(n.stacks.map((s) => s.id), ['b']);
  });

  test('reorderStacks handles forward move with ReorderableList offset', () async {
    final n = await _build();
    n.addStack(const Stack(id: 'a', name: 'A', sats: 1));
    n.addStack(const Stack(id: 'b', name: 'B', sats: 2));
    n.addStack(const Stack(id: 'c', name: 'C', sats: 3));

    // Moving index 0 past index 2 (ReorderableList passes newIndex = 3).
    n.reorderStacks(0, 3);
    expect(n.stacks.map((s) => s.id), ['b', 'c', 'a']);
  });

  test('reorderStacks handles backward move', () async {
    final n = await _build();
    n.addStack(const Stack(id: 'a', name: 'A', sats: 1));
    n.addStack(const Stack(id: 'b', name: 'B', sats: 2));
    n.addStack(const Stack(id: 'c', name: 'C', sats: 3));

    n.reorderStacks(2, 0);
    expect(n.stacks.map((s) => s.id), ['c', 'a', 'b']);
  });

  test('no-op reorder does not notify', () async {
    final n = await _build();
    n.addStack(const Stack(id: 'a', name: 'A', sats: 1));
    var notifies = 0;
    n.addListener(() => notifies++);

    n.reorderStacks(0, 0);
    expect(notifies, 0);
  });
}
