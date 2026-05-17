import 'dart:async';
import 'dart:convert';

import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeChannel()
      : _incoming = StreamController<dynamic>.broadcast(),
        _outgoing = StreamController<dynamic>(),
        _ready = Completer<void>()..complete();

  final StreamController<dynamic> _incoming;
  final StreamController<dynamic> _outgoing;
  final Completer<void> _ready;
  bool _sinkClosed = false;

  // Outgoing: messages sent via `sink.add()` show up here so tests can assert
  // the subscribe payload.
  Stream<dynamic> get sentMessages => _outgoing.stream;

  void emit(String text) => _incoming.add(text);
  void closeFromServer({Object? error}) {
    if (error != null) {
      _incoming.addError(error);
    }
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(this);

  @override
  Future<void> get ready => _ready.future;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final _FakeChannel _channel;

  @override
  void add(dynamic data) {
    if (_channel._sinkClosed) return;
    _channel._outgoing.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final v in stream) {
      add(v);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (_channel._sinkClosed) return;
    _channel._sinkClosed = true;
    await _channel._outgoing.close();
    if (!_channel._incoming.isClosed) await _channel._incoming.close();
  }

  @override
  Future<void> get done => _channel._outgoing.done;
}

String _tickerUpdate({String symbol = 'BTC/USD', double last = 50000.0}) =>
    jsonEncode({
      'channel': 'ticker',
      'type': 'update',
      'data': [
        {
          'symbol': symbol,
          'last': last,
        },
      ],
    });

void main() {
  group('KrakenStreamService', () {
    test('sends a v2 subscribe message with all 7 BTC pairs on start', () async {
      final channel = _FakeChannel();
      final svc = KrakenStreamService(channelFactory: (_) => channel);
      addTearDown(svc.dispose);

      svc.start();

      final firstSent = await channel.sentMessages.first;
      final decoded = jsonDecode(firstSent as String) as Map<String, dynamic>;
      expect(decoded['method'], 'subscribe');
      final params = decoded['params'] as Map<String, dynamic>;
      expect(params['channel'], 'ticker');
      expect(
        params['symbol'],
        equals(KrakenStreamService.pairs),
      );
    });

    test('parses ticker updates into KrakenTick events', () async {
      final channel = _FakeChannel();
      final svc = KrakenStreamService(channelFactory: (_) => channel);
      addTearDown(svc.dispose);
      svc.start();

      // Wait a microtask so the subscribe send completes before we feed ticks.
      await Future<void>.delayed(Duration.zero);

      final received = <KrakenTick>[];
      final sub = svc.ticks.listen(received.add);
      addTearDown(sub.cancel);

      channel.emit(_tickerUpdate(symbol: 'BTC/USD', last: 50123.45));
      channel.emit(_tickerUpdate(symbol: 'BTC/EUR', last: 47000.0));

      // Drain microtasks so the broadcast subscriber sees the events.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0].pairCode, 'BTC/USD');
      expect(received[0].last, 50123.45);
      expect(received[1].pairCode, 'BTC/EUR');
    });

    test('ignores heartbeat and non-update channel frames', () async {
      final channel = _FakeChannel();
      final svc = KrakenStreamService(channelFactory: (_) => channel);
      addTearDown(svc.dispose);
      svc.start();
      await Future<void>.delayed(Duration.zero);

      final received = <KrakenTick>[];
      final sub = svc.ticks.listen(received.add);
      addTearDown(sub.cancel);

      channel.emit(jsonEncode({'channel': 'heartbeat'}));
      channel.emit(jsonEncode({'channel': 'status', 'type': 'update', 'data': []}));
      channel.emit(jsonEncode({'channel': 'ticker', 'type': 'subscribe'}));

      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
    });

    test('reconnects with backoff after the channel closes', () {
      fakeAsync((async) {
        final channels = <_FakeChannel>[];
        final svc = KrakenStreamService(channelFactory: (_) {
          final c = _FakeChannel();
          channels.add(c);
          return c;
        });

        svc.start();
        async.flushMicrotasks();
        expect(channels, hasLength(1));

        // Server drops the connection. Client should schedule a 1s reconnect.
        channels[0].closeFromServer();
        async.flushMicrotasks();
        expect(channels, hasLength(1)); // not yet — backoff timer pending

        async.elapse(const Duration(seconds: 1));
        expect(channels, hasLength(2)); // reconnected after 1s

        // Drop again — second backoff is 2s.
        channels[1].closeFromServer();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(channels, hasLength(2));
        async.elapse(const Duration(milliseconds: 1500));
        expect(channels, hasLength(3));

        // First successful message resets the failure count, so the next drop
        // schedules a 1s reconnect again.
        channels[2].emit(_tickerUpdate());
        async.flushMicrotasks();
        channels[2].closeFromServer();
        async.elapse(const Duration(seconds: 1));
        expect(channels, hasLength(4));

        svc.dispose();
      });
    });

    test('stop() cancels reconnect timers and prevents new connections', () {
      fakeAsync((async) {
        final channels = <_FakeChannel>[];
        final svc = KrakenStreamService(channelFactory: (_) {
          final c = _FakeChannel();
          channels.add(c);
          return c;
        });
        svc.start();
        async.flushMicrotasks();
        channels[0].closeFromServer();
        svc.stop();
        async.elapse(const Duration(seconds: 30));
        expect(channels, hasLength(1));
        svc.dispose();
      });
    });

    test('dispose() closes the broadcast stream', () async {
      final channel = _FakeChannel();
      final svc = KrakenStreamService(channelFactory: (_) => channel);
      svc.start();
      await Future<void>.delayed(Duration.zero);

      var done = false;
      final sub = svc.ticks.listen((_) {}, onDone: () => done = true);
      await svc.dispose();
      await sub.cancel();
      expect(done, isTrue);
    });
  });
}
