import 'api_service.dart';
import 'local_storage_service.dart';

class RiderService {
  static Future<String?>? riderDownload;
  static String? riderDownloadError;

  static Future<String?> downloadRiderList() {
    return riderDownload ??= _downloadRiderList();
  }

  static Future<String?> _downloadRiderList() async {
    riderDownloadError = null;
    try {
      final riders = await ApiService.getRiders();
      await LocalStorageService.saveRiderList(riders);
    } catch (e) {
      riderDownloadError = e.toString();
    } finally {
      riderDownload = null;
    }
    return riderDownloadError;
  }

  // A warning means riders succeeded; exceptions mean riders failed.
  static Future<String?> refresh({
    bool downloadRiders = true,
    bool downloadCheckpoints = true,
    void Function(String? error)? onRidersDone,
    void Function(String? error)? onCheckpointsDone,
  }) async {
    String? riderError;
    String? checkpointError;
    Future<void> ridersDownload() async {
      riderError = await downloadRiderList();
      onRidersDone?.call(riderError);
    }

    Future<void> checkpointsDownload() async {
      try {
        final checkpoints = await ApiService.getCheckpoints();
        if (checkpoints.isEmpty ||
            checkpoints.any(
              (c) =>
                  c.id.trim().isEmpty ||
                  c.name.trim().isEmpty ||
                  !c.isActive ||
                  !['40', '100', '40&100'].contains(c.category),
            )) {
          throw const ApiException('No valid checkpoint options received.');
        }
        await LocalStorageService.saveCheckpoints(checkpoints);
      } catch (e) {
        checkpointError = e.toString();
      }
      onCheckpointsDone?.call(checkpointError);
    }

    await Future.wait([
      if (downloadRiders) ridersDownload(),
      if (downloadCheckpoints) checkpointsDownload(),
    ]);
    if (riderError != null) {
      throw ApiException(
        'Rider master update failed: $riderError\n${checkpointError == null ? "Checkpoints updated successfully." : "Checkpoint update also failed: $checkpointError"}\nRetry the download or cancel.',
      );
    }
    if (checkpointError != null) {
      return 'Rider master updated successfully. Checkpoint master update failed: $checkpointError\n${LocalStorageService.checkpoints.isEmpty ? "No saved checkpoints are available; checkpoint selection is required before scanning." : "Previously saved checkpoint options will be used."}';
    }
    return null;
  }
}
