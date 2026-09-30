import 'package:flutter_test/flutter_test.dart';
import 'package:ride_track/models/rider.dart';

void main() {
  test('missing or blank names default to NA with valid rider ID', () {
    for (final name in [null, '', '   ']) {
      expect(
        Rider.fromJson({
          'rider_id': '123',
          'category': '40',
          'rider_name': name,
        }).name,
        'NA',
      );
    }
    expect(Rider.fromJson({'rider_id': '123', 'category': '100'}).name, 'NA');
    expect(() => Rider.fromJson({'category': '40'}), throwsFormatException);
  });
}
