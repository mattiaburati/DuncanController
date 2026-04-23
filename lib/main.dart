import 'package:flutter/material.dart';

import 'screens/brand_launch_screen.dart';
import 'services/ble_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ReleControllerApp(bleService: BleService()));
}

class ReleControllerApp extends StatelessWidget {
  const ReleControllerApp({super.key, required this.bleService});

  final BleService bleService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF116466),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Duncan Controller',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F3),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          margin: EdgeInsets.zero,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colorScheme.surfaceContainerHigh,
          contentTextStyle: TextStyle(color: colorScheme.onSurface),
        ),
      ),
      home: BrandLaunchScreen(bleService: bleService),
    );
  }
}
