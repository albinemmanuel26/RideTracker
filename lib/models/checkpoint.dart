class Checkpoint {
  static const String commonCategory = '40&100';

  /// Trim category values without translating aliases.
  static String normalizeCategory(String value) => value.trim();

  final String id;
  final String name;
  final String category;
  final bool isActive;

  const Checkpoint({
    required this.id,
    required this.name,
    required this.category,
    required this.isActive,
  });

  factory Checkpoint.fromJson(Map<String, dynamic> json) {
    return Checkpoint(
      id: json['checkpoint_id']?.toString() ?? '',
      name: json['checkpoint_name']?.toString() ?? '',
      category: normalizeCategory(json['category']?.toString() ?? ''),
      // Older getCheckpoints responses omit this field and return active rows only.
      isActive:
          !json.containsKey('is_active') ||
          json['is_active'] == true ||
          json['is_active']?.toString().trim().toUpperCase() == 'TRUE',
    );
  }

  @override
  String toString() => name;
}
