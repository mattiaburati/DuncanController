import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleDeviceConfig {
  const BleDeviceConfig({
    required this.id,
    required this.displayName,
    required this.serviceUuid,
    required this.controlCharacteristicUuid,
    required this.relayServiceConfirmed,
    required this.scanServiceUuids,
    required this.candidateNames,
    required this.candidateNamePrefixes,
    required this.candidateServiceUuids,
  });

  final String id;
  final String displayName;
  final Uuid serviceUuid;
  final Uuid controlCharacteristicUuid;
  final bool relayServiceConfirmed;
  final List<Uuid> scanServiceUuids;
  final List<String> candidateNames;
  final List<String> candidateNamePrefixes;
  final List<Uuid> candidateServiceUuids;

  List<int>? encodeRelayFrameBytes({
    required int relayIndex,
    required bool isOn,
  }) {
    if (!_isShBt04bProfileId(id)) {
      return null;
    }

    if (relayIndex < 1 || relayIndex > 8) {
      return null;
    }

    return _buildShBt04bCommandFrame(
      instructionCode: isOn ? 0x01 : 0x02,
      content: <int>[relayIndex],
    );
  }

  List<int>? encodeRelayStatusQueryFrameBytes() {
    if (!_isShBt04bProfileId(id)) {
      return null;
    }

    return _buildShBt04bCommandFrame(
      instructionCode: 0x05,
      content: const <int>[0x00],
    );
  }

  String encodeRelayCommand({required int relayIndex, required bool isOn}) {
    final frameBytes = encodeRelayFrameBytes(
      relayIndex: relayIndex,
      isOn: isOn,
    );
    if (frameBytes != null) {
      return frameBytes
          .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join();
    }

    final state = isOn ? 'ON' : 'OFF';
    return 'R$relayIndex:$state';
  }

  bool likelyMatches(DiscoveredDevice device) {
    return matchesByName(device.name) ||
        matchesByAdvertisedServices(device.serviceUuids);
  }

  bool matchesByName(String rawName) {
    final normalized = rawName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    final hasExactMatch = candidateNames.any(
      (candidate) => candidate.trim().toLowerCase() == normalized,
    );
    if (hasExactMatch) {
      return true;
    }

    return candidateNamePrefixes.any(
      (prefix) => normalized.startsWith(prefix.trim().toLowerCase()),
    );
  }

  bool matchesByAdvertisedServices(List<Uuid> advertisedServices) {
    return candidateServiceUuids.any(
      (candidate) => advertisedServices.any(
        (advertised) => _uuidMatches(candidate, advertised),
      ),
    );
  }

  static Uuid parseUuid16(String shortUuid) {
    return Uuid.parse('0000$shortUuid-0000-1000-8000-00805F9B34FB');
  }

  static const List<String> _shBt04bCandidateNames = [
    'DSD TECH SH-BT04B',
    'SH-BT04B',
    'BT04-B',
  ];

  static const List<String> _shBt04bCandidateNamePrefixes = [
    'DSD TECH',
    'SH-BT',
    'BT04',
  ];

  static final List<Uuid> _shBt04bScanServiceUuids = [
    parseUuid16('FFE0'),
    parseUuid16('FFF0'),
  ];

  static const int _shBt04bStartFlag = 0xA1;
  static const int _shBt04bEndFlag = 0xAA;
  static const int _shBt04bDefaultPassword = 1234;

  // NOTE: SH-BT04B variants often expose FFE0/FFE1 (HM-10 style), while some
  // modules are seen with FFF0/FFF1. Keep this as best-effort matching until
  // service/characteristic UUID are confirmed on the real hardware.
  static final BleDeviceConfig shBt04b = BleDeviceConfig(
    id: 'sh-bt04b',
    displayName: 'DSD TECH SH-BT04B',
    serviceUuid: parseUuid16('FFE0'),
    controlCharacteristicUuid: parseUuid16('FFE1'),
    relayServiceConfirmed: false,
    scanServiceUuids: _shBt04bScanServiceUuids,
    candidateNames: _shBt04bCandidateNames,
    candidateNamePrefixes: _shBt04bCandidateNamePrefixes,
    candidateServiceUuids: _shBt04bScanServiceUuids,
  );

  static final BleDeviceConfig shBt04bFfe = BleDeviceConfig(
    id: 'sh-bt04b-ffe',
    displayName: 'DSD TECH SH-BT04B (FFE0/FFE1)',
    serviceUuid: parseUuid16('FFE0'),
    controlCharacteristicUuid: parseUuid16('FFE1'),
    relayServiceConfirmed: true,
    scanServiceUuids: [parseUuid16('FFE0')],
    candidateNames: _shBt04bCandidateNames,
    candidateNamePrefixes: _shBt04bCandidateNamePrefixes,
    candidateServiceUuids: [parseUuid16('FFE0')],
  );

  static final BleDeviceConfig shBt04bFff = BleDeviceConfig(
    id: 'sh-bt04b-fff',
    displayName: 'DSD TECH SH-BT04B (FFF0/FFF1)',
    serviceUuid: parseUuid16('FFF0'),
    controlCharacteristicUuid: parseUuid16('FFF1'),
    relayServiceConfirmed: true,
    scanServiceUuids: [parseUuid16('FFF0')],
    candidateNames: _shBt04bCandidateNames,
    candidateNamePrefixes: _shBt04bCandidateNamePrefixes,
    candidateServiceUuids: [parseUuid16('FFF0')],
  );

  static final BleDeviceConfig placeholder = BleDeviceConfig(
    id: 'generic-relay-placeholder',
    displayName: 'Relay BLE Device',
    serviceUuid: parseUuid16('FFF0'),
    controlCharacteristicUuid: parseUuid16('FFF1'),
    relayServiceConfirmed: false,
    scanServiceUuids: [parseUuid16('FFF0')],
    candidateNames: const ['Relay BLE Device'],
    candidateNamePrefixes: const ['Relay'],
    candidateServiceUuids: [parseUuid16('FFF0')],
  );

  static final List<BleDeviceConfig> knownProfiles = [
    shBt04bFfe,
    shBt04bFff,
    placeholder,
  ];

  static BleDeviceConfig? confirmedProfileForGatt({
    required Uuid serviceUuid,
    required Uuid characteristicUuid,
  }) {
    for (final profile in knownProfiles) {
      if (!profile.relayServiceConfirmed) {
        continue;
      }

      final sameService = _uuidMatches(profile.serviceUuid, serviceUuid);
      final sameCharacteristic = _uuidMatches(
        profile.controlCharacteristicUuid,
        characteristicUuid,
      );

      if (sameService && sameCharacteristic) {
        return profile;
      }
    }

    return null;
  }

  static BleDeviceConfig profileForDevice(DiscoveredDevice device) {
    for (final profile in knownProfiles) {
      if (profile.likelyMatches(device)) {
        return profile;
      }
    }

    return shBt04b;
  }

  static bool _isShBt04bProfileId(String profileId) {
    return profileId.startsWith('sh-bt04b');
  }

  static List<int> _buildShBt04bCommandFrame({
    required int instructionCode,
    required List<int> content,
  }) {
    final passwordHighByte = (_shBt04bDefaultPassword >> 8) & 0xFF;
    final passwordLowByte = _shBt04bDefaultPassword & 0xFF;

    final payload = <int>[
      _shBt04bStartFlag,
      passwordHighByte,
      passwordLowByte,
      instructionCode,
      ...content,
    ];

    var checksum = 0;
    for (final value in payload) {
      checksum ^= value;
    }

    return <int>[...payload, checksum & 0xFF, _shBt04bEndFlag];
  }

  static bool _uuidMatches(Uuid a, Uuid b) {
    final normalizedA = _normalizeUuid(a.toString());
    final normalizedB = _normalizeUuid(b.toString());
    if (normalizedA == null || normalizedB == null) {
      return false;
    }

    if (normalizedA.kind == _NormalizedUuidKind.short16 &&
        normalizedB.kind == _NormalizedUuidKind.short16) {
      return normalizedA.value == normalizedB.value;
    }

    return normalizedA.value == normalizedB.value;
  }

  static _NormalizedUuid? _normalizeUuid(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.isEmpty) {
      return null;
    }

    final compact = lower.replaceAll('-', '');
    final short16Match = RegExp(r'^[0-9a-f]{4}$').hasMatch(compact);
    if (short16Match) {
      return _NormalizedUuid(
        kind: _NormalizedUuidKind.short16,
        value: compact,
      );
    }

    final full128Match = RegExp(r'^[0-9a-f]{32}$').hasMatch(compact);
    if (!full128Match) {
      return null;
    }

    final isBluetoothBase = compact.endsWith('00001000800000805f9b34fb');
    if (isBluetoothBase && compact.startsWith('0000')) {
      return _NormalizedUuid(
        kind: _NormalizedUuidKind.short16,
        value: compact.substring(4, 8),
      );
    }

    return _NormalizedUuid(kind: _NormalizedUuidKind.full128, value: compact);
  }
}

class _NormalizedUuid {
  const _NormalizedUuid({required this.kind, required this.value});

  final _NormalizedUuidKind kind;
  final String value;
}

enum _NormalizedUuidKind { short16, full128 }
