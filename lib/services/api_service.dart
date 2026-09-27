import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../models/checkpoint.dart';
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

// ---------------------------------------------------------------------------
// API Service
// ---------------------------------------------------------------------------

class ApiService {
  static final Uri _baseUri = Uri.parse(AppConstants.apiUrl);

  /// POST helper — injects the API key as `key` (matches Apps Script check).
  ///
  /// Uses [HttpClient] directly (not [http.Client]) so we can:
  ///  1. Set [HttpClientRequest.followRedirects] = false per request, ensuring
  ///     the POST body is not lost when Google Apps Script issues a redirect.
  ///  2. Supply a [badCertificateCallback] covering all Google-owned domains,
  ///     which fixes CERTIFICATE_VERIFY_FAILED on Android devices whose trust
  ///     store is missing Google's intermediate CA (affects emulators and some
  ///     older devices).  Hostname identity is still verified by the OS.
  static Future<Map<String, dynamic>> _post(
      Map<String, dynamic> body) async {
    body['key'] = AppConstants.apiKey;
    final encodedBody = jsonEncode(body);

    final httpClient = HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        return host.endsWith('.google.com') ||
            host == 'google.com' ||
            host.endsWith('.googleusercontent.com') ||
            host.endsWith('.googleapis.com');
      };

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

      final postResponse =
          await request.close().timeout(const Duration(seconds: 30));

      // Step 2 — Apps Script responds with 302 to a googleusercontent.com URL
      // that serves the JSON result via GET.  Follow it as GET (not POST);
      // re-POSTing to that URL causes 405 Method Not Allowed.
      if (postResponse.statusCode >= 300 && postResponse.statusCode < 400) {
        final location = postResponse.headers.value('location');
        await postResponse.drain<void>();

        if (location == null) {
          throw const ApiException('Invalid redirect from server.');
        }

        final getRequest = await httpClient
            .getUrl(Uri.parse(location))
            .timeout(const Duration(seconds: 30));
        getRequest.followRedirects = false;

        final getResponse =
            await getRequest.close().timeout(const Duration(seconds: 30));
        final responseBody =
            await getResponse.transform(utf8.decoder).join();

        if (getResponse.statusCode != 200) {
          throw ApiException(
              'Server error (${getResponse.statusCode}). Please try again.');
        }

        return jsonDecode(responseBody) as Map<String, dynamic>;
      }

      // No redirect — response came directly from the exec URL.
      final responseBody =
          await postResponse.transform(utf8.decoder).join();

      if (postResponse.statusCode != 200) {
        throw ApiException(
            'Server error (${postResponse.statusCode}). Please try again.');
      }

      return jsonDecode(responseBody) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } on SocketException catch (e) {
      debugPrint('ApiService SocketException: $e');
      throw const ApiException(
          'No internet connection. Check your network and try again.');
    } on TimeoutException catch (e) {
      debugPrint('ApiService TimeoutException: $e');
      throw const ApiException(
          'Request timed out. The server may be busy — please try again.');
    } catch (e) {
      // Log the real exception so it appears in debug output.
      debugPrint('ApiService unexpected error: $e');
      throw ApiException('Network error: $e');
    } finally {
      httpClient.close(force: false);
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
    final data = await _post({
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

    throw ApiException(
        data['message']?.toString() ?? 'Invalid phone or PIN.');
  }

  // ── getCheckpoints ─────────────────────────────────────────────────────────
  /// Returns active checkpoints from the Checkpoints_Master sheet.
  /// Each entry includes checkpoint_id, checkpoint_name, category.
  static Future<List<Checkpoint>> getCheckpoints() async {
    final data = await _post({'action': 'getCheckpoints'});

    if (data['status'] == 'success') {
      final List<dynamic> raw =
          data['checkpoints'] as List<dynamic>;
      return raw
          .map((e) => Checkpoint.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException(
        data['message']?.toString() ?? 'Failed to load checkpoints.');
  }

  // ── scanCheckpoint ─────────────────────────────────────────────────────────
  /// Validates and records a rider scan into the Riders_Scan sheet.
  ///
  /// Server checks:
  ///  • rider_id exists in Riders_Master
  ///  • category matches master record
  ///  • checkpoint is valid for the category
  ///  • no duplicate scan (same rider + checkpoint + category)
  ///  • scanned_by (volunteer phone) resolves to a known volunteer
  ///
  /// Returns the scan data map `{rider_name, category, scanned_by}` on success,
  /// where scanned_by is the resolved volunteer name.
  /// Throws [DuplicateScanException] for duplicates.
  /// Throws [ApiException] for all other errors.
  static Future<Map<String, dynamic>> scanCheckpoint({
    required String riderId,
    required String category,
    required String checkpoint,
    required String scannedBy,
  }) async {
    final data = await _post({
      'action': 'scanCheckpoint',
      'rider_id': riderId,
      'category': category,
      'checkpoint': checkpoint,
      'scanned_by': scannedBy,
    });

    if (data['status'] == 'success') {
      return data['data'] as Map<String, dynamic>;
    }

    if (data['status'] == 'duplicate') {
      throw DuplicateScanException(
          data['message']?.toString() ??
              'Already scanned at this checkpoint.');
    }

    throw ApiException(
        data['message']?.toString() ?? 'Scan failed. Please try again.');
  }

  // ── verifyRider ────────────────────────────────────────────────────────────
  /// Verifies a rider by ID and retrieves their category.
  /// Returns a map `{rider_id, rider_name, category}` on success.
  /// Throws [ApiException] if rider verification fails.
  static Future<Map<String, dynamic>> verifyRider({
    required String riderId,
  }) async {
    final data = await _post({
      'action': 'verifyRider',
      'rider_id': riderId,
    });

    if (data['status'] == 'success') {
      return data['data'] as Map<String, dynamic>;
    }

    throw ApiException(
        data['message']?.toString() ?? 'Rider verification failed.');
  }
}
