import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ble_device_config.dart';
import '../models/main_button_bindings.dart';
import '../models/relay_settings.dart';
import '../models/saved_controller.dart';
import '../services/ble_service.dart';
import 'configuration_screen.dart';
import 'device_control_screen.dart';
import 'device_scan_screen.dart';

enum _ActionFeedbackState { idle, pulse, doublePulse, hold }

class MainControlScreen extends StatefulWidget {
  const MainControlScreen({super.key, required this.bleService});

  final BleService bleService;

  @override
  State<MainControlScreen> createState() => _MainControlScreenState();
}

class _MainControlScreenState extends State<MainControlScreen> {
  static const _configPassword = '1234';

  final List<bool> _optimisticRelayStates = List<bool>.filled(4, false);
  final Set<int> _busyRelays = <int>{};
  final Set<int> _holdPressedRelays = <int>{};
  final Set<int> _pendingHoldReleaseRelays = <int>{};
  final Map<MainActionButton, _ActionFeedbackState> _actionFeedbackStates =
      <MainActionButton, _ActionFeedbackState>{};
  final Map<int, Timer> _autoOffTimers = <int, Timer>{};

  List<RelaySettings> _relaySettings = List<RelaySettings>.generate(
    4,
    (_) => const RelaySettings(),
  );
  MainButtonBindings _bindings = const MainButtonBindings.empty();
  SavedKitchenState? _kitchenState;
  SavedKitchen? _activeKitchen;
  SavedController? _savedController;
  bool _loading = true;
  bool _autoConnecting = false;
  bool _autoConnectInProgress = false;

  void _resetSilentReconnectState() {
    _autoConnecting = false;
    _autoConnectInProgress = false;
  }

  @override
  void initState() {
    super.initState();
    widget.bleService.addListener(_handleBleUpdates);
    _loadPageState();
  }

  @override
  void dispose() {
    widget.bleService.removeListener(_handleBleUpdates);
    for (final timer in _autoOffTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _handleBleUpdates() {
    if (!mounted) {
      return;
    }

    _trySilentReconnectFromScan();

    if (_autoConnecting &&
        !_autoConnectInProgress &&
        !widget.bleService.isScanning) {
      _resetSilentReconnectState();
    }

    setState(() {});
  }

  Future<void> _loadPageState() async {
    final preferences = await SharedPreferences.getInstance();
    final settings = List<RelaySettings>.generate(
      4,
      (index) => RelaySettings.fromPreferences(preferences, index + 1),
    );
    final bindings = MainButtonBindings.fromPreferences(preferences);
    final kitchenState = await SavedControllerStore.loadState();
    final activeKitchen = kitchenState.activeKitchen;
    final savedController = activeKitchen.controller;

    if (!mounted) {
      return;
    }

    setState(() {
      _relaySettings = settings;
      _bindings = bindings;
      _kitchenState = kitchenState;
      _activeKitchen = activeKitchen;
      _savedController = savedController;
      _loading = false;
    });

    await _startSilentReconnectIfNeeded();
  }

  RelaySettings _settingsFor(int relayIndex) => _relaySettings[relayIndex - 1];

  bool _isKitchenControllerConnected(SavedKitchen? kitchen) {
    final controller = kitchen?.controller;
    if (controller == null) {
      return false;
    }

    return widget.bleService.connectionState ==
            DeviceConnectionState.connected &&
        widget.bleService.connectedDeviceId == controller.id;
  }

  bool _isKitchenControllerConnecting(SavedKitchen? kitchen) {
    final controller = kitchen?.controller;
    if (controller == null) {
      return false;
    }

    return widget.bleService.connectionState ==
            DeviceConnectionState.connecting &&
        widget.bleService.connectedDeviceId == controller.id;
  }

  Future<bool> _setRelay(int relayIndex, bool isOn) async {
    if (_busyRelays.contains(relayIndex)) {
      return false;
    }

    setState(() {
      _busyRelays.add(relayIndex);
    });

    final ok = await widget.bleService.writeRelayCommand(
      relayIndex: relayIndex,
      isOn: isOn,
    );

    if (!mounted) {
      return ok;
    }

    setState(() {
      _busyRelays.remove(relayIndex);
      if (ok) {
        _optimisticRelayStates[relayIndex - 1] = isOn;
      }
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invio comando relè $relayIndex fallito.')),
      );
    }

    return ok;
  }

  Future<void> _startSilentReconnectIfNeeded() async {
    if (!mounted ||
        _loading ||
        _savedController == null ||
        widget.bleService.isConnected ||
        widget.bleService.connectionState == DeviceConnectionState.connecting ||
        _autoConnecting ||
        _autoConnectInProgress) {
      return;
    }

    _autoConnecting = true;
    setState(() {});

    await widget.bleService.startScan(
      withServices: BleDeviceConfig.shBt04b.scanServiceUuids,
      fallbackToUnfiltered: true,
    );
  }

  void _trySilentReconnectFromScan() {
    final savedController = _savedController;
    if (!_autoConnecting ||
        _autoConnectInProgress ||
        savedController == null ||
        !widget.bleService.isScanning) {
      return;
    }

    DiscoveredDevice? matchedDevice;
    for (final device in widget.bleService.scanResults) {
      if (device.id == savedController.id) {
        matchedDevice = device;
        break;
      }
    }

    if (matchedDevice == null) {
      return;
    }

    _autoConnectInProgress = true;
    widget.bleService.stopScan();
    Future<void>.microtask(() => _connectSavedDevice(matchedDevice!));
  }

  Future<void> _connectSavedDevice(DiscoveredDevice device) async {
    final activeKitchen = _activeKitchen;
    if (activeKitchen == null) {
      throw StateError('Active kitchen is not loaded.');
    }

    final config = widget.bleService.resolveConfigForDevice(device);
    final connected =
        await widget.bleService.connect(device: device, config: config);

    if (!mounted) {
      return;
    }

    _autoConnecting = false;
    _autoConnectInProgress = false;

    if (!connected) {
      setState(() {});
      return;
    }

    await SavedController(id: device.id, name: device.name).save(
      kitchenId: activeKitchen.id,
    );
    await _loadPageState();
  }

  Future<void> _selectKitchen(String kitchenId) async {
    final kitchenState = _kitchenState;
    if (kitchenState == null) {
      throw StateError('Kitchen state is not loaded.');
    }
    if (kitchenState.activeKitchenId == kitchenId) {
      return;
    }

    _autoConnecting = false;
    _autoConnectInProgress = false;
    await widget.bleService.stopScan();
    await widget.bleService.disconnect(suppressAutoReconnect: true);
    await SavedControllerStore.setActiveKitchen(kitchenId);
    await _loadPageState();
  }

  String _displayKitchenName(SavedKitchen kitchen) {
    return kitchen.displayName;
  }

  SavedKitchen? _findKitchenById(
      SavedKitchenState? kitchenState, String kitchenId) {
    if (kitchenState == null) {
      return null;
    }

    for (final kitchen in kitchenState.kitchens) {
      if (kitchen.id == kitchenId) {
        return kitchen;
      }
    }

    return null;
  }

  Future<void> _activateKitchen(String kitchenId) async {
    if (_activeKitchen?.id == kitchenId) {
      return;
    }

    await _selectKitchen(kitchenId);
  }

  Future<void> _openKitchenConnection(SavedKitchen kitchen) async {
    await _activateKitchen(kitchen.id);
    if (!mounted) {
      return;
    }

    await _openScanToConnect();
  }

  Future<void> _openKitchenControls(SavedKitchen kitchen) async {
    await _activateKitchen(kitchen.id);
    if (!mounted) {
      return;
    }

    if (!_isKitchenControllerConnected(_activeKitchen)) {
      await _openScanToConnect();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceControlScreen(
          bleService: widget.bleService,
          activeKitchenName: _displayKitchenName(kitchen),
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadPageState();
  }

  Widget _buildMissingKitchenSection({
    required String sectionLabel,
    required String expectedKitchenLabel,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x1A1B1712)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sectionLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF5E4D42),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            expectedKitchenLabel,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF17120E),
                ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF55483E),
                ),
          ),
          const SizedBox(height: 14),
          const Chip(
            label: Text('Dati ambiente mancanti'),
          ),
        ],
      ),
    );
  }

  Future<void> _performAction(MainActionButton action) async {
    final relayIndex = _bindings.relayFor(action);
    if (relayIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nessun relè associato a ${action.label}.')),
      );
      return;
    }

    if (!_isKitchenControllerConnected(_activeKitchen) ||
        !widget.bleService.relayControlReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collega prima il controller.')),
      );
      return;
    }

    final settings = _settingsFor(relayIndex);
    switch (settings.mode) {
      case RelayInteractionMode.pulseHold:
        await _startPulseMode(relayIndex, settings);
        break;
      case RelayInteractionMode.pulseDouble:
        await _startPulseMode(relayIndex, settings);
        break;
    }
  }

  Future<void> _startPulseMode(int relayIndex, RelaySettings settings) async {
    final turnedOn = await _setRelay(relayIndex, true);
    if (!turnedOn || !mounted) {
      return;
    }

    await Future<void>.delayed(settings.pulseDuration);
    if (!mounted) {
      return;
    }
    await _setRelay(relayIndex, false);
  }

  Future<void> _startDoublePulseMode(
      int relayIndex, RelaySettings settings) async {
    await _runPulseCycle(relayIndex, settings.pulseDuration, repetitions: 2);
  }

  Future<bool> _startHold(MainActionButton action) async {
    final relayIndex = _bindings.relayFor(action);
    if (relayIndex == null || _holdPressedRelays.contains(relayIndex)) {
      return false;
    }

    if (!_isKitchenControllerConnected(_activeKitchen) ||
        !widget.bleService.relayControlReady) {
      return false;
    }

    final settings = _settingsFor(relayIndex);
    if (settings.mode != RelayInteractionMode.pulseHold) {
      return false;
    }

    setState(() {
      _holdPressedRelays.add(relayIndex);
    });

    final ok = await _setRelay(relayIndex, true);
    if (!ok && mounted) {
      setState(() {
        _holdPressedRelays.remove(relayIndex);
        _pendingHoldReleaseRelays.remove(relayIndex);
        _actionFeedbackStates.remove(action);
      });
      return false;
    }

    _setActionFeedback(action, _ActionFeedbackState.hold);

    if (_pendingHoldReleaseRelays.remove(relayIndex)) {
      await _releaseHold(action);
    }

    return true;
  }

  Future<void> _releaseHold(MainActionButton action) async {
    final relayIndex = _bindings.relayFor(action);
    if (relayIndex == null || !_holdPressedRelays.contains(relayIndex)) {
      return;
    }

    if (_busyRelays.contains(relayIndex)) {
      _pendingHoldReleaseRelays.add(relayIndex);
      return;
    }

    setState(() {
      _holdPressedRelays.remove(relayIndex);
      _pendingHoldReleaseRelays.remove(relayIndex);
      _actionFeedbackStates.remove(action);
    });

    await _setRelay(relayIndex, false);
  }

  Future<void> _runPulseCycle(
    int relayIndex,
    Duration pulseDuration, {
    required int repetitions,
  }) async {
    for (var index = 0; index < repetitions; index++) {
      final turnedOn = await _setRelay(relayIndex, true);
      if (!turnedOn || !mounted) {
        return;
      }

      await Future<void>.delayed(pulseDuration);
      if (!mounted) {
        return;
      }

      final turnedOff = await _setRelay(relayIndex, false);
      if (!turnedOff || !mounted) {
        return;
      }

      if (index < repetitions - 1) {
        await Future<void>.delayed(pulseDuration);
        if (!mounted) {
          return;
        }
      }
    }
  }

  void _setActionFeedback(
    MainActionButton action,
    _ActionFeedbackState state,
  ) {
    if (!mounted) {
      return;
    }

    setState(() {
      if (state == _ActionFeedbackState.idle) {
        _actionFeedbackStates.remove(action);
      } else {
        _actionFeedbackStates[action] = state;
      }
    });
  }

  Future<void> _flashActionFeedback(
    MainActionButton action, {
    _ActionFeedbackState state = _ActionFeedbackState.pulse,
    Duration duration = const Duration(milliseconds: 170),
  }) async {
    _setActionFeedback(action, state);
    await Future<void>.delayed(duration);
    _setActionFeedback(action, _ActionFeedbackState.idle);
  }

  void _handleTapDown(MainActionButton action) {
    _setActionFeedback(action, _ActionFeedbackState.pulse);
  }

  void _handleTapUp(MainActionButton action) {
    _setActionFeedback(action, _ActionFeedbackState.idle);
  }

  Future<void> _handleActionTap(MainActionButton action) async {
    HapticFeedback.selectionClick();
    unawaited(_flashActionFeedback(action, state: _ActionFeedbackState.pulse));
    await _performAction(action);
  }

  Future<void> _handleActionDoubleTap(
    MainActionButton action,
    int relayIndex,
    RelaySettings settings,
  ) async {
    HapticFeedback.mediumImpact();
    unawaited(
      _flashActionFeedback(
        action,
        state: _ActionFeedbackState.doublePulse,
        duration: const Duration(milliseconds: 240),
      ),
    );
    await _startDoublePulseMode(relayIndex, settings);
  }

  Future<void> _handleSecondaryAction(
    MainActionButton action,
    RelaySettings settings,
  ) async {
    final relayIndex = _bindings.relayFor(action);
    if (relayIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nessun relè associato a ${action.label}.')),
      );
      return;
    }

    if (!_isKitchenControllerConnected(_activeKitchen) ||
        !widget.bleService.relayControlReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collega prima il controller.')),
      );
      return;
    }

    switch (settings.mode) {
      case RelayInteractionMode.pulseHold:
        if (_holdPressedRelays.contains(relayIndex)) {
          HapticFeedback.selectionClick();
          await _releaseHold(action);
        } else {
          HapticFeedback.heavyImpact();
          await _startHold(action);
        }
        break;
      case RelayInteractionMode.pulseDouble:
        await _handleActionDoubleTap(action, relayIndex, settings);
        break;
    }
  }

  String _feedbackLabelFor(
    MainActionButton action,
    RelaySettings? settings,
    int? relayIndex,
  ) {
    final state = _actionFeedbackStates[action] ?? _ActionFeedbackState.idle;
    final relayName = relayIndex == null || settings == null
        ? 'Relè'
        : settings.resolvedName(relayIndex);

    switch (state) {
      case _ActionFeedbackState.pulse:
        return 'Impulso in corso su $relayName';
      case _ActionFeedbackState.doublePulse:
        return 'Doppio impulso in corso su $relayName';
      case _ActionFeedbackState.hold:
        return 'Attivazione continua su $relayName';
      case _ActionFeedbackState.idle:
        return relayIndex == null || settings == null
            ? 'Non associato'
            : '$relayName - ${settings.mode == RelayInteractionMode.pulseHold ? 'Impulso + attivazione continua' : 'Impulso + doppio impulso'}';
    }
  }

  Color _statusColor({
    required bool connected,
    required bool connecting,
    required bool hasSavedController,
  }) {
    if (connected) {
      return const Color(0xFF1E6F4F);
    }
    if (connecting) {
      return const Color(0xFF8A5A18);
    }
    return hasSavedController
        ? const Color(0xFF6E4D2D)
        : const Color(0xFF8A5A18);
  }

  Future<void> _handlePrimaryAction(SavedKitchen kitchen) async {
    if (_isKitchenControllerConnected(kitchen)) {
      await _openKitchenControls(kitchen);
      return;
    }

    await _openKitchenConnection(kitchen);
  }

  Future<void> _openScanToConnect() async {
    final activeKitchen = _activeKitchen;
    if (activeKitchen == null) {
      throw StateError('Active kitchen is not loaded.');
    }

    _autoConnecting = false;
    _autoConnectInProgress = false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceScanScreen(
          bleService: widget.bleService,
          kitchenId: activeKitchen.id,
          activeKitchenName: _displayKitchenName(activeKitchen),
          preferredDeviceId: _savedController?.id,
          preferredDeviceName: _savedController?.displayName,
          openControlOnConnect: false,
          autoConnect: true,
          selectionMode: true,
        ),
      ),
    );

    await _loadPageState();
  }

  Future<void> _openConfigurationWithPassword() async {
    final activeKitchen = _activeKitchen;
    if (activeKitchen == null) {
      throw StateError('Active kitchen is not loaded.');
    }

    final unlocked = await _showPasswordDialog();
    if (!mounted || !unlocked) {
      return;
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ConfigurationScreen(
          bleService: widget.bleService,
          activeKitchen: activeKitchen,
          initialRelaySettings: _relaySettings,
          initialBindings: _bindings,
        ),
      ),
    );

    if (saved == true) {
      await _loadPageState();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurazione aggiornata.')),
      );
    }
  }

  Future<bool> _showPasswordDialog() async {
    final controller = TextEditingController();
    var invalidPassword = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Accesso configurazione'),
              content: TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: invalidPassword ? 'Password non valida' : null,
                ),
                onSubmitted: (_) {
                  if (controller.text.trim() == _configPassword) {
                    Navigator.of(context).pop(true);
                  } else {
                    setLocalState(() {
                      invalidPassword = true;
                    });
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () {
                    if (controller.text.trim() == _configPassword) {
                      Navigator.of(context).pop(true);
                    } else {
                      setLocalState(() {
                        invalidPassword = true;
                      });
                    }
                  },
                  child: const Text('Entra'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final relayReady = widget.bleService.relayControlReady;
    final kitchenState = _kitchenState;
    final activeKitchen = _activeKitchen;
    final kitchenName =
        activeKitchen == null ? 'Ambiente' : _displayKitchenName(activeKitchen);
    final savedController = activeKitchen?.controller;
    final connected = _isKitchenControllerConnected(activeKitchen);
    final connecting = _isKitchenControllerConnecting(activeKitchen) ||
        (_autoConnecting && savedController != null);
    final statusLabel = connected
        ? 'Collegato'
        : connecting
            ? 'Collegamento'
            : savedController == null
                ? 'Nessun controller'
                : 'Non collegato';
    final statusColor = _statusColor(
      connected: connected,
      connecting: connecting,
      hasSavedController: savedController != null,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(kitchenName),
        actions: [
          IconButton(
            onPressed: _openConfigurationWithPassword,
            tooltip: 'Configurazione protetta',
            icon: const Icon(Icons.lock_outline_rounded),
          ),
        ],
      ),
      body: _loading || kitchenState == null || activeKitchen == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x1A1B1712)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12183227),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kitchenName,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF17120E),
                                ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          Text(
                            connected && relayReady
                                ? 'Relè pronti'
                                : connected
                                    ? 'Inizializzazione relè'
                                    : savedController == null
                                        ? 'Collegamento richiesto'
                                        : 'Controller salvato',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      if (savedController != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          savedController.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              unawaited(_handlePrimaryAction(activeKitchen)),
                          icon: Icon(
                            connected
                                ? Icons.tune_rounded
                                : Icons.bluetooth_searching_rounded,
                          ),
                          label: Text(
                            connected ? 'Apri comandi' : 'Collega controller',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildActionButton(MainActionButton.onOff),
                const SizedBox(height: 12),
              ],
            ),
    );
  }

  Widget _buildActionButton(MainActionButton action) {
    final relayIndex = _bindings.relayFor(action);
    final hasRelay = relayIndex != null;
    final settings = hasRelay ? _settingsFor(relayIndex) : null;
    final holdPressed = hasRelay && _holdPressedRelays.contains(relayIndex);
    final isBusy = hasRelay && _busyRelays.contains(relayIndex);
    final feedbackState =
        _actionFeedbackStates[action] ?? _ActionFeedbackState.idle;
    final isHighlighted =
        feedbackState != _ActionFeedbackState.idle || holdPressed;

    final subtitle = _feedbackLabelFor(action, settings, relayIndex);
    final secondaryLabel = settings == null
        ? null
        : settings.mode == RelayInteractionMode.pulseHold
            ? null
            : 'Doppio impulso';
    final secondaryDescription = settings == null || secondaryLabel == null
        ? null
        : settings.mode == RelayInteractionMode.pulseHold
            ? (holdPressed
                ? 'Attivazione continua attiva. Tocca per disattivare.'
                : 'Mantiene il relè attivo finché non lo disattivi.')
            : 'Esegue due impulsi consecutivi.';
    final semanticsLabel = settings == null || relayIndex == null
        ? '${action.label}, comando non associato'
        : '${action.label}, impulso su ${settings.resolvedName(relayIndex)}';

    return SizedBox(
      width: double.infinity,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: isHighlighted ? 0.985 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: (feedbackState == _ActionFeedbackState.doublePulse
                              ? const Color(0xFF9A6C3F)
                              : feedbackState == _ActionFeedbackState.hold
                                  ? const Color(0xFF524034)
                                  : const Color(0xFF82624A))
                          .withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : const [],
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: feedbackState == _ActionFeedbackState.doublePulse
                  ? const Color(0xFF7C5635)
                  : feedbackState == _ActionFeedbackState.hold
                      ? const Color(0xFF3D2E25)
                      : const Color(0xFF1E1813),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isBusy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(
                        settings?.mode == RelayInteractionMode.pulseHold &&
                                holdPressed
                            ? Icons.pan_tool_alt_rounded
                            : settings?.mode == RelayInteractionMode.pulseDouble
                                ? Icons.repeat_rounded
                                : Icons.flash_on_rounded,
                        color: Colors.white,
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Semantics(
                  button: true,
                  enabled: hasRelay && !isBusy,
                  label: semanticsLabel,
                  child: FilledButton.icon(
                    onPressed: !hasRelay || isBusy
                        ? null
                        : () => _handleActionTap(action),
                    icon: const Icon(Icons.flash_on_rounded),
                    label: const Text('Impulso'),
                  ),
                ),
                if (secondaryLabel != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    secondaryDescription!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    enabled: hasRelay && !isBusy,
                    label: '${action.label}, ${secondaryLabel.toLowerCase()}',
                    child: OutlinedButton.icon(
                      onPressed: !hasRelay || isBusy || settings == null
                          ? null
                          : () => _handleSecondaryAction(action, settings),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                      ),
                      icon: Icon(
                        settings?.mode == RelayInteractionMode.pulseHold
                            ? (holdPressed
                                ? Icons.pause_circle_outline_rounded
                                : Icons.pan_tool_alt_rounded)
                            : Icons.repeat_rounded,
                      ),
                      label: Text(
                        secondaryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
