import 'package:shared_preferences/shared_preferences.dart';

enum RelayInteractionMode { pulseHold, pulseDouble }

extension RelayInteractionModeX on RelayInteractionMode {
  String get storageValue {
    switch (this) {
      case RelayInteractionMode.pulseHold:
        return 'pulse_hold';
      case RelayInteractionMode.pulseDouble:
        return 'pulse_double';
    }
  }

  String get label {
    switch (this) {
      case RelayInteractionMode.pulseHold:
        return 'Pulsante';
      case RelayInteractionMode.pulseDouble:
        return 'Pulsante 2';
    }
  }

  String get description {
    switch (this) {
      case RelayInteractionMode.pulseHold:
        return 'Tap: impulso ON/OFF. Hold: il relè resta attivo finché tieni premuto.';
      case RelayInteractionMode.pulseDouble:
        return 'Tap: impulso ON/OFF. Double tap: ciclo ON/OFF ON/OFF.';
    }
  }

  static RelayInteractionMode fromStorage(String? rawValue) {
    switch (rawValue) {
      case 'pulse_hold':
        return RelayInteractionMode.pulseHold;
      case 'pulse_double':
      case 'pulse':
        return RelayInteractionMode.pulseDouble;
      case 'toggle':
      case 'timer':
      case 'hold':
      case null:
        return RelayInteractionMode.pulseHold;
    }

    return RelayInteractionMode.pulseHold;
  }
}

class RelaySettings {
  static const int minimumTimerSeconds = 1;
  static const int maximumTimerSeconds = 120;
  static const int minimumPulseMilliseconds = 100;
  static const int maximumPulseMilliseconds = 2000;

  const RelaySettings({
    this.displayName = '',
    this.mode = RelayInteractionMode.pulseHold,
    this.timerDuration = const Duration(seconds: 3),
    this.pulseDuration = const Duration(milliseconds: 300),
  });

  final String displayName;
  final RelayInteractionMode mode;
  final Duration timerDuration;
  final Duration pulseDuration;

  RelaySettings copyWith({
    String? displayName,
    RelayInteractionMode? mode,
    Duration? timerDuration,
    Duration? pulseDuration,
  }) {
    return RelaySettings(
      displayName: displayName ?? this.displayName,
      mode: mode ?? this.mode,
      timerDuration: timerDuration ?? this.timerDuration,
      pulseDuration: pulseDuration ?? this.pulseDuration,
    );
  }

  String resolvedName(int relayIndex) {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? 'Relè $relayIndex' : trimmed;
  }

  static RelaySettings fromPreferences(
    SharedPreferences preferences,
    int relayIndex,
  ) {
    final mode = RelayInteractionModeX.fromStorage(
      preferences.getString(_modeKey(relayIndex)),
    );
    final storedSeconds = preferences.getInt(_timerSecondsKey(relayIndex));
    final normalizedSeconds = _normalizeTimerSeconds(storedSeconds ?? 3);
    final storedPulseMilliseconds = preferences.getInt(_pulseMillisecondsKey(relayIndex));
    final normalizedPulseMilliseconds =
        _normalizePulseMilliseconds(storedPulseMilliseconds ?? 300);

    return RelaySettings(
      displayName: preferences.getString(_nameKey(relayIndex)) ?? '',
      mode: mode,
      timerDuration: Duration(seconds: normalizedSeconds),
      pulseDuration: Duration(milliseconds: normalizedPulseMilliseconds),
    );
  }

  Future<void> saveToPreferences(
    SharedPreferences preferences,
    int relayIndex,
  ) async {
    await preferences.setString(_nameKey(relayIndex), displayName.trim());
    await preferences.setString(_modeKey(relayIndex), mode.storageValue);
    await preferences.setInt(
      _timerSecondsKey(relayIndex),
      _normalizeTimerSeconds(timerDuration.inSeconds),
    );
    await preferences.setInt(
      _pulseMillisecondsKey(relayIndex),
      _normalizePulseMilliseconds(pulseDuration.inMilliseconds),
    );
  }

  static String _nameKey(int relayIndex) => 'relay_${relayIndex}_name';

  static String _modeKey(int relayIndex) => 'relay_${relayIndex}_mode';

  static String _timerSecondsKey(int relayIndex) =>
      'relay_${relayIndex}_timer_seconds';

  static String _pulseMillisecondsKey(int relayIndex) =>
      'relay_${relayIndex}_pulse_milliseconds';

  static int _normalizeTimerSeconds(int seconds) {
    return seconds.clamp(minimumTimerSeconds, maximumTimerSeconds);
  }

  static int _normalizePulseMilliseconds(int milliseconds) {
    return milliseconds.clamp(
      minimumPulseMilliseconds,
      maximumPulseMilliseconds,
    );
  }
}
