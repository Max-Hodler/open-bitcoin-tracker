class HistoryPoint {
  const HistoryPoint(this.timeMs, this.priceUsd);

  final int timeMs;
  final double priceUsd;
}

/// A single (timestamp, value) pair rendered by [AreaChart].
class PricePoint {
  const PricePoint(this.t, this.price);
  final int t;
  final double price;
}
