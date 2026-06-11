import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStateNotifier> _build() async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  return AppStateNotifier(AppStateRepository(prefs));
}

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues(const {});
  return SharedPreferences.getInstance();
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

  test('setCurrency notifies and persists after the debounce window',
      () async {
    final prefs = await _freshPrefs();
    fakeAsync((async) {
      final n = AppStateNotifier(AppStateRepository(prefs));
      var notifies = 0;
      n.addListener(() => notifies++);

      n.setCurrency(Currency.gbp);
      async.flushMicrotasks();

      expect(notifies, 1);
      // Settings churn is debounced — nothing on disk yet.
      expect(prefs.getString('btc_tracker'), isNull);

      async.elapse(AppStateNotifier.saveDebounceWindow);
      async.flushMicrotasks();
      expect(prefs.getString('btc_tracker'), contains('"currency":"GBP"'));
    });
  });

  group('save debouncing', () {
    test('converter keystrokes coalesce into one deferred write', () async {
      final prefs = await _freshPrefs();
      fakeAsync((async) {
        final n = AppStateNotifier(AppStateRepository(prefs));

        n.setConverterFiatModeEntry(raw: '1', activeSlot: 'top');
        n.setConverterFiatModeEntry(raw: '12', activeSlot: 'top');
        n.setConverterFiatModeEntry(raw: '123', activeSlot: 'top');
        async.flushMicrotasks();
        expect(prefs.getString('btc_tracker'), isNull);

        async.elapse(AppStateNotifier.saveDebounceWindow);
        async.flushMicrotasks();
        // One write carrying the latest value.
        expect(
          prefs.getString('btc_tracker'),
          contains('"converterFiatModeRaw":"123"'),
        );
      });
    });

    test('window anchors to the first unsaved mutation, so continuous '
        'typing cannot postpone durability past the window', () async {
      final prefs = await _freshPrefs();
      fakeAsync((async) {
        final n = AppStateNotifier(AppStateRepository(prefs));
        const window = AppStateNotifier.saveDebounceWindow;

        n.setConverterFiatModeEntry(raw: '1', activeSlot: 'top');
        async.elapse(window * 0.6);
        // A mutation mid-window must NOT push the deadline out.
        n.setConverterFiatModeEntry(raw: '12', activeSlot: 'top');
        async.elapse(window * 0.4);
        async.flushMicrotasks();

        expect(
          prefs.getString('btc_tracker'),
          contains('"converterFiatModeRaw":"12"'),
        );
      });
    });

    test('stack mutations persist immediately, flushing pending settings '
        'churn with them', () async {
      final prefs = await _freshPrefs();
      fakeAsync((async) {
        final n = AppStateNotifier(AppStateRepository(prefs));

        n.setCurrency(Currency.gbp);
        n.addStack(const Stack(id: 'a', name: 'A', sats: 1));
        async.flushMicrotasks();

        // No debounce wait: both the stack and the settings change are
        // already on disk.
        final raw = prefs.getString('btc_tracker')!;
        expect(raw, contains('"id":"a"'));
        expect(raw, contains('"currency":"GBP"'));
      });
    });

    test('lifecycle pause flushes a pending debounced write', () async {
      final prefs = await _freshPrefs();
      fakeAsync((async) {
        final n = AppStateNotifier(AppStateRepository(prefs));

        n.setConverterFiatModeEntry(raw: '42', activeSlot: 'top');
        async.flushMicrotasks();
        expect(prefs.getString('btc_tracker'), isNull);

        n.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.flushMicrotasks();
        expect(
          prefs.getString('btc_tracker'),
          contains('"converterFiatModeRaw":"42"'),
        );
      });
    });
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

  group('cycleCurrency', () {
    test('returns false and is no-op when the ring is empty / singleton', () async {
      final n = await _build();
      // Default seed has at least one selected currency. Force a singleton.
      n.setSelectedCurrencies([Currency.usd]);
      final before = n.currency;
      expect(n.cycleCurrency(1), isFalse);
      expect(n.cycleCurrency(-1), isFalse);
      expect(n.currency, before);
    });

    test('steps forward through the ring', () async {
      final n = await _build();
      n.setSelectedCurrencies([Currency.usd, Currency.eur, Currency.gbp]);
      n.setCurrency(Currency.usd);

      expect(n.cycleCurrency(1), isTrue);
      expect(n.currency, Currency.eur);
      expect(n.cycleCurrency(1), isTrue);
      expect(n.currency, Currency.gbp);
      // Wraps around.
      expect(n.cycleCurrency(1), isTrue);
      expect(n.currency, Currency.usd);
    });

    test('steps backward and wraps', () async {
      final n = await _build();
      n.setSelectedCurrencies([Currency.usd, Currency.eur, Currency.gbp]);
      n.setCurrency(Currency.usd);

      expect(n.cycleCurrency(-1), isTrue);
      expect(n.currency, Currency.gbp);
    });

    test('snaps to first ring entry if active currency is outside the ring', () async {
      final n = await _build();
      // Drop EUR from the ring while it is the active currency, then re-add a
      // different set. setSelectedCurrencies will snap if active isn't in the
      // new list, so to engineer "active not in ring" we set the ring first
      // then manually setCurrency to something the ring doesn't contain.
      n.setSelectedCurrencies([Currency.usd, Currency.eur]);
      n.setCurrency(Currency.jpy);

      // Stepping forward from "outside the ring" should land on ring[0+1].
      expect(n.cycleCurrency(1), isTrue);
      expect(n.currency, Currency.eur);
    });
  });
}
