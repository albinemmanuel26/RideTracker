import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants/app_constants.dart';
import 'screens/login_screen.dart';
import 'screens/scanner_screen.dart';
import 'services/local_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorageService.init();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const RideTrackApp());
}

class RideTrackApp extends StatelessWidget {
  const RideTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ride Track',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: AppConstants.primaryColor,
          onPrimary: AppConstants.onPrimaryColor,
          primaryContainer: AppConstants.primaryColor,
          onPrimaryContainer: AppConstants.onPrimaryColor,
          error: AppConstants.primaryColor,
          onError: AppConstants.onPrimaryColor,
          errorContainer: AppConstants.primaryColor,
          onErrorContainer: AppConstants.onPrimaryColor,
          secondary: AppConstants.secondaryColor,
          surface: AppConstants.surfaceColor,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: AppConstants.onPrimaryColor,
            disabledForegroundColor: AppConstants.onPrimaryColor,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: AppConstants.onPrimaryColor,
            disabledForegroundColor: AppConstants.onPrimaryColor,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          contentTextStyle: TextStyle(color: Colors.white),
          actionTextColor: Colors.white,
          backgroundColor: AppConstants.surfaceColor,
        ),
        scaffoldBackgroundColor: AppConstants.backgroundDark,
        fontFamily: 'Roboto',
      ),
      home: const _AppEntry(),
    );
  }
}

class _AppEntry extends StatelessWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context) {
    if (LocalStorageService.isLoggedIn &&
        LocalStorageService.checkpointName.isNotEmpty) {
      return ScannerScreen(
        checkpointName: LocalStorageService.checkpointName,
        checkpointId: LocalStorageService.checkpointId,
        checkpointCategory: LocalStorageService.checkpointCategory,
        volunteerPhone: LocalStorageService.volunteerPhone,
        volunteerName: LocalStorageService.volunteerName,
      );
    }
    return const LoginScreen();
  }
}
