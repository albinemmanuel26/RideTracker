class Rider {
  final String id;
  final String name;
  final String category;

  const Rider({required this.id, required this.name, required this.category});

  factory Rider.fromJson(Map<String, dynamic> json) {
    final id = json['rider_id']?.toString().trim() ?? '';
    final name = json['rider_name']?.toString().trim() ?? '';
    final category = json['category']?.toString().trim() ?? '';
    if (id.isEmpty || !['40', '100'].contains(category)) {
      throw const FormatException('Invalid rider details');
    }
    return Rider(id: id, name: name.isEmpty ? 'NA' : name, category: category);
  }

  Map<String, dynamic> toJson() => {
    'rider_id': id,
    'rider_name': name,
    'category': category,
  };
}

class RiderList {
  final Map<String, Rider> riders;
  final DateTime updatedAt;

  RiderList(List<Rider> entries, this.updatedAt)
    : riders = Map.unmodifiable({
        for (final rider in entries) rider.id: rider,
      }) {
    if (riders.length != entries.length) {
      throw const FormatException('Duplicate rider IDs in rider list');
    }
  }

  factory RiderList.fromJson(Map<String, dynamic> json) => RiderList(
    (json['riders'] as List)
        .map((e) => Rider.fromJson(e as Map<String, dynamic>))
        .toList(),
    DateTime.parse(json['updated_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'riders': riders.values.map((r) => r.toJson()).toList(),
  };
}
