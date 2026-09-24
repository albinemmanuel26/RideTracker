import 'package:flutter/material.dart';

class AppConstants {
  // API
  static const String apiUrl =
      'https://script.google.com/macros/s/AKfycby3bQEUDNzkMirpYLTUMdbg4ZRqwX-9WNmeqWBSwfbthBJEk8rPIs0gKs5PmyP5tLcP/exec';
  static const String apiKey = 'Albin KCC ride track';

  // Theme colors
  static const Color primaryColor = Color(0xFFB22222);
  static const Color secondaryColor = Color(0xFFFFFF00);
  static const Color backgroundDark = Color(0xFF1A1A1A);
  static const Color surfaceColor = Color(0xFF2C2C2C);
  static const Color onPrimaryColor = Colors.white;

  // Storage keys
  static const String keyIsLoggedIn = 'isLoggedIn';
  static const String keyCheckpointId = 'checkpointId';
  static const String keyCheckpointName = 'checkpointName';
  static const String keyCheckpointCategory = 'checkpointCategory';
  static const String keyVolunteerPhone = 'volunteerPhone';
  static const String keyVolunteerName = 'volunteerName';
  static const String keyVolunteerRole = 'volunteerRole';
}
