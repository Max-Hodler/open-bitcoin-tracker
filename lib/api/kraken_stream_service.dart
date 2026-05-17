import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class KrakenTick {
  const KrakenTick({required this.pairCode, required this.last});

  final String pairCode;
  final double last;
}

typedef KrakenChannelFactory = WebSocketChannel Function(Uri uri);

WebSocketChannel _defaultFactory(Uri uri) => WebSocketChannel.connect(uri);

class KrakenStreamService {
  KrakenStreamService({KrakenChannelFactory? channelFactory})
      : _factory = channelFactory ?? _defaultFactory;

  static const String url = 'wss://ws.kraken.com/v2';
  // Kraken WS v2 quotes BTC against the major fiats with the `BTC/` prefix; v1
  // used `XBT/`, but `subscribe` on v2 returns "Currency pair not supported"
  // for the XBT form. The REST OHLC endpoint still uses the legacy `XBTUSD`
  // altname — single-sourced inside [KrakenOhlcClient].
  static const List<String> pairs = [
    'BTC/USD',
    'BTC/EUR',
    'BTC/GBP',
    'BTC/JPY',
    'BTC/CAD',
    'BTC/AUD',
    'BTC/CHF',
  ];

  // 1s, 2s, 4s, 8s, 16s, 30s (capped). Reset on the first message after
  // reconnect so a transient blip doesn't leave us stuck at a long delay.
  static const List<int> _backoffSeconds = [1, 2, 4, 8, 16, 30];

  final KrakenChannelFactory _factory;
  final StreamController<KrakenTick> _controller =
      StreamController<KrakenTick>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  int _failures = 0;
  bool _disposed = false;
  bool _running = false;

  Stream<KrakenTick> get ticks => _controller.stream;

  void start() {
    if (_disposed || _running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  /// Tear down the current connection and reconnect immediately, resetting
  /// backoff so a manual retry doesn't have to wait out the previous delay.
  void restart() {
    if (_disposed) return;
    stop();
    _failures = 0;
    start();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    stop();
    await _controller.close();
  }

  void _connect() {
    if (_disposed || !_running) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final WebSocketChannel channel;
    try {
      channel = _factory(Uri.parse(url));
    } on Object catch (e) {
      if (kDebugMode) debugPrint('Kraken WS connect failed: $e');
      _scheduleReconnect();
      return;
    }
    _channel = channel;

    _sub = channel.stream.listen(
      _onMessage,
      onError: (Object err, StackTrace _) {
        if (kDebugMode) debugPrint('Kraken WS error: $err');
        _onDone();
      },
      onDone: _onDone,
      cancelOnError: true,
    );

    final subscribe = jsonEncode({
      'method': 'subscribe',
      'params': {
        'channel': 'ticker',
        'symbol': pairs,
      },
    });
    try {
      channel.sink.add(subscribe);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('Kraken WS subscribe send failed: $e');
      _onDone();
    }
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    // Any successful message resets the failure count so a long-running
    // session doesn't stay stuck at the 30s cap if it earlier reconnected.
    _failures = 0;

    final String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      text = utf8.decode(raw);
    } else {
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('Kraken WS decode failed: $e');
      return;
    }
    if (decoded is! Map) return;

    final channel = decoded['channel'];
    if (channel == 'heartbeat') return;
    if (channel != 'ticker') return;
    if (decoded['type'] != 'update' && decoded['type'] != 'snapshot') return;

    final data = decoded['data'];
    if (data is! List) return;
    for (final entry in data) {
      if (entry is! Map) continue;
      final symbol = entry['symbol'];
      final last = entry['last'];
      if (symbol is! String || last is! num) continue;
      _controller.add(KrakenTick(pairCode: symbol, last: last.toDouble()));
    }
  }

  void _onDone() {
    if (_disposed) return;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    if (!_running) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_running) return;
    final idx = min(_failures, _backoffSeconds.length - 1);
    final delay = Duration(seconds: _backoffSeconds[idx]);
    _failures++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }
}
