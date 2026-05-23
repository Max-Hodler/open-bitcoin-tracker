class HistoryPoint {
  const HistoryPoint(this.timeMs, this.priceUsd);

  final int timeMs;
  final double priceUsd;
}

/// A single (timestamp, value) pair rendered by [AreaChart]. The value's unit
/// is context-dependent: it's fiat for the BTC price chart, but the same
/// type is reused for the hashrate chart, where it carries EH/s.
class PricePoint {
  const PricePoint(this.t, this.price);
  final int t;
  final double price;
}
