import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../models/ble_device_config.dart';

class BleService extends ChangeNotifier {
  BleService() : _ble = FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  final List<DiscoveredDevice> _scanResults = [];
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _relayNotificationSubscription;
  Timer? _scanFallbackTimer;

  bool _isScanning = false;
  bool _scanUsesServiceFilter = false;
  String? _connectedDeviceId;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  BleDeviceConfig? _deviceConfig;
  bool _writeWithoutResponse = false;
  Uuid? _resolvedRelayServiceUuid;
  Uuid? _resolvedRelayCharacteristicUuid;
  String? _lastGattDiscoverySummary;
  String? _relayWarningDetail;
  String? _lastScanError;
  String? _lastConnectionError;
  String? _lastProtocolMessage;
  String? _lastWriteServiceUuid;
  String? _lastWriteCharacteristicUuid;
  String? _lastWritePayloadHex;
  bool? _lastWriteSucceeded;
  bool _suppressAutoReconnectOnce = false;
  final List<int> _notificationBuffer = <int>[];
  final List<bool> _relayStates = List<bool>.filled(8, false);
  int _knownRelayCount = 0;

  List<DiscoveredDevice> get scanResults => List.unmodifiable(_scanResults);
  bool get isScanning => _isScanning;
  bool get scanUsesServiceFilter => _scanUsesServiceFilter;
  String? get connectedDeviceId => _connectedDeviceId;
  DeviceConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == DeviceConnectionState.connected;
  bool get relayControlReady => _deviceConfig?.relayServiceConfirmed ?? false;
  String? get lastScanError => _lastScanError;
  String? get lastConnectionError => _lastConnectionError;
  String? get lastProtocolMessage => _lastProtocolMessage;
  String? get lastWriteServiceUuid => _lastWriteServiceUuid;
  String? get lastWriteCharacteristicUuid => _lastWriteCharacteristicUuid;
  String? get lastWritePayloadHex => _lastWritePayloadHex;
  bool? get lastWriteSucceeded => _lastWriteSucceeded;
  bool get hasKnownRelayStates => _knownRelayCount > 0;
  int get knownRelayCount => _knownRelayCount;
  List<bool> get relayStates => List<bool>.unmodifiable(_relayStates);
  bool get hasWriteDiagnostics =>
      _lastWriteServiceUuid != null ||
      _lastWriteCharacteristicUuid != null ||
      _lastWritePayloadHex != null ||
      _lastWriteSucceeded != null;
  bool get isConnectedShBt04b => _isShBt04bConfig(_deviceConfig);

  bool consumeAutoReconnectSuppressed() {
    final suppressed = _suppressAutoReconnectOnce;
    _suppressAutoReconnectOnce = false;
    return suppressed;
  }

  String? get relayControlWarning {
    final config = _deviceConfig;
    if (config == null || config.relayServiceConfirmed) {
      return null;
    }

    final detail = _relayWarningDetail == null ? '' : ' ${_relayWarningDetail!}';
    final diagnostic = _lastGattDiscoverySummary == null
        ? ''
        : ' GATT: $_lastGattDiscoverySummary';

    if (config.id == BleDeviceConfig.shBt04b.id) {
      return 'Connesso a SH-BT04B, ma UUID servizio/caratteristica da confermare prima dei comandi relè.$detail$diagnostic';
    }

    return 'Connesso al device, ma percorso BLE dei relè non ancora confermato.$detail$diagnostic';
  }

  Future<void> startScan({
    List<Uuid>? withServices,
    bool fallbackToUnfiltered = true,
    Duration filteredScanWindow = const Duration(seconds: 4),
  }) async {
    await stopScan();

    _scanResults.clear();
    _isScanning = true;
    _lastScanError = null;

    final requestedServices = withServices ?? const <Uuid>[];
    final hasServiceFilter = requestedServices.isNotEmpty;
    _scanUsesServiceFilter = hasServiceFilter;
    notifyListeners();

    _startScanSubscription(withServices: requestedServices);

    if (hasServiceFilter && fallbackToUnfiltered) {
      _scanFallbackTimer = Timer(filteredScanWindow, () {
        if (!_isScanning) {
          return;
        }

        _scanUsesServiceFilter = false;
        _startScanSubscription(withServices: const <Uuid>[]);
        notifyListeners();
      });
    }
  }

  Future<void> stopScan() async {
    _scanFallbackTimer?.cancel();
    _scanFallbackTimer = null;

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    if (_isScanning) {
      _isScanning = false;
      _scanUsesServiceFilter = false;
      notifyListeners();
    }
  }

  Future<bool> connect({
    required DiscoveredDevice device,
    required BleDeviceConfig config,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    _suppressAutoReconnectOnce = false;
    await stopScan();
    await disconnect();

    _connectedDeviceId = device.id;
    _connectionState = DeviceConnectionState.connecting;
    _deviceConfig = _isShBt04bConfig(config) ? BleDeviceConfig.shBt04b : config;
    _writeWithoutResponse = false;
    _resolvedRelayServiceUuid = null;
    _resolvedRelayCharacteristicUuid = null;
    _lastGattDiscoverySummary = null;
    _relayWarningDetail = null;
    _lastConnectionError = null;
    _lastProtocolMessage = null;
    _clearRelayStates();
    _resetWriteDiagnostics();
    notifyListeners();

    final completer = Completer<bool>();

    _connectionSubscription = _ble
        .connectToDevice(id: device.id, connectionTimeout: timeout)
        .listen(
          (update) {
            _connectionState = update.connectionState;

            if (update.connectionState == DeviceConnectionState.disconnected) {
              _connectedDeviceId = null;
              _deviceConfig = null;
              _writeWithoutResponse = false;
              _resolvedRelayServiceUuid = null;
              _resolvedRelayCharacteristicUuid = null;
              _lastGattDiscoverySummary = null;
              _relayWarningDetail = null;
              _lastProtocolMessage = null;
              _clearRelayStates();
              _resetWriteDiagnostics();
            }

            if (!completer.isCompleted &&
                update.connectionState == DeviceConnectionState.connected) {
              _confirmRelayPathIfPossible(device.id).whenComplete(() {
                if (!completer.isCompleted) {
                  completer.complete(true);
                }
              });
            }

            if (!completer.isCompleted &&
                update.connectionState == DeviceConnectionState.disconnected) {
              _lastConnectionError = 'Dispositivo disconnesso durante la connessione.';
              completer.complete(false);
            }

            notifyListeners();
          },
          onError: (Object error) {
            _connectionState = DeviceConnectionState.disconnected;
            _connectedDeviceId = null;
            _deviceConfig = null;
            _writeWithoutResponse = false;
            _resolvedRelayServiceUuid = null;
            _resolvedRelayCharacteristicUuid = null;
            _lastGattDiscoverySummary = null;
            _relayWarningDetail = null;
            _lastConnectionError = 'Errore connessione BLE: $error';
            _lastProtocolMessage = null;
            _clearRelayStates();
            _resetWriteDiagnostics();

            if (!completer.isCompleted) {
              completer.complete(false);
            }

            notifyListeners();
          },
        );

    return completer.future;
  }

  Future<void> disconnect({bool suppressAutoReconnect = true}) async {
    if (suppressAutoReconnect) {
      _suppressAutoReconnectOnce = true;
    }

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _relayNotificationSubscription?.cancel();
    _relayNotificationSubscription = null;

    _connectedDeviceId = null;
    _deviceConfig = null;
    _writeWithoutResponse = false;
    _resolvedRelayServiceUuid = null;
    _resolvedRelayCharacteristicUuid = null;
    _lastGattDiscoverySummary = null;
    _relayWarningDetail = null;
    _connectionState = DeviceConnectionState.disconnected;
    _lastConnectionError = null;
    _lastProtocolMessage = null;
    _clearRelayStates();
    _resetWriteDiagnostics();
    notifyListeners();
  }

  BleDeviceConfig resolveConfigForDevice(DiscoveredDevice device) {
    for (final profile in BleDeviceConfig.knownProfiles) {
      if (profile.matchesByAdvertisedServices(device.serviceUuids) ||
          _matchesCandidateServiceData(device, profile)) {
        return profile;
      }
    }

    if (BleDeviceConfig.shBt04b.matchesByName(device.name)) {
      return BleDeviceConfig.shBt04b;
    }

    return BleDeviceConfig.placeholder;
  }

  bool isLikelyTargetDevice(
    DiscoveredDevice device, {
    BleDeviceConfig? preferredProfile,
  }) {
    final profile = preferredProfile ?? BleDeviceConfig.shBt04b;
    if (profile.likelyMatches(device)) {
      return true;
    }

    return _matchesCandidateServiceData(device, profile);
  }

  Future<bool> writeRelayCommand({
    required int relayIndex,
    required bool isOn,
  }) async {
    final deviceId = _connectedDeviceId;
    final config = _deviceConfig;

    if (deviceId == null || config == null || !isConnected) {
      _lastWriteSucceeded = false;
      notifyListeners();
      return false;
    }

    if (_isShBt04bConfig(config)) {
      final binaryPayload = config.encodeRelayFrameBytes(
        relayIndex: relayIndex,
        isOn: isOn,
      );
      if (binaryPayload == null) {
        _lastWriteSucceeded = false;
        notifyListeners();
        return false;
      }

      if (!config.relayServiceConfirmed) {
        _lastWritePayloadHex = _payloadToHex(binaryPayload);
        _lastWriteSucceeded = false;
        notifyListeners();
        return false;
      }

      final serviceUuid = _resolvedRelayServiceUuid ?? config.serviceUuid;
      final characteristicUuid =
          _resolvedRelayCharacteristicUuid ?? config.controlCharacteristicUuid;

      final didWrite = await _writePayload(
        characteristic: QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: characteristicUuid,
          deviceId: deviceId,
        ),
        payload: binaryPayload,
      );

      if (!didWrite) {
        return false;
      }

      return true;
    }

    if (!config.relayServiceConfirmed) {
      _lastWriteSucceeded = false;
      notifyListeners();
      return false;
    }

    final serviceUuid = _resolvedRelayServiceUuid ?? config.serviceUuid;
    final characteristicUuid =
        _resolvedRelayCharacteristicUuid ?? config.controlCharacteristicUuid;
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    final command = config.encodeRelayCommand(relayIndex: relayIndex, isOn: isOn);
    return _writePayload(
      characteristic: characteristic,
      payload: utf8.encode(command),
    );
  }

  void _upsertScannedDevice(DiscoveredDevice device) {
    final index = _scanResults.indexWhere((d) => d.id == device.id);

    if (index == -1) {
      _scanResults.add(device);
    } else {
      _scanResults[index] = device;
    }

    _scanResults.sort((a, b) {
      final an = a.name.isNotEmpty ? a.name : a.id;
      final bn = b.name.isNotEmpty ? b.name : b.id;
      return an.toLowerCase().compareTo(bn.toLowerCase());
    });

    notifyListeners();
  }

  void _startScanSubscription({required List<Uuid> withServices}) {
    _scanSubscription?.cancel();

    _scanSubscription = _ble
        .scanForDevices(withServices: withServices, scanMode: ScanMode.lowLatency)
        .listen(
          _upsertScannedDevice,
          onError: (Object error) {
            _lastScanError = 'Errore scansione BLE: $error';
            _isScanning = false;
            _scanUsesServiceFilter = false;
            notifyListeners();
          },
        );
  }

  bool _matchesCandidateServiceData(
    DiscoveredDevice device,
    BleDeviceConfig profile,
  ) {
    if (device.serviceData.isEmpty) {
      return false;
    }

    final candidateShortUuids = profile.candidateServiceUuids
        .map(_extract16BitUuid)
        .whereType<int>()
        .toSet();

    if (candidateShortUuids.isEmpty) {
      return false;
    }

    for (final advertisedServiceDataId in device.serviceData.keys) {
      final normalizedId = _normalizeServiceDataKey(advertisedServiceDataId);
      if (normalizedId != null && candidateShortUuids.contains(normalizedId)) {
        return true;
      }
    }

    return false;
  }

  int? _extract16BitUuid(Uuid uuid) {
    final raw = uuid.toString().trim().toLowerCase();

    final shortMatch = RegExp(r'^[0-9a-f]{4}$').firstMatch(raw);
    if (shortMatch != null) {
      return int.parse(shortMatch.group(0)!, radix: 16);
    }

    final hexPrefixMatch = RegExp(r'^0x([0-9a-f]{4})$').firstMatch(raw);
    if (hexPrefixMatch != null) {
      return int.parse(hexPrefixMatch.group(1)!, radix: 16);
    }

    final canonicalMatch = RegExp(
      r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (canonicalMatch != null) {
      return int.parse(canonicalMatch.group(1)!, radix: 16);
    }

    final compact = raw.replaceAll('-', '');
    final compactBaseMatch = RegExp(
      r'^0000([0-9a-f]{4})00001000800000805f9b34fb$',
      caseSensitive: false,
    ).firstMatch(compact);
    if (compactBaseMatch != null) {
      return int.parse(compactBaseMatch.group(1)!, radix: 16);
    }

    return null;
  }

  int? _normalizeServiceDataKey(Object key) {
    if (key is int) {
      return key;
    }

    if (key is Uuid) {
      return _extract16BitUuid(key);
    }

    final text = key.toString().trim().toLowerCase();
    final hexMatch = RegExp(r'0x([0-9a-f]{4})').firstMatch(text);
    if (hexMatch != null) {
      return int.parse(hexMatch.group(1)!, radix: 16);
    }

    return int.tryParse(text);
  }

  Future<void> _confirmRelayPathIfPossible(String deviceId) async {
    try {
      await _ble.discoverAllServices(deviceId);
      final services = await _ble.getDiscoveredServices(deviceId);
      _lastGattDiscoverySummary = _buildGattSummary(services);
      _relayWarningDetail = null;

      _resolvedRelayServiceUuid = null;
      _resolvedRelayCharacteristicUuid = null;

      if (_deviceConfig != null && _isShBt04bConfig(_deviceConfig)) {
        final resolvedPath = _resolveShBt04bOfficialPath(services);
        if (resolvedPath != null) {
          _deviceConfig = BleDeviceConfig.shBt04bFfe;
          _resolvedRelayServiceUuid = resolvedPath.service.id;
          _resolvedRelayCharacteristicUuid = resolvedPath.characteristic.id;
          _writeWithoutResponse =
              resolvedPath.characteristic.isWritableWithoutResponse;
          _relayWarningDetail = null;
          await _startRelayNotificationsIfAvailable(deviceId, resolvedPath);
          await queryRelayStatus();
          notifyListeners();
          return;
        }

        _deviceConfig = BleDeviceConfig.shBt04b;
        _relayWarningDetail =
            'Path ufficiale FFE0/FFE1 non trovato o non scrivibile.';
        notifyListeners();
        return;
      }

      for (final service in services) {
        for (final characteristic in service.characteristics) {
          final matchedProfile = BleDeviceConfig.confirmedProfileForGatt(
            serviceUuid: service.id,
            characteristicUuid: characteristic.id,
          );

          if (matchedProfile == null) {
            continue;
          }

          final canWriteWithResponse = characteristic.isWritableWithResponse;
          final canWriteWithoutResponse =
              characteristic.isWritableWithoutResponse;

          if (!canWriteWithResponse && !canWriteWithoutResponse) {
            continue;
          }

          _deviceConfig = matchedProfile;
          _resolvedRelayServiceUuid = service.id;
          _resolvedRelayCharacteristicUuid = characteristic.id;
          _writeWithoutResponse = canWriteWithoutResponse;
          _relayWarningDetail = null;
          await _startRelayNotificationsIfAvailable(
            deviceId,
            _GattPath(service: service, characteristic: characteristic),
          );
          notifyListeners();
          return;
        }
      }
    } catch (error) {
      _lastConnectionError = 'Connessione BLE ok, ma discovery servizi fallita: $error';
      notifyListeners();
    }
  }

  String _buildGattSummary(List<Service> services) {
    if (services.isEmpty) {
      return 'nessun servizio scoperto';
    }

    const maxServices = 3;
    const maxCharsPerService = 3;
    final segments = <String>[];

    for (final service in services.take(maxServices)) {
      final chars = service.characteristics.take(maxCharsPerService).map((c) {
        final flags = <String>[];
        if (c.isWritableWithResponse || c.isWritableWithoutResponse) {
          flags.add('W');
        }
        if (c.isReadable) {
          flags.add('R');
        }
        if (c.isNotifiable) {
          flags.add('N');
        }

        final flagsText = flags.isEmpty ? '' : '/${flags.join()}';
        return '${_compactUuid(c.id)}$flagsText';
      }).join(',');

      final suffix = service.characteristics.length > maxCharsPerService
          ? ',+${service.characteristics.length - maxCharsPerService}'
          : '';
      segments.add('${_compactUuid(service.id)}[$chars$suffix]');
    }

    final extraServices = services.length > maxServices
        ? ' +${services.length - maxServices} srv'
        : '';

    return '${segments.join(' | ')}$extraServices';
  }

  _GattPath? _resolveShBt04bOfficialPath(List<Service> services) {
    for (final service in services) {
      if (_extract16BitUuid(service.id) != 0xFFE0) {
        continue;
      }

      for (final characteristic in service.characteristics) {
        if (_extract16BitUuid(characteristic.id) != 0xFFE1) {
          continue;
        }

        if (!characteristic.isWritableWithResponse &&
            !characteristic.isWritableWithoutResponse) {
          continue;
        }

        return _GattPath(service: service, characteristic: characteristic);
      }
    }

    return null;
  }

  String _compactUuid(Uuid uuid) {
    final shortValue = _extract16BitUuid(uuid);
    if (shortValue != null) {
      return shortValue.toRadixString(16).toUpperCase().padLeft(4, '0');
    }

    return uuid.toString().toUpperCase();
  }

  bool _isShBt04bConfig(BleDeviceConfig? config) {
    return config != null && config.id.startsWith('sh-bt04b');
  }

  Future<bool> _writePayload({
    required QualifiedCharacteristic characteristic,
    required List<int> payload,
    bool? writeWithoutResponse,
  }) async {
    _lastWriteServiceUuid = _compactUuid(characteristic.serviceId);
    _lastWriteCharacteristicUuid = _compactUuid(characteristic.characteristicId);
    _lastWritePayloadHex = _payloadToHex(payload);

    try {
      final useWriteWithoutResponse = writeWithoutResponse ?? _writeWithoutResponse;
      if (useWriteWithoutResponse) {
        await _ble.writeCharacteristicWithoutResponse(
          characteristic,
          value: payload,
        );
      } else {
        await _ble.writeCharacteristicWithResponse(
          characteristic,
          value: payload,
        );
      }

      _lastWriteSucceeded = true;
      notifyListeners();
      return true;
    } catch (error) {
      _lastWriteSucceeded = false;
      _lastConnectionError = 'Invio comando BLE fallito: $error';
      notifyListeners();
      return false;
    }
  }

  void _resetWriteDiagnostics() {
    _lastWriteServiceUuid = null;
    _lastWriteCharacteristicUuid = null;
    _lastWritePayloadHex = null;
    _lastWriteSucceeded = null;
  }

  String _payloadToHex(List<int> payload) {
    return payload
        .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  Future<bool> queryRelayStatus() async {
    final deviceId = _connectedDeviceId;
    final config = _deviceConfig;
    if (deviceId == null || config == null || !isConnected) {
      return false;
    }

    if (!_isShBt04bConfig(config)) {
      return false;
    }

    if (!config.relayServiceConfirmed) {
      return false;
    }

    final payload = config.encodeRelayStatusQueryFrameBytes();
    if (payload == null) {
      return false;
    }

    final serviceUuid = _resolvedRelayServiceUuid ?? config.serviceUuid;
    final characteristicUuid =
        _resolvedRelayCharacteristicUuid ?? config.controlCharacteristicUuid;

    return _writePayload(
      characteristic: QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
        deviceId: deviceId,
      ),
      payload: payload,
    );
  }

  Future<void> _startRelayNotificationsIfAvailable(
    String deviceId,
    _GattPath path,
  ) async {
    await _relayNotificationSubscription?.cancel();
    _relayNotificationSubscription = null;
    _notificationBuffer.clear();

    if (!path.characteristic.isNotifiable) {
      return;
    }

    final characteristic = QualifiedCharacteristic(
      serviceId: path.service.id,
      characteristicId: path.characteristic.id,
      deviceId: deviceId,
    );

    _relayNotificationSubscription = _ble
        .subscribeToCharacteristic(characteristic)
        .listen(
          _handleRelayNotificationData,
          onError: (Object error) {
            _lastConnectionError = 'Notifiche relè fallite: $error';
            notifyListeners();
          },
        );
  }

  void _handleRelayNotificationData(List<int> data) {
    if (data.isEmpty) {
      return;
    }

    _notificationBuffer.addAll(data);

    while (true) {
      final startIndex = _notificationBuffer.indexOf(0xA1);
      if (startIndex == -1) {
        _notificationBuffer.clear();
        return;
      }

      if (startIndex > 0) {
        _notificationBuffer.removeRange(0, startIndex);
      }

      final endIndex = _notificationBuffer.indexOf(0xAA, 1);
      if (endIndex == -1) {
        return;
      }

      final frame = List<int>.from(_notificationBuffer.sublist(0, endIndex + 1));
      _notificationBuffer.removeRange(0, endIndex + 1);
      _processIncomingFrame(frame);
    }
  }

  void _processIncomingFrame(List<int> frame) {
    if (frame.length < 5 || frame.first != 0xA1 || frame.last != 0xAA) {
      return;
    }

    final expectedChecksum = frame[frame.length - 2];
    var actualChecksum = 0;
    for (final value in frame.sublist(0, frame.length - 2)) {
      actualChecksum ^= value;
    }

    if ((actualChecksum & 0xFF) != expectedChecksum) {
      _lastProtocolMessage = 'Frame relè ignorato: checksum non valido.';
      notifyListeners();
      return;
    }

    final instructionCode = frame[1];
    final payload = frame.sublist(2, frame.length - 2);

    switch (instructionCode) {
      case 0x01:
      case 0x02:
      case 0x03:
      case 0x04:
      case 0x06:
      case 0x07:
      case 0x08:
      case 0x11:
        final succeeded = payload.isNotEmpty && payload.first == 0x01;
        _lastProtocolMessage = succeeded
            ? 'Controller ha confermato il comando.'
            : 'Controller ha rifiutato il comando.';
        notifyListeners();
        return;
      case 0x05:
      case 0x81:
        _applyRelayStatusPayload(payload);
        return;
      default:
        _lastProtocolMessage =
            'Risposta controller ${instructionCode.toRadixString(16).padLeft(2, '0').toUpperCase()} ricevuta.';
        notifyListeners();
        return;
    }
  }

  void _applyRelayStatusPayload(List<int> payload) {
    if (payload.length < 2) {
      return;
    }

    final relayCount = payload.first.clamp(0, _relayStates.length);
    final rawStatuses = payload.sublist(1);
    if (rawStatuses.length < relayCount) {
      return;
    }

    for (var relayIndex = 1; relayIndex <= relayCount; relayIndex++) {
      final statusByte = rawStatuses[relayCount - relayIndex];
      _relayStates[relayIndex - 1] = statusByte != 0x00;
    }

    for (var relayIndex = relayCount; relayIndex < _relayStates.length; relayIndex++) {
      _relayStates[relayIndex] = false;
    }

    _knownRelayCount = relayCount;
    _lastProtocolMessage = 'Stato relè sincronizzato dal controller.';
    notifyListeners();
  }

  void _clearRelayStates() {
    _notificationBuffer.clear();
    _knownRelayCount = 0;
    for (var index = 0; index < _relayStates.length; index++) {
      _relayStates[index] = false;
    }
  }

  @override
  void dispose() {
    _scanFallbackTimer?.cancel();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _relayNotificationSubscription?.cancel();
    super.dispose();
  }
}

class _GattPath {
  const _GattPath({
    required this.service,
    required this.characteristic,
  });

  final Service service;
  final Characteristic characteristic;
}
