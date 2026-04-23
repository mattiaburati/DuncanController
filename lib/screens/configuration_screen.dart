import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/main_button_bindings.dart';
import '../models/relay_settings.dart';
import '../models/saved_controller.dart';
import '../services/ble_service.dart';
import 'device_scan_screen.dart';
import 'relay_settings_screen.dart';

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({
    super.key,
    required this.bleService,
    required this.activeKitchen,
    required this.initialRelaySettings,
    required this.initialBindings,
  });

  final BleService bleService;
  final SavedKitchen activeKitchen;
  final List<RelaySettings> initialRelaySettings;
  final MainButtonBindings initialBindings;

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  late List<RelaySettings> _relaySettings;
  late MainButtonBindings _bindings;
  SavedController? _savedController;

  @override
  void initState() {
    super.initState();
    _relaySettings = widget.initialRelaySettings;
    _bindings = widget.initialBindings;
    _loadSavedController();
  }

  Future<void> _loadSavedController() async {
    final state = await SavedControllerStore.loadState();
    final saved = state.kitchens
        .firstWhere((kitchen) => kitchen.id == widget.activeKitchen.id)
        .controller;
    if (!mounted) {
      return;
    }

    setState(() {
      _savedController = saved;
    });
  }

  Future<void> _openScanForPairing() async {
    final paired = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DeviceScanScreen(
          bleService: widget.bleService,
          kitchenId: widget.activeKitchen.id,
          activeKitchenName: widget.activeKitchen.displayName,
          preferredDeviceId: _savedController?.id,
          preferredDeviceName: _savedController?.displayName,
          openControlOnConnect: false,
          autoConnect: false,
          selectionMode: true,
        ),
      ),
    );

    if (paired == true) {
      await _loadSavedController();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispositivo relay associato.')),
      );
    }
  }

  Future<void> _openRelaySettings() async {
    final updated = await Navigator.of(context).push<List<RelaySettings>>(
      MaterialPageRoute<List<RelaySettings>>(
        builder: (_) => RelaySettingsScreen(initialSettings: _relaySettings),
      ),
    );

    if (updated == null) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    for (var relayIndex = 1; relayIndex <= updated.length; relayIndex++) {
      await updated[relayIndex - 1].saveToPreferences(preferences, relayIndex);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _relaySettings = updated;
    });
  }

  Future<void> _saveBindingsAndClose() async {
    final preferences = await SharedPreferences.getInstance();
    await _bindings.save(preferences);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(true);
  }

  void _updateBinding(MainActionButton action, int? relay) {
    setState(() {
      switch (action) {
        case MainActionButton.onOff:
          _bindings =
              _bindings.copyWith(onOffRelay: relay, clearOnOff: relay == null);
          break;
        case MainActionButton.scenari:
          _bindings = _bindings.copyWith(
              scenariRelay: relay, clearScenari: relay == null);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final savedController = _savedController;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurazione'),
        actions: [
          TextButton(
              onPressed: _saveBindingsAndClose, child: const Text('Salva')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dispositivo Bluetooth relay',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      savedController == null
                          ? 'Nessun dispositivo associato'
                          : '${savedController.displayName}\n${savedController.id}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _openScanForPairing,
                    icon: const Icon(Icons.bluetooth_searching_rounded),
                    label: Text(
                      savedController == null
                          ? 'Associa dispositivo'
                          : 'Cambia dispositivo',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comportamento relè',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Configura i relè in modalità Pulsante o Pulsante 2 e personalizza la durata impulso.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _openRelaySettings,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Apri impostazioni relè'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Associazione pulsante principale',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scegli quale relè comandare con On/Off.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  _buildBindingField(MainActionButton.onOff),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBindingField(MainActionButton action) {
    final selectedRelay = _bindings.relayFor(action);

    return DropdownButtonFormField<int?>(
      initialValue: selectedRelay,
      decoration: InputDecoration(
        labelText: action.label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Non associato'),
        ),
        ...List<DropdownMenuItem<int?>>.generate(4, (index) {
          final relayIndex = index + 1;
          final relayLabel = _relaySettings[index].resolvedName(relayIndex);
          return DropdownMenuItem<int?>(
            value: relayIndex,
            child: Text('Relè $relayIndex - $relayLabel'),
          );
        }),
      ],
      onChanged: (value) => _updateBinding(action, value),
    );
  }
}
