class Checkpoint {
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
      category: json['category']?.toString() ?? '',
      isActive: json['is_active'] == true || json['is_active'] == 'TRUE',
    );
  }

  @override
  String toString() => name;
}
