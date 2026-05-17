import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../api/price_data.dart';

/// Stores BTC daily history as packed binary (16 bytes per point: int64 ms +
/// float64 USD) in a file under the app's documents directory. JSON in
/// SharedPreferences would re-encode the entire series on every save and grow
/// linearly forever; this format halves the on-disk size and avoids the
/// SharedPreferences string-roundtrip cost.
class BtcHistoryCache {
  BtcHistoryCache({Directory? directory}) : _overrideDirectory = directory;

  static const String fileName = 'btc_history.bin';
  static const int _bytesPerPoint = 16;

  final Directory? _overrideDirectory;
  File? _file;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = _overrideDirectory ?? await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/$fileName');
  }

  Future<List<HistoryPoint>> load() async {
    final file = await _resolveFile();
    if (!await file.exists()) return const [];
    final bytes = await file.readAsBytes();
    if (bytes.length < _bytesPerPoint) return const [];
    // Trim any trailing partial record from a torn write.
    final usable = bytes.length - (bytes.length % _bytesPerPoint);
    final view = ByteData.sublistView(bytes, 0, usable);
    final count = usable ~/ _bytesPerPoint;
    final out = List<HistoryPoint>.generate(count, (i) {
      final offset = i * _bytesPerPoint;
      return HistoryPoint(
        view.getInt64(offset, Endian.little),
        view.getFloat64(offset + 8, Endian.little),
      );
    }, growable: false);
    return out;
  }

  Future<void> save(List<HistoryPoint> history) async {
    final file = await _resolveFile();
    final buffer = ByteData(history.length * _bytesPerPoint);
    for (var i = 0; i < history.length; i++) {
      final p = history[i];
      final offset = i * _bytesPerPoint;
      buffer.setInt64(offset, p.timeMs, Endian.little);
      buffer.setFloat64(offset + 8, p.priceUsd, Endian.little);
    }
    // Atomic-ish write: stage to a sibling temp file, then rename. Avoids a
    // half-written file if the app is killed mid-flush.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(buffer.buffer.asUint8List(), flush: true);
    await tmp.rename(file.path);
  }
}
