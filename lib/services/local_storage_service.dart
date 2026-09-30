import 'dart:convert';
import '../models/rider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/checkpoint.dart';

class LocalStorageService {
  static SharedPreferences? _prefs;
  static RiderList? _riderList;
  static List<Checkpoint> _checkpoints = const [];
  static List<Checkpoint> get checkpoints => _checkpoints;

  static Future<void> init() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
    _riderList = _loadRiderList();
    final raw = _prefs!.getString('master_data_v1');
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final riders = RiderList.fromJson(
          data['riders'] as Map<String, dynamic>,
        );
        final checkpoints = (data['checkpoints'] as List)
            .map((e) => Checkpoint.fromJson(e as Map<String, dynamic>))
            .toList();
        _riderList = riders;
        _checkpoints = List.unmodifiable(checkpoints);
      } catch (_) {
        /* Login or Settings refresh can repair a damaged cache. */
      }
    }
    final riderOverride = _prefs!.getString('riders_v2');
    if (riderOverride != null) {
      try {
        _riderList = RiderList.fromJson(
          jsonDecode(riderOverride) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    final checkpointOverride = _prefs!.getString('checkpoints_v2');
    if (checkpointOverride != null) {
      try {
        _checkpoints = List.unmodifiable(
          (jsonDecode(checkpointOverride) as List).map(
            (e) => Checkpoint.fromJson(e as Map<String, dynamic>),
          ),
        );
      } catch (_) {}
    }
  }

  static RiderList? get riderList => _riderList;

  static RiderList? _loadRiderList() {
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
      'riders_v2',
      jsonEncode(list.toJson()),
    );
    if (!saved) throw StateError('Could not save rider list');
    _riderList = list;
  }

  static Future<void> saveCheckpoints(List<Checkpoint> checkpoints) async {
    final encoded = jsonEncode(
      checkpoints
          .map(
            (c) => {
              'checkpoint_id': c.id,
              'checkpoint_name': c.name,
              'category': c.category,
              'is_active': c.isActive,
            },
          )
          .toList(),
    );
    if (!await _prefs!.setString('checkpoints_v2', encoded)) {
      throw StateError('Could not save checkpoints');
    }
    _checkpoints = List.unmodifiable(checkpoints);
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
