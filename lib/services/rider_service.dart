import 'api_service.dart';
import 'local_storage_service.dart';

class RiderService {
  static Future<void> refresh() async {
    final list = await ApiService.getRiders();
    try {
      await LocalStorageService.saveRiderList(list);
    } catch (_) {
      throw const ApiException(
        'Could not save the rider list. Please try again.',
      );
    }
  }
}
