class Volunteer {
  final String name;
  final String phone;
  final String role;

  const Volunteer({
    required this.name,
    required this.phone,
    required this.role,
  });

  factory Volunteer.fromJson(Map<String, dynamic> json) {
    return Volunteer(
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      role: json['role']?.toString() ?? 'scanner',
    );
  }
}
