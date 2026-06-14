class Stack {
  static const int maxNameLength = 24;

  const Stack({
    required this.id,
    required this.name,
    required this.sats,
    this.isHidden = false,
    this.imageData,
    this.colorKey,
    this.projectedPrice,
    this.projectedPriceCurrency,
  });

  final String id;
  final String name;
  final int sats;
  final bool isHidden;
  // Raw base64-encoded JPEG (no data: prefix), pre-processed to a fixed
  // 256x256 square so the encrypted stacks blob stays small and predictable.
  final String? imageData;
  // Palette key for the default initial-letter avatar (e.g. "gold"). Null
  // means the theme's bitcoin orange. Ignored when an [imageData] is set.
  final String? colorKey;
  // Last BTC price the user parked the future-value slider on, so the
  // projection is restored on the next visit. Stored together with the
  // currency it was set in ([projectedPriceCurrency], an ISO code) — a price
  // is meaningless without its unit, so we only restore it when the active
  // currency matches and otherwise fall back to the default. Null = never set.
  final double? projectedPrice;
  final String? projectedPriceCurrency;

  Stack copyWith({
    String? id,
    String? name,
    int? sats,
    bool? isHidden,
    String? imageData,
    bool clearImage = false,
    String? colorKey,
    bool clearColor = false,
    double? projectedPrice,
    String? projectedPriceCurrency,
    bool clearProjectedPrice = false,
  }) {
    return Stack(
      id: id ?? this.id,
      name: name ?? this.name,
      sats: sats ?? this.sats,
      isHidden: isHidden ?? this.isHidden,
      imageData: clearImage ? null : (imageData ?? this.imageData),
      colorKey: clearColor ? null : (colorKey ?? this.colorKey),
      projectedPrice:
          clearProjectedPrice ? null : (projectedPrice ?? this.projectedPrice),
      projectedPriceCurrency: clearProjectedPrice
          ? null
          : (projectedPriceCurrency ?? this.projectedPriceCurrency),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sats': sats,
        if (isHidden) 'isHidden': true,
        if (imageData != null) 'imageData': imageData,
        if (colorKey != null) 'colorKey': colorKey,
        if (projectedPrice != null) 'projectedPrice': projectedPrice,
        if (projectedPriceCurrency != null)
          'projectedPriceCurrency': projectedPriceCurrency,
      };

  static Stack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final sats = raw['sats'];
    if (id is! String || name is! String || sats is! num) return null;
    final image = raw['imageData'];
    final color = raw['colorKey'];
    final projected = raw['projectedPrice'];
    final projectedCurrency = raw['projectedPriceCurrency'];
    return Stack(
      id: id,
      name: name,
      sats: sats.toInt(),
      isHidden: raw['isHidden'] == true,
      imageData: image is String ? image : null,
      colorKey: color is String ? color : null,
      projectedPrice: projected is num ? projected.toDouble() : null,
      projectedPriceCurrency:
          projectedCurrency is String ? projectedCurrency : null,
    );
  }
}
