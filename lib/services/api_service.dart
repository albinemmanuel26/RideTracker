import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../constants/app_constants.dart';
import '../models/checkpoint.dart';
import '../models/rider.dart';
import '../models/volunteer.dart';

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

/// Thrown when the server returns status == "duplicate".
class DuplicateScanException extends ApiException {
  const DuplicateScanException(super.message);
}

class _UncertainScanException extends ApiException {
  const _UncertainScanException(super.message);
}

class _RetryableApiException extends ApiException {
  const _RetryableApiException(super.message);
}

// ---------------------------------------------------------------------------
// API Service
// ---------------------------------------------------------------------------

class ApiService {
  static final Uri _baseUri = Uri.parse(AppConstants.apiUrl);

  // Only reads and login use this helper. Repeating login only refreshes
  // last_login. Each retry starts at the exec URL; scans must not be replayed.
  static Future<Map<String, dynamic>> _retrySafePost(
    Map<String, dynamic> body,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _post(body);
      } on _RetryableApiException {
        if (attempt == 2) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
  }

  /// Posts once, then fetches the Apps Script Content Service result via GET.
  /// Redirects never replay the POST body, which may record a rider scan.
  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final encodedBody = jsonEncode({...body, 'key': AppConstants.apiKey});
    final httpClient = HttpClient();
    var redirects = 0;

    try {
      Uri uri = _baseUri;

      // Step 1 — POST to the Apps Script exec URL.
      final request = await httpClient
          .postUrl(uri)
          .timeout(const Duration(seconds: 30));
      request
        ..followRedirects = false
        ..headers.set('Content-Type', 'application/json')
        ..write(encodedBody);

      var response = await request.close().timeout(const Duration(seconds: 30));

      // Content Service redirects to a one-time result URL. Follow the whole
      // chain, but bound it to avoid redirect loops. Never resend credentials.
      // HttpClientResponse.isRedirect is false for POST + 302 in dart:io.
      // Inspect the status explicitly for Apps Script's POST response.
      while (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final status = response.statusCode;
        await response.drain<void>().timeout(const Duration(seconds: 30));

        if (location == null || location.isEmpty) {
          throw const ApiException('Invalid redirect from server.');
        }
        if (++redirects > 5) {
          throw const ApiException(
            'Too many server redirects. Check the Apps Script deployment.',
          );
        }

        final nextUri = uri.resolve(location);
        if (nextUri.host == 'accounts.google.com') {
          throw const ApiException(
            'The backend requires Google sign-in. Check the Apps Script '
            'web app access settings.',
          );
        }
        if (nextUri.scheme != 'https' ||
            nextUri.userInfo.isNotEmpty ||
            nextUri.port != 443 ||
            (nextUri.host != 'script.google.com' &&
                nextUri.host != 'script.googleusercontent.com')) {
          throw const ApiException('Unexpected redirect from server.');
        }
        // 307/308 require preserving the method. Do not silently turn an
        // unexecuted POST into a GET or replay a potentially completed scan.
        if (redirects == 1 && (status == 307 || status == 308)) {
          throw const ApiException(
            'Unexpected POST redirect. Check the Apps Script deployment URL.',
          );
        }

        uri = nextUri;
        final getRequest = await httpClient
            .getUrl(uri)
            .timeout(const Duration(seconds: 30));
        getRequest.followRedirects = false;
        response = await getRequest.close().timeout(
          const Duration(seconds: 30),
        );
      }

      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        if (body['action'] == 'scanCheckpoint') {
          throw _UncertainScanException(
            'Could not retrieve the check-in result (${response.statusCode}). '
            'The check-in may already be saved. Retrying can create another row.',
          );
        }
        if (const {
              408,
              429,
              500,
              502,
              503,
              504,
            }.contains(response.statusCode) ||
            (response.statusCode == 404 && redirects > 0)) {
          throw _RetryableApiException(
            'Server temporarily unavailable (${response.statusCode}). Please try again.',
          );
        }
        throw ApiException(
          'Server error (${response.statusCode}). Please try again.',
        );
      }

      try {
        final data = jsonDecode(responseBody);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } on FormatException {
        // Login and deployment error pages can return HTML with status 200.
      }
      if (body['action'] == 'scanCheckpoint') {
        throw const _UncertainScanException('Unexpected check-in response.');
      }
      throw const _RetryableApiException(
        'The backend returned an unexpected response. Please try again. '
        'If this keeps happening, check the Apps Script deployment URL '
        'and web app access settings.',
      );
    } on ApiException {
      rethrow;
    } on SocketException {
      if (body['action'] == 'scanCheckpoint') {
        throw const _UncertainScanException('Check-in connection lost.');
      }
      throw const _RetryableApiException(
        'No internet connection. Check your network and try again.',
      );
    } on TimeoutException {
      if (body['action'] == 'scanCheckpoint') {
        throw const _UncertainScanException('Check-in response timed out.');
      }
      throw const _RetryableApiException(
        'Request timed out. The server may be busy — please try again.',
      );
    } catch (e) {
      throw ApiException('Network error: $e');
    } finally {
      httpClient.close(force: true);
    }
  }

  // ── loginVolunteer ─────────────────────────────────────────────────────────
  /// Authenticates a volunteer via the Volunteers sheet.
  /// Actions: loginVolunteer
  /// Checks: phone match, PIN match, is_active == TRUE.
  /// On success updates last_login in sheet.
  /// Returns a [Volunteer] with name, phone, and role from the API response.
  static Future<Volunteer> loginVolunteer({
    required String phone,
    required String pin,
  }) async {
    final data = await _retrySafePost({
      'action': 'loginVolunteer',
      'phone': phone,
      'pin': pin,
    });

    if (data['status'] == 'success') {
      final v = data['volunteer'] as Map<String, dynamic>? ?? {};
      return Volunteer(
        name: v['name']?.toString() ?? phone,
        phone: v['phone']?.toString() ?? phone,
        role: v['role']?.toString() ?? 'scanner',
      );
    }

    throw ApiException(data['message']?.toString() ?? 'Invalid phone or PIN.');
  }

  /// Downloads both master sheets in a single response.
  static Future<RiderList> getRiders() async {
    final data = await _retrySafePost({'action': 'getRiders'});
    if (data['status'] != 'success') {
      throw ApiException(
        data['message']?.toString() ?? 'Could not download riders.',
      );
    }
    try {
      final groups = data['riders'] as Map<String, dynamic>;
      final riders = <Rider>[];
      for (final category in ['40', '100']) {
        for (final raw in groups[category] as List) {
          final rider = Rider.fromJson(raw as Map<String, dynamic>);
          if (rider.category != category) throw const FormatException();
          riders.add(rider);
        }
      }
      return RiderList(riders, DateTime.now());
    } catch (_) {
      throw const ApiException(
        'The rider list is incomplete or invalid. Please contact an organizer.',
      );
    }
  }

  // ── getCheckpoints ─────────────────────────────────────────────────────────
  /// Returns active checkpoints from the Checkpoints_Master sheet.
  /// Each entry includes checkpoint_id, checkpoint_name, category.
  static Future<List<Checkpoint>> getCheckpoints() async {
    final data = await _retrySafePost({'action': 'getCheckpoints'});

    if (data['status'] == 'success') {
      try {
        final raw = data['checkpoints'] as List;
        return raw
            .map((e) => Checkpoint.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        throw const ApiException(
          'Invalid checkpoint list. Please retry the download.',
        );
      }
    }

    throw ApiException(
      data['message']?.toString() ?? 'Failed to load checkpoints.',
    );
  }

  static Future<void> uploadScanEntry(Map<String, dynamic> entry) async {
    final data = await _post({...entry, 'action': 'scanCheckpoint'});
    if (data['status'] != 'success') {
      throw ApiException(
        data['message']?.toString() ?? 'Upload not confirmed.',
      );
    }
    if (data['entry_id'] != entry['entry_id']) {
      throw const ApiException(
        'Entry ID not confirmed. Update the backend and sync again.',
      );
    }
  }

  static Future<Map<String, dynamic>> syncScanEntries(
    List<Map<String, dynamic>> entries,
  ) async {
    final data = await _post({'action': 'syncScans', 'entries': entries});
    if (data['status'] != 'success' ||
        data['confirmed_ids'] is! List ||
        data['errors'] is! Map) {
      throw ApiException(
        data['message']?.toString() ?? 'Sync not confirmed. Please try again.',
      );
    }
    return data;
  }

  // ── scanCheckpoint ─────────────────────────────────────────────────────────
  /// Validates and records a rider scan into the Riders_Scan sheet.
  ///
  /// Server checks:
  ///  • rider_id exists in Riders_Master
  ///  • category matches master record
  ///  • checkpoint is valid for the category
  ///  • scanned_by (volunteer phone) resolves to a known volunteer
  ///
  /// Returns the scan data map `{rider_name, category, scanned_by}` on success,
  /// where scanned_by is the resolved volunteer name.
  /// Repeated submissions are allowed. Legacy servers may reject duplicates.
  /// Throws [ApiException] for all other errors.
  static Future<Map<String, dynamic>> scanCheckpoint({
    required String riderId,
    required String category,
    required String checkpoint,
    required String scannedBy,
  }) async {
    late final Map<String, dynamic> data;
    try {
      data = await _post({
        'action': 'scanCheckpoint',
        'rider_id': riderId,
        'category': category,
        'checkpoint': checkpoint,
        'scanned_by': scannedBy,
      });
    } on _UncertainScanException {
      throw const ApiException(
        'Could not confirm whether the check-in was saved. '
        'Wait briefly before retrying. Retrying may create another check-in row.',
      );
    }

    if (data['status'] == 'success') {
      return data['data'] as Map<String, dynamic>;
    }

    if (data['status'] == 'duplicate') {
      throw DuplicateScanException(
        data['message']?.toString() ?? 'Already scanned at this checkpoint.',
      );
    }

    throw ApiException(
      data['message']?.toString() ?? 'Scan failed. Please try again.',
    );
  }

  // ── verifyRider ────────────────────────────────────────────────────────────
  /// Read-only lookup; never resubmits a scan.
  static Future<bool> checkScanStatus({
    required String riderId,
    required String category,
    required String checkpoint,
  }) => _checkScanStatus(
    riderId: riderId,
    category: category,
    checkpoint: checkpoint,
    retry: true,
  );

  static Future<bool> _checkScanStatus({
    required String riderId,
    required String category,
    required String checkpoint,
    required bool retry,
  }) async {
    final data = await (retry ? _retrySafePost : _post)({
      'action': 'checkScanStatus',
      'rider_id': riderId,
      'category': category,
      'checkpoint': checkpoint,
    });
    if (data['status'] == 'success' && data['recorded'] is bool) {
      return data['recorded'] as bool;
    }
    throw const ApiException('Check-in status unavailable.');
  }

  /// Verifies a rider by ID and retrieves their category.
  /// Returns a map `{rider_id, rider_name, category}` on success.
  /// Throws [ApiException] if rider verification fails.
  static Future<Map<String, dynamic>> verifyRider({
    required String riderId,
  }) async {
    final data = await _retrySafePost({
      'action': 'verifyRider',
      'rider_id': riderId,
    });

    if (data['status'] == 'success') {
      return data['data'] as Map<String, dynamic>;
    }

    throw ApiException(
      data['message']?.toString() ?? 'Rider verification failed.',
    );
  }
}
