import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ride_track/services/local_storage_service.dart';
import 'package:ride_track/services/rider_service.dart';

// Opt-in read-only backend diagnostic; never logs rider details or credentials.
void main() {
  test(
    'live repeated parallel refresh downloads and saves both lists',
    () async {
      SharedPreferences.setMockInitialValues({});
      await LocalStorageService.init();
      for (var attempt = 1; attempt <= 2; attempt++) {
        final clock = Stopwatch()..start();
        final warning = await RiderService.refresh();
        expect(warning, isNull);
        expect(RiderService.riderDownload, isNull);
        expect(RiderService.riderDownloadError, isNull);
        expect(LocalStorageService.riderList, isNotNull);
        expect(LocalStorageService.checkpoints, isNotEmpty);
        // ignore: avoid_print
        print(
          'Refresh $attempt: ${clock.elapsedMilliseconds} ms; '
          '${LocalStorageService.riderList!.riders.length} riders; '
          '${LocalStorageService.checkpoints.length} checkpoints saved.',
        );
      }
    },
    skip: !const bool.fromEnvironment('LIVE_REFRESH'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
