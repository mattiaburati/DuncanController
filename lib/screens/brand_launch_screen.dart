import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import '../widgets/brand_visual_placeholder.dart';
import 'main_control_screen.dart';

class BrandLaunchScreen extends StatefulWidget {
  const BrandLaunchScreen({super.key, required this.bleService});

  final BleService bleService;

  @override
  State<BrandLaunchScreen> createState() => _BrandLaunchScreenState();
}

class _BrandLaunchScreenState extends State<BrandLaunchScreen> {
  static const Duration _minimumSplashDuration = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _openMainScreen();
  }

  Future<void> _openMainScreen() async {
    await Future<void>.delayed(_minimumSplashDuration);
    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MainControlScreen(bleService: widget.bleService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = BrandEnvironmentStyle.duncan;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            children: [
              BrandVisualPlaceholder(
                height: 320,
                borderRadius: 32,
                eyebrow: 'Duncan Controller',
                title: 'Duncan',
                subtitle: 'Avvio controllo relay BLE',
                trailingIcon: Icons.bluetooth_rounded,
                statusLabel: 'Inizializzazione',
                accentColor: style.accentColor,
                assetPath: style.assetPath,
              ),
              const Spacer(),
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 18),
              Text(
                'Apertura controller Duncan',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
