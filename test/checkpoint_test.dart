import 'package:flutter_test/flutter_test.dart';
import 'package:ride_track/models/checkpoint.dart';

void main() {
  test('reads the common checkpoint category and trims whitespace', () {
    for (final category in ['40&100', ' 40&100 ']) {
      final checkpoint = Checkpoint.fromJson({'category': category});
      expect(checkpoint.category, '40&100');
      expect(checkpoint.isActive, isTrue);
    }
  });

  test('preserves individual categories and explicit active flags', () {
    for (final category in ['40', '100']) {
      final checkpoint = Checkpoint.fromJson({
        'category': category,
        'is_active': false,
      });
      expect(checkpoint.category, category);
      expect(checkpoint.isActive, isFalse);
    }
    expect(Checkpoint.fromJson({'is_active': true}).isActive, isTrue);
  });
}
