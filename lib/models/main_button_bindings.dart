import 'package:shared_preferences/shared_preferences.dart';

enum MainActionButton { onOff, scenari }

extension MainActionButtonX on MainActionButton {
  String get label {
    switch (this) {
      case MainActionButton.onOff:
        return 'On/Off';
      case MainActionButton.scenari:
        return 'Scenari';
    }
  }

  String get storageKey {
    switch (this) {
      case MainActionButton.onOff:
        return 'main_button_on_off';
      case MainActionButton.scenari:
        return 'main_button_scenari';
    }
  }
}

class MainButtonBindings {
  const MainButtonBindings({
    required this.onOffRelay,
    required this.scenariRelay,
  });

  const MainButtonBindings.empty()
    : onOffRelay = null,
      scenariRelay = null;

  final int? onOffRelay;
  final int? scenariRelay;

  int? relayFor(MainActionButton action) {
    switch (action) {
      case MainActionButton.onOff:
        return onOffRelay;
      case MainActionButton.scenari:
        return scenariRelay;
    }
  }

  MainButtonBindings copyWith({
    int? onOffRelay,
    int? scenariRelay,
    bool clearOnOff = false,
    bool clearScenari = false,
  }) {
    return MainButtonBindings(
      onOffRelay: clearOnOff ? null : (onOffRelay ?? this.onOffRelay),
      scenariRelay: clearScenari ? null : (scenariRelay ?? this.scenariRelay),
    );
  }

  Future<void> save(SharedPreferences preferences) async {
    await _saveRelay(preferences, MainActionButton.onOff.storageKey, onOffRelay);
    await _saveRelay(
      preferences,
      MainActionButton.scenari.storageKey,
      scenariRelay,
    );
  }

  static MainButtonBindings fromPreferences(SharedPreferences preferences) {
    return MainButtonBindings(
      onOffRelay: _readRelay(preferences, MainActionButton.onOff.storageKey),
      scenariRelay: _readRelay(preferences, MainActionButton.scenari.storageKey),
    );
  }

  static int? _readRelay(SharedPreferences preferences, String key) {
    final value = preferences.getInt(key);
    if (value == null || value < 1 || value > 4) {
      return null;
    }

    return value;
  }

  static Future<void> _saveRelay(
    SharedPreferences preferences,
    String key,
    int? relay,
  ) async {
    if (relay == null) {
      await preferences.remove(key);
      return;
    }

    await preferences.setInt(key, relay.clamp(1, 4));
  }
}
