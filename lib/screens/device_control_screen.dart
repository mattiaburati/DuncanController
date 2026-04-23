import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/relay_settings.dart';
import '../services/ble_service.dart';
import 'relay_settings_screen.dart';

class DeviceControlScreen extends StatefulWidget {
  const DeviceControlScreen({
    super.key,
    required this.bleService,
    required this.activeKitchenName,
  });

  final BleService bleService;
  final String activeKitchenName;

  @override
  State<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen> {
  final List<bool> _optimisticRelayStates = List<bool>.filled(4, false);
  final Set<int> _busyRelays = <int>{};
  final Set<int> _holdPressedRelays = <int>{};
  final Set<int> _pendingHoldReleaseRelays = <int>{};
  final Set<int> _activeRelayFeedback = <int>{};
  final Map<int, Timer> _autoOffTimers = <int, Timer>{};

  List<RelaySettings> _relaySettings = List<RelaySettings>.generate(
    4,
    (_) => const RelaySettings(),
  );
  SharedPreferences? _preferences;
  bool _loadingSettings = true;
  bool _refreshingStatus = false;

  @override
  void initState() {
    super.initState();
    _loadRelaySettings();
  }

  @override
  void dispose() {
    for (final timer in _autoOffTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> _loadRelaySettings() async {
    final preferences = await SharedPreferences.getInstance();
    final settings = List<RelaySettings>.generate(
      4,
      (index) => RelaySettings.fromPreferences(preferences, index + 1),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _preferences = preferences;
      _relaySettings = settings;
      _loadingSettings = false;
    });
  }

  Future<void> _saveRelaySettings(List<RelaySettings> settings) async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    _preferences = preferences;

    for (var relayIndex = 1; relayIndex <= settings.length; relayIndex++) {
      await settings[relayIndex - 1].saveToPreferences(preferences, relayIndex);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _relaySettings = settings;
    });

    for (var relayIndex = 1; relayIndex <= settings.length; relayIndex++) {
      final settingsForRelay = settings[relayIndex - 1];
      _cancelAutoOff(relayIndex);
      if (settingsForRelay.mode != RelayInteractionMode.pulseHold &&
          _holdPressedRelays.contains(relayIndex)) {
        unawaited(_releaseHold(relayIndex));
      }
    }
  }

  RelaySettings _settingsFor(int relayIndex) => _relaySettings[relayIndex - 1];

  bool _displayRelayState(int relayIndex) {
    if (widget.bleService.hasKnownRelayStates &&
        widget.bleService.knownRelayCount >= relayIndex) {
      return widget.bleService.relayStates[relayIndex - 1];
    }

    return _optimisticRelayStates[relayIndex - 1];
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

  Future<void> _handleRelayAction(int relayIndex) async {
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

  Future<bool> _startHold(int relayIndex) async {
    if (_holdPressedRelays.contains(relayIndex) ||
        _busyRelays.contains(relayIndex)) {
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
        _activeRelayFeedback.remove(relayIndex);
      });
      return false;
    }

    _setRelayFeedback(relayIndex, true);

    if (_pendingHoldReleaseRelays.remove(relayIndex)) {
      await _releaseHold(relayIndex);
    }

    return true;
  }

  Future<void> _releaseHold(int relayIndex) async {
    if (!_holdPressedRelays.contains(relayIndex)) {
      return;
    }

    if (_busyRelays.contains(relayIndex)) {
      _pendingHoldReleaseRelays.add(relayIndex);
      return;
    }

    setState(() {
      _holdPressedRelays.remove(relayIndex);
      _pendingHoldReleaseRelays.remove(relayIndex);
      _activeRelayFeedback.remove(relayIndex);
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

  void _setRelayFeedback(int relayIndex, bool isActive) {
    if (!mounted) {
      return;
    }

    setState(() {
      if (isActive) {
        _activeRelayFeedback.add(relayIndex);
      } else {
        _activeRelayFeedback.remove(relayIndex);
      }
    });
  }

  Future<void> _flashRelayFeedback(
    int relayIndex, {
    Duration duration = const Duration(milliseconds: 170),
  }) async {
    _setRelayFeedback(relayIndex, true);
    await Future<void>.delayed(duration);
    _setRelayFeedback(relayIndex, false);
  }

  void _handleRelayTapDown(int relayIndex) {
    _setRelayFeedback(relayIndex, true);
  }

  void _handleRelayTapUp(int relayIndex) {
    _setRelayFeedback(relayIndex, false);
  }

  Future<void> _handleRelayTap(int relayIndex) async {
    HapticFeedback.selectionClick();
    unawaited(_flashRelayFeedback(relayIndex));
    await _handleRelayAction(relayIndex);
  }

  Future<void> _handleRelayDoubleTap(
    int relayIndex,
    RelaySettings settings,
  ) async {
    HapticFeedback.mediumImpact();
    unawaited(
      _flashRelayFeedback(
        relayIndex,
        duration: const Duration(milliseconds: 240),
      ),
    );
    await _startDoublePulseMode(relayIndex, settings);
  }

  Future<void> _handleRelaySecondaryAction(
    int relayIndex,
    RelaySettings settings,
  ) async {
    if (_busyRelays.contains(relayIndex)) {
      return;
    }

    switch (settings.mode) {
      case RelayInteractionMode.pulseHold:
        if (_holdPressedRelays.contains(relayIndex)) {
          HapticFeedback.selectionClick();
          await _releaseHold(relayIndex);
        } else {
          HapticFeedback.heavyImpact();
          await _startHold(relayIndex);
        }
        break;
      case RelayInteractionMode.pulseDouble:
        await _handleRelayDoubleTap(relayIndex, settings);
        break;
    }
  }

  void _cancelAutoOff(int relayIndex) {
    final timer = _autoOffTimers.remove(relayIndex);
    timer?.cancel();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSettingsScreen() async {
    final updatedSettings =
        await Navigator.of(context).push<List<RelaySettings>>(
      MaterialPageRoute(
        builder: (_) => RelaySettingsScreen(initialSettings: _relaySettings),
      ),
    );

    if (updatedSettings != null) {
      await _saveRelaySettings(updatedSettings);
    }
  }

  Future<void> _refreshRelayStatus() async {
    if (_refreshingStatus) {
      return;
    }

    setState(() {
      _refreshingStatus = true;
    });

    final ok = await widget.bleService.queryRelayStatus();

    if (!mounted) {
      return;
    }

    setState(() {
      _refreshingStatus = false;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Aggiornamento stato relè non disponibile.')),
      );
    }
  }

  Future<void> _disconnectAndClose() async {
    await widget.bleService.disconnect(suppressAutoReconnect: true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _connectionLabel(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connecting:
        return 'Collegamento';
      case DeviceConnectionState.connected:
        return 'Collegato';
      case DeviceConnectionState.disconnecting:
        return 'Scollegamento';
      case DeviceConnectionState.disconnected:
        return 'Non collegato';
    }
  }

  String _statusText(int relayIndex) {
    final relayOn = _displayRelayState(relayIndex);
    if (widget.bleService.hasKnownRelayStates &&
        widget.bleService.knownRelayCount >= relayIndex) {
      return relayOn ? 'Stato reale: attivo' : 'Stato reale: disattivo';
    }

    return relayOn ? 'Ultimo comando: attivo' : 'Ultimo comando: disattivo';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.activeKitchenName} · Comandi'),
        actions: [
          IconButton(
            onPressed: widget.bleService.relayControlReady
                ? _refreshRelayStatus
                : null,
            tooltip: 'Aggiorna stato',
            icon: _refreshingStatus
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          IconButton(
            onPressed: _openSettingsScreen,
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            onPressed: _disconnectAndClose,
            tooltip: 'Disconnetti',
            icon: const Icon(Icons.link_off),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.bleService,
        builder: (_, __) {
          final state = widget.bleService.connectionState;
          final connected = state == DeviceConnectionState.connected;
          final relayReady = widget.bleService.relayControlReady;
          final relayWarning = widget.bleService.relayControlWarning;

          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: _buildConnectionCard(
                    context: context,
                    state: state,
                    connected: connected,
                  ),
                ),
                if (relayWarning != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _buildWarningCard(context, relayWarning),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _buildInfoCard(context),
                ),
                Expanded(
                  child: _loadingSettings
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 700 ? 2 : 1;
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 18,
                                crossAxisSpacing: 18,
                                childAspectRatio: columns == 2 ? 1.08 : 1.04,
                              ),
                              itemCount: 4,
                              itemBuilder: (_, index) {
                                final relayIndex = index + 1;
                                return _buildRelayCard(
                                  context: context,
                                  relayIndex: relayIndex,
                                  connected: connected,
                                  relayReady: relayReady,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionCard({
    required BuildContext context,
    required DeviceConnectionState state,
    required bool connected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = connected
        ? const Color(0xFF1E6F4F)
        : state == DeviceConnectionState.connecting
            ? const Color(0xFF8A5A18)
            : colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.activeKitchenName,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 10),
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
                              _connectionLabel(state),
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
                            connected
                                ? 'Relè disponibili'
                                : 'Collega il controller per usare i relè',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: connected ? _disconnectAndClose : null,
                  child: Text(connected ? 'Scollega' : 'Non collegato'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.bleService.connectedDeviceId ??
                  'Nessun controller collegato',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningCard(BuildContext context, String warning) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colorScheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                warning,
                style: TextStyle(color: colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final protocolMessage = widget.bleService.lastProtocolMessage;
    const baseText = 'Usa Impulso o l’azione secondaria per ogni relè.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tune_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    baseText,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Aggiorna lo stato se serve, poi usa i comandi sotto.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (protocolMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                protocolMessage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRelayCard({
    required BuildContext context,
    required int relayIndex,
    required bool connected,
    required bool relayReady,
  }) {
    final settings = _settingsFor(relayIndex);
    final relayOn = _displayRelayState(relayIndex);
    final busy = _busyRelays.contains(relayIndex);
    final holdPressed = _holdPressedRelays.contains(relayIndex);
    final highlighted =
        _activeRelayFeedback.contains(relayIndex) || holdPressed;
    final enabled = connected && relayReady;
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = relayOn
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accentColor, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Canale $relayIndex',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                settings.resolvedName(relayIndex),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                      'Impulso On/Off',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (settings.mode == RelayInteractionMode.pulseHold ||
                      settings.mode == RelayInteractionMode.pulseDouble)
                    Chip(
                      label: Text(
                        '${settings.pulseDuration.inMilliseconds} ms',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _statusText(relayIndex),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                settings.mode == RelayInteractionMode.pulseDouble
                    ? 'Tocca Impulso per attivare o disattivare. Secondaria: doppio impulso.'
                    : 'Tocca Impulso per attivare o disattivare.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              _buildActionArea(
                context: context,
                relayIndex: relayIndex,
                settings: settings,
                enabled: enabled,
                highlighted: highlighted,
                busy: busy,
                relayOn: relayOn,
                holdPressed: holdPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionArea({
    required BuildContext context,
    required int relayIndex,
    required RelaySettings settings,
    required bool enabled,
    required bool highlighted,
    required bool busy,
    required bool relayOn,
    required bool holdPressed,
  }) {
    final hasSecondary = settings.mode == RelayInteractionMode.pulseDouble;
    final secondaryLabel = !hasSecondary
        ? null
        : settings.mode == RelayInteractionMode.pulseHold
            ? (holdPressed ? 'Disattiva continua' : 'Attivazione continua')
            : 'Doppio impulso';
    final secondaryDescription = !hasSecondary
        ? null
        : settings.mode == RelayInteractionMode.pulseHold
            ? (holdPressed
                ? 'Attivazione continua attiva. Tocca per disattivare.'
                : 'Mantiene il relè attivo finché non lo disattivi.')
            : 'Esegue due impulsi consecutivi da ${settings.pulseDuration.inMilliseconds} ms.';

    return SizedBox(
      width: double.infinity,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: highlighted ? 0.985 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(
                            alpha: 0.2,
                          ),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                button: true,
                enabled: enabled && !busy,
                label: 'Impulso ${settings.resolvedName(relayIndex)}',
                child: FilledButton.icon(
                  onPressed: enabled && !busy
                      ? () => _handleRelayTap(relayIndex)
                      : null,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.flash_on_rounded),
                  label: const Text('Impulso'),
                ),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(height: 10),
                Text(
                  secondaryDescription!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  enabled: enabled && !busy,
                  label: '$secondaryLabel ${settings.resolvedName(relayIndex)}',
                  child: OutlinedButton.icon(
                    onPressed: enabled && !busy
                        ? () =>
                            _handleRelaySecondaryAction(relayIndex, settings)
                        : null,
                    icon: Icon(
                      settings.mode == RelayInteractionMode.pulseHold
                          ? (holdPressed
                              ? Icons.pause_circle_outline_rounded
                              : Icons.pan_tool_alt_rounded)
                          : Icons.repeat_rounded,
                    ),
                    label: Text(secondaryLabel),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Azione principale: impulso. Azione secondaria: doppio impulso.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
