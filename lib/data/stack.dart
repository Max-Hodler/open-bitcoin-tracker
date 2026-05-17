class Stack {
  static const int maxNameLength = 24;

  const Stack({
    required this.id,
    required this.name,
    required this.sats,
    this.isHidden = false,
  });

  final String id;
  final String name;
  final int sats;
  final bool isHidden;

  Stack copyWith({String? id, String? name, int? sats, bool? isHidden}) {
    return Stack(
      id: id ?? this.id,
      name: name ?? this.name,
      sats: sats ?? this.sats,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sats': sats,
        if (isHidden) 'isHidden': true,
      };

  static Stack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final sats = raw['sats'];
    if (id is! String || name is! String || sats is! num) return null;
    return Stack(
      id: id,
      name: name,
      sats: sats.toInt(),
      isHidden: raw['isHidden'] == true,
    );
  }
}
