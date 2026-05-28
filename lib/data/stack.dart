class Stack {
  static const int maxNameLength = 24;

  const Stack({
    required this.id,
    required this.name,
    required this.sats,
    this.isHidden = false,
    this.imageData,
    this.colorKey,
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

  Stack copyWith({
    String? id,
    String? name,
    int? sats,
    bool? isHidden,
    String? imageData,
    bool clearImage = false,
    String? colorKey,
    bool clearColor = false,
  }) {
    return Stack(
      id: id ?? this.id,
      name: name ?? this.name,
      sats: sats ?? this.sats,
      isHidden: isHidden ?? this.isHidden,
      imageData: clearImage ? null : (imageData ?? this.imageData),
      colorKey: clearColor ? null : (colorKey ?? this.colorKey),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sats': sats,
        if (isHidden) 'isHidden': true,
        if (imageData != null) 'imageData': imageData,
        if (colorKey != null) 'colorKey': colorKey,
      };

  static Stack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final sats = raw['sats'];
    if (id is! String || name is! String || sats is! num) return null;
    final image = raw['imageData'];
    final color = raw['colorKey'];
    return Stack(
      id: id,
      name: name,
      sats: sats.toInt(),
      isHidden: raw['isHidden'] == true,
      imageData: image is String ? image : null,
      colorKey: color is String ? color : null,
    );
  }
}
