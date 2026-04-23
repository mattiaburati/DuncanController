import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../models/ble_device_config.dart';
import '../models/saved_controller.dart';
import '../services/ble_service.dart';
import 'device_control_screen.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({
    super.key,
    required this.bleService,
    required this.kitchenId,
    required this.activeKitchenName,
    this.preferredDeviceId,
    this.preferredDeviceName,
    this.openControlOnConnect = true,
    this.autoConnect = true,
    this.selectionMode = false,
  });

  final BleService bleService;
  final String kitchenId;
  final String activeKitchenName;
  final String? preferredDeviceId;
  final String? preferredDeviceName;
  final bool openControlOnConnect;
  final bool autoConnect;
  final bool selectionMode;

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final BleDeviceConfig _preferredProfile = BleDeviceConfig.shBt04b;
  String? _connectingDeviceId;
  bool _autoConnectTriggered = false;
  bool _openingControlScreen = false;

  bool get _isConnectionInFlight =>
      _connectingDeviceId != null ||
      widget.bleService.connectionState == DeviceConnectionState.connecting;

  bool get _hasPreferredDevice =>
      widget.preferredDeviceId != null && widget.preferredDeviceId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.bleService.addListener(_handleBleUpdate);
    _startScan();
  }

  @override
  void dispose() {
    widget.bleService.removeListener(_handleBleUpdate);
    widget.bleService.stopScan();
    super.dispose();
  }

  void _handleBleUpdate() {
    if (!widget.autoConnect ||
        !mounted ||
        _connectingDeviceId != null ||
        _openingControlScreen) {
      return;
    }

    final matchingDevices = _matchingDevices();
    if (matchingDevices.isEmpty) {
      if (!widget.bleService.isScanning) {
        _autoConnectTriggered = false;
      }
      return;
    }

    if (_autoConnectTriggered) {
      return;
    }

    if (_hasPreferredDevice) {
      DiscoveredDevice? preferredDevice;
      for (final device in matchingDevices) {
        if (device.id == widget.preferredDeviceId) {
          preferredDevice = device;
          break;
        }
      }

      if (preferredDevice == null) {
        return;
      }

      if (widget.bleService.isScanning) {
        widget.bleService.stopScan();
      }

      _autoConnectTriggered = true;
      Future<void>.microtask(() {
        if (!mounted) {
          return Future<void>.value();
        }

        return _connectToDevice(preferredDevice!);
      });
      return;
    }
  }

  List<DiscoveredDevice> _matchingDevices() {
    final devices = widget.bleService.scanResults
        .where(
          (device) => widget.bleService.isLikelyTargetDevice(
            device,
            preferredProfile: _preferredProfile,
          ),
        )
        .toList()
      ..sort((left, right) {
        final leftPreferred = left.id == widget.preferredDeviceId;
        final rightPreferred = right.id == widget.preferredDeviceId;

        if (leftPreferred != rightPreferred) {
          return leftPreferred ? -1 : 1;
        }

        return right.rssi.compareTo(left.rssi);
      });

    return devices;
  }

  Future<void> _startScan() async {
    await widget.bleService.startScan(
      withServices: _preferredProfile.scanServiceUuids,
      fallbackToUnfiltered: true,
    );
  }

  Future<void> _restartScan() async {
    _autoConnectTriggered = false;
    if (_isConnectionInFlight) {
      await widget.bleService.disconnect(suppressAutoReconnect: true);
    }
    if (!mounted) return;
    setState(() {
      _connectingDeviceId = null;
    });
    await _startScan();
  }

  Future<void> _openControlScreen() async {
    if (_openingControlScreen) {
      return;
    }

    _openingControlScreen = true;

    if (!mounted) {
      _openingControlScreen = false;
      return;
    }

    if (widget.openControlOnConnect) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DeviceControlScreen(
            bleService: widget.bleService,
            activeKitchenName: widget.activeKitchenName,
          ),
        ),
      );
    }

    _openingControlScreen = false;

    if (mounted && !widget.bleService.isConnected) {
      if (widget.bleService.consumeAutoReconnectSuppressed()) {
        _autoConnectTriggered = false;
        return;
      }

      await _restartScan();
    }
  }

  Future<void> _connectToDevice(DiscoveredDevice device) async {
    if (!mounted) {
      return;
    }

    final config = widget.bleService.resolveConfigForDevice(device);

    setState(() {
      _connectingDeviceId = device.id;
    });

    final connected =
        await widget.bleService.connect(device: device, config: config);

    if (!mounted) {
      return;
    }

    setState(() {
      _connectingDeviceId = null;
    });

    if (!connected) {
      _autoConnectTriggered = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.bleService.lastConnectionError ??
                'Collegamento fallito. Riprova.',
          ),
        ),
      );
      return;
    }

    await SavedController(id: device.id, name: device.name).save(
      kitchenId: widget.kitchenId,
    );

    if (!mounted) return;

    if (!widget.openControlOnConnect) {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    await _openControlScreen();
  }

  _ScanFeedbackState _resolveScanFeedbackState({
    required String? scanError,
    required bool hasDevices,
  }) {
    final normalizedError = scanError?.toLowerCase();

    if (normalizedError != null) {
      if (normalizedError.contains('bluetooth') &&
          (normalizedError.contains('off') ||
              normalizedError.contains('spento') ||
              normalizedError.contains('disabled') ||
              normalizedError.contains('not powered'))) {
        return _ScanFeedbackState.bluetoothOff;
      }

      if (normalizedError.contains('perm') ||
          normalizedError.contains('denied') ||
          normalizedError.contains('autoriz')) {
        return _ScanFeedbackState.permissionDenied;
      }

      return _ScanFeedbackState.genericError;
    }

    if (!hasDevices) {
      return _ScanFeedbackState.noCompatibleDevices;
    }

    return _ScanFeedbackState.none;
  }

  String _scanStatusLabel(bool isScanning) {
    return isScanning ? 'Scansione in corso' : 'Scansione completata';
  }

  Widget _buildStatusCard({
    required BuildContext context,
    required String title,
    required String description,
    String? supportingLabel,
    IconData icon = Icons.bluetooth_searching_rounded,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                icon,
                size: 40,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (supportingLabel != null) ...[
              const SizedBox(height: 12),
              Text(
                supportingLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 24),
            if (actionLabel != null && onAction != null)
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectionMode
            ? 'Seleziona controller Bluetooth'
            : 'Scansione controller'),
        actions: [
          AnimatedBuilder(
            animation: widget.bleService,
            builder: (_, __) {
              final scanning = widget.bleService.isScanning;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    _scanStatusLabel(scanning),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.bleService,
        builder: (_, __) {
          final allDevices = widget.bleService.scanResults;
          final scanError = widget.bleService.lastScanError;
          final devices = _matchingDevices();
          final isConnecting = _connectingDeviceId != null;
          final isScanning = widget.bleService.isScanning;
          final feedbackState = _resolveScanFeedbackState(
            scanError: scanError,
            hasDevices: devices.isNotEmpty,
          );

          if (isConnecting) {
            return _buildStatusCard(
              context: context,
              title: widget.autoConnect
                  ? 'Collegamento automatico'
                  : 'Collegamento',
              description: widget.openControlOnConnect
                  ? 'Controller trovato. Apertura comandi in corso.'
                  : 'Collegamento al controller in corso.',
              supportingLabel: _connectingDeviceId,
              icon: Icons.bluetooth_connected_rounded,
            );
          }

          if (isScanning && allDevices.isEmpty) {
            return _buildStatusCard(
              context: context,
              title: _hasPreferredDevice
                  ? 'Cerco il controller salvato...'
                  : 'Cerco il controller...',
              description: _hasPreferredDevice && widget.autoConnect
                  ? 'Avvicina il telefono al controller e attendi il rilevamento automatico.'
                  : 'Avvicina il telefono al controller e selezionalo dalla lista.',
              supportingLabel: _hasPreferredDevice
                  ? 'Controller salvato: ${widget.preferredDeviceName ?? 'Controller Bluetooth'}'
                  : 'Tocca il controller corretto.',
              icon: Icons.bluetooth_searching_rounded,
            );
          }

          if (devices.isEmpty) {
            switch (feedbackState) {
              case _ScanFeedbackState.bluetoothOff:
                return _buildStatusCard(
                  context: context,
                  title: 'Bluetooth disattivato',
                  description: 'Attiva Bluetooth e riprova.',
                  icon: Icons.bluetooth_disabled_rounded,
                  actionLabel: 'Riprova',
                  onAction: _restartScan,
                );
              case _ScanFeedbackState.permissionDenied:
                return _buildStatusCard(
                  context: context,
                  title: 'Permesso Bluetooth non concesso',
                  description: 'Consenti l’accesso Bluetooth e riprova.',
                  icon: Icons.bluetooth_searching_rounded,
                  actionLabel: 'Riprova',
                  onAction: _restartScan,
                );
              case _ScanFeedbackState.genericError:
                return _buildStatusCard(
                  context: context,
                  title: 'Errore di scansione',
                  description: scanError!,
                  icon: Icons.error_outline_rounded,
                  actionLabel: 'Riprova',
                  onAction: _restartScan,
                );
              case _ScanFeedbackState.noCompatibleDevices:
                return _buildStatusCard(
                  context: context,
                  title: 'Nessun controller compatibile trovato',
                  description: 'Avvicina il telefono al controller e riprova.',
                  supportingLabel: _hasPreferredDevice
                      ? 'Controller salvato: ${widget.preferredDeviceName ?? widget.preferredDeviceId}'
                      : null,
                  icon: Icons.sensors_off_rounded,
                  actionLabel: 'Riprova',
                  onAction: _restartScan,
                );
              case _ScanFeedbackState.none:
                throw StateError(
                  'Unexpected scan feedback state with no matching devices.',
                );
            }
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.bluetooth_connected_rounded,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.selectionMode
                                    ? 'Dispositivi compatibili trovati'
                                    : (_hasPreferredDevice
                                        ? 'Controller salvato trovato'
                                        : 'Controller trovato'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _hasPreferredDevice && widget.autoConnect
                                    ? 'Il controller salvato viene collegato automaticamente quando disponibile.'
                                    : 'Seleziona il controller da associare.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.bleService.scanUsesServiceFilter)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: const Text(
                      'Scansione filtrata in corso, poi ricerca estesa.'),
                ),
              if (scanError != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(scanError),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final device = devices[index];
                    final isConnectingTile = _connectingDeviceId == device.id;
                    final resolvedConfig =
                        widget.bleService.resolveConfigForDevice(device);
                    final name = device.name.isNotEmpty
                        ? device.name
                        : 'Controller senza nome';

                    return ListTile(
                      tileColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        device.id == widget.preferredDeviceId
                            ? 'Controller salvato · Segnale ${device.rssi} dBm'
                            : 'Controller Bluetooth compatibile · Segnale ${device.rssi} dBm',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: false,
                      trailing: isConnectingTile
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.recommend),
                      onTap: isConnectingTile
                          ? null
                          : () => _connectToDevice(device),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _restartScan,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Ripeti scansione'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _ScanFeedbackState {
  none,
  bluetoothOff,
  permissionDenied,
  noCompatibleDevices,
  genericError,
}
