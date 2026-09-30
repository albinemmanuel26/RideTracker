import 'dart:convert';
import '../models/rider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/checkpoint.dart';

class LocalStorageService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static RiderList? get riderList {
    final raw = _prefs?.getString('rider_list_v1');
    if (raw == null) return null;
    try {
      return RiderList.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // Store both categories and timestamp as one snapshot, never partial updates.
  static Future<void> saveRiderList(RiderList list) async {
    final saved = await _prefs!.setString(
      'rider_list_v1',
      jsonEncode(list.toJson()),
    );
    if (!saved) throw StateError('Could not save rider list');
  }

  static Future<void> saveSession({
    required String volunteerPhone,
    required String volunteerName,
    required String volunteerRole,
    required String checkpointId,
    required String checkpointName,
    required String checkpointCategory,
  }) async {
    await _prefs!.setBool(AppConstants.keyIsLoggedIn, true);
    await _prefs!.setString(AppConstants.keyVolunteerPhone, volunteerPhone);
    await _prefs!.setString(AppConstants.keyVolunteerName, volunteerName);
    await _prefs!.setString(AppConstants.keyVolunteerRole, volunteerRole);
    await _prefs!.setString(AppConstants.keyCheckpointId, checkpointId);
    await _prefs!.setString(AppConstants.keyCheckpointName, checkpointName);
    await _prefs!.setString(
      AppConstants.keyCheckpointCategory,
      Checkpoint.normalizeCategory(checkpointCategory),
    );
  }

  static Future<void> clearSession() async {
    await _prefs!.remove(AppConstants.keyIsLoggedIn);
    await _prefs!.remove(AppConstants.keyVolunteerPhone);
    await _prefs!.remove(AppConstants.keyVolunteerName);
    await _prefs!.remove(AppConstants.keyVolunteerRole);
    await _prefs!.remove(AppConstants.keyCheckpointId);
    await _prefs!.remove(AppConstants.keyCheckpointName);
    await _prefs!.remove(AppConstants.keyCheckpointCategory);
  }

  static bool get isLoggedIn =>
      _prefs?.getBool(AppConstants.keyIsLoggedIn) ?? false;

  static String get volunteerPhone =>
      _prefs?.getString(AppConstants.keyVolunteerPhone) ?? '';

  static String get volunteerName =>
      _prefs?.getString(AppConstants.keyVolunteerName) ?? '';

  static String get volunteerRole =>
      _prefs?.getString(AppConstants.keyVolunteerRole) ?? '';

  static String get checkpointId =>
      _prefs?.getString(AppConstants.keyCheckpointId) ?? '';

  static String get checkpointName =>
      _prefs?.getString(AppConstants.keyCheckpointName) ?? '';

  static String get checkpointCategory => Checkpoint.normalizeCategory(
    _prefs?.getString(AppConstants.keyCheckpointCategory) ?? '',
  );
}
