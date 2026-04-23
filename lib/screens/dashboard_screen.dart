import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../models/saved_controller.dart';
import '../services/ble_service.dart';
import 'device_control_screen.dart';
import 'device_scan_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.bleService});

  final BleService bleService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  SavedKitchenState? _kitchenState;
  SavedKitchen? _activeKitchen;
  SavedController? _savedController;
  bool _loadingSavedController = true;

  @override
  void initState() {
    super.initState();
    widget.bleService.addListener(_handleBleUpdate);
    _loadSavedController();
  }

  @override
  void dispose() {
    widget.bleService.removeListener(_handleBleUpdate);
    super.dispose();
  }

  Future<void> _loadSavedController() async {
    final kitchenState = await SavedControllerStore.loadState();
    final activeKitchen = kitchenState.activeKitchen;
    final savedController = activeKitchen.controller;

    if (!mounted) {
      return;
    }

    setState(() {
      _kitchenState = kitchenState;
      _activeKitchen = activeKitchen;
      _savedController = savedController;
      _loadingSavedController = false;
    });
  }

  Future<void> _selectKitchen(String kitchenId) async {
    final kitchenState = _kitchenState;
    if (kitchenState == null) {
      throw StateError('Kitchen state is not loaded.');
    }
    if (kitchenState.activeKitchenId == kitchenId) {
      return;
    }

    await widget.bleService.stopScan();
    await widget.bleService.disconnect(suppressAutoReconnect: true);
    await SavedControllerStore.setActiveKitchen(kitchenId);
    await _loadSavedController();
  }

  void _handleBleUpdate() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  String _displayKitchenName(SavedKitchen kitchen) {
    return kitchen.displayName;
  }

  Future<void> _openQuickReconnect() async {
    if (!mounted) {
      return;
    }

    final savedController = _savedController;
    final activeKitchen = _activeKitchen;
    if (activeKitchen == null) {
      throw StateError('Active kitchen is not loaded.');
    }

    if (savedController == null) {
      await _openScanScreen();
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceScanScreen(
          bleService: widget.bleService,
          kitchenId: activeKitchen.id,
          activeKitchenName: _displayKitchenName(activeKitchen),
          preferredDeviceId: savedController.id,
          preferredDeviceName: savedController.displayName,
        ),
      ),
    );

    if (mounted) {
      await _loadSavedController();
    }
  }

  Future<void> _openScanScreen() async {
    final activeKitchen = _activeKitchen;
    if (activeKitchen == null) {
      throw StateError('Active kitchen is not loaded.');
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceScanScreen(
          bleService: widget.bleService,
          kitchenId: activeKitchen.id,
          activeKitchenName: _displayKitchenName(activeKitchen),
        ),
      ),
    );

    if (mounted) {
      await _loadSavedController();
    }
  }

  Future<void> _openControlScreen() async {
    final activeKitchen = _activeKitchen;
    if (activeKitchen == null) {
      throw StateError('Active kitchen is not loaded.');
    }

    if (!widget.bleService.isConnected) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceControlScreen(
          bleService: widget.bleService,
          activeKitchenName: _displayKitchenName(activeKitchen),
        ),
      ),
    );
  }

  String _statusTitle() {
    switch (widget.bleService.connectionState) {
      case DeviceConnectionState.connecting:
        return 'Collegamento';
      case DeviceConnectionState.connected:
        return 'Controller collegato';
      case DeviceConnectionState.disconnecting:
        return 'Scollegamento';
      case DeviceConnectionState.disconnected:
        return _savedController == null
            ? 'Nessun controller associato'
            : 'Controller non collegato';
    }
  }

  String _statusDescription() {
    switch (widget.bleService.connectionState) {
      case DeviceConnectionState.connecting:
        return 'Collegamento al controller in corso.';
      case DeviceConnectionState.connected:
        return 'Controller collegato. Apri i comandi.';
      case DeviceConnectionState.disconnecting:
        return 'Scollegamento in corso.';
      case DeviceConnectionState.disconnected:
        return _savedController == null
            ? 'Tocca Cerca controller.'
            : 'Tocca Collega controller o Cerca controller.';
    }
  }

  Color _statusColor(bool isConnected, SavedController? savedController) {
    if (isConnected) {
      return const Color(0xFF1E6F4F);
    }
    if (widget.bleService.connectionState == DeviceConnectionState.connecting) {
      return const Color(0xFF8A5A18);
    }
    return savedController == null
        ? const Color(0xFF8A5A18)
        : const Color(0xFF6E4D2D);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final kitchenState = _kitchenState;
    final activeKitchen = _activeKitchen;
    final savedController = _savedController;
    final isConnected = widget.bleService.isConnected;
    final statusColor = _statusColor(isConnected, savedController);

    return Scaffold(
      appBar: AppBar(title: const Text('Controllo ambiente')),
      body: SafeArea(
        child: _loadingSavedController ||
                kitchenState == null ||
                activeKitchen == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
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
                                    'Ambiente',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _displayKitchenName(activeKitchen),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                _statusBadgeLabel(isConnected, savedController),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _statusTitle(),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _statusDescription(),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        if (savedController != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Controller salvato',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  savedController.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          initialValue: activeKitchen.id,
                          decoration: const InputDecoration(
                            labelText: 'Seleziona ambiente',
                            border: OutlineInputBorder(),
                          ),
                          items: kitchenState.kitchens
                              .map(
                                (kitchen) => DropdownMenuItem<String>(
                                  value: kitchen.id,
                                  child: Text(_displayKitchenName(kitchen)),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) async {
                            if (value == null) {
                              throw StateError('Selected kitchen id is null.');
                            }

                            await _selectKitchen(value);
                          },
                        ),
                        const SizedBox(height: 12),
                        if (!isConnected && savedController != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _openQuickReconnect,
                              icon: const Icon(
                                Icons.play_circle_outline_rounded,
                              ),
                              label: const Text('Collega controller'),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (isConnected)
                              FilledButton.icon(
                                onPressed: _openControlScreen,
                                icon: const Icon(Icons.tune_rounded),
                                label: const Text('Apri comandi'),
                              ),
                            FilledButton.tonalIcon(
                              onPressed: _openScanScreen,
                              icon:
                                  const Icon(Icons.bluetooth_searching_rounded),
                              label: Text(
                                savedController == null
                                    ? 'Cerca un controller'
                                    : 'Cambia controller',
                              ),
                            ),
                          ],
                        ),
                        if (widget.bleService.lastConnectionError != null ||
                            widget.bleService.lastProtocolMessage != null) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (widget.bleService.lastConnectionError != null)
                                Chip(
                                  label: Text(
                                      widget.bleService.lastConnectionError!),
                                ),
                              if (widget.bleService.lastProtocolMessage != null)
                                Chip(
                                  label: Text(
                                      widget.bleService.lastProtocolMessage!),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DashboardSection(
                    title: 'Stato',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            widget.bleService.isConnected
                                ? 'Controller collegato'
                                : 'Non collegato',
                          ),
                        ),
                        Chip(
                          label: Text(
                              'Ambiente: ${_displayKitchenName(activeKitchen)}'),
                        ),
                        Chip(
                          label: Text(
                              _statusBadgeLabel(isConnected, savedController)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

String _statusBadgeLabel(bool isConnected, SavedController? savedController) {
  if (isConnected) {
    return 'Collegato';
  }
  if (savedController == null) {
    return 'Da collegare';
  }
  return 'Non collegato';
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
