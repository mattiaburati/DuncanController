import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedController {
  const SavedController({required this.id, required this.name});

  final String id;
  final String name;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'SH-BT04B' : trimmed;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'id': id, 'name': name.trim()};
  }

  static Future<SavedController?> load() {
    return SavedControllerStore.load();
  }

  Future<void> save({String? kitchenId}) {
    return SavedControllerStore.saveControllerForKitchen(
      kitchenId: kitchenId ?? SavedControllerStore.defaultKitchenId,
      controller: this,
    );
  }

  static SavedController fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Saved controller id is missing.');
    }

    final name = json['name'];
    return SavedController(id: id, name: name is String ? name : '');
  }
}

class SavedKitchen {
  const SavedKitchen({
    required this.id,
    required this.name,
    this.controller,
  });

  final String id;
  final String name;
  final SavedController? controller;

  String get displayName => SavedControllerStore.defaultKitchenName;

  SavedKitchen copyWith({
    String? id,
    String? name,
    SavedController? controller,
    bool clearController = false,
  }) {
    return SavedKitchen(
      id: id ?? this.id,
      name: name ?? this.name,
      controller: clearController ? null : (controller ?? this.controller),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'controller': controller?.toJson(),
    };
  }

  static SavedKitchen fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final controllerJson = json['controller'];

    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Saved kitchen id is missing.');
    }

    SavedController? controller;
    if (controllerJson != null) {
      if (controllerJson is! Map) {
        throw const FormatException(
            'Saved kitchen controller payload is invalid.');
      }
      controller = SavedController.fromJson(
        Map<String, Object?>.from(controllerJson as Map),
      );
    }

    return SavedKitchen(
      id: SavedControllerStore.defaultKitchenId,
      name: SavedControllerStore.defaultKitchenName,
      controller: controller,
    );
  }
}

class SavedKitchenState {
  const SavedKitchenState({
    required this.kitchens,
    required this.activeKitchenId,
  });

  final List<SavedKitchen> kitchens;
  final String activeKitchenId;

  SavedKitchen get activeKitchen {
    if (kitchens.length != 1) {
      throw StateError('Duncan-only state must contain exactly one kitchen.');
    }

    final kitchen = kitchens.single;
    if (activeKitchenId != kitchen.id) {
      throw StateError('Active kitchen "$activeKitchenId" is invalid.');
    }

    return kitchen;
  }

  SavedKitchenState copyWith({
    List<SavedKitchen>? kitchens,
    String? activeKitchenId,
  }) {
    return SavedKitchenState(
      kitchens: kitchens ?? this.kitchens,
      activeKitchenId: activeKitchenId ?? this.activeKitchenId,
    );
  }
}

class SavedControllerStore {
  static const String _stateKey = 'saved_controller_state_v1';
  static const String _legacyIdKey = 'saved_controller_id';
  static const String _legacyNameKey = 'saved_controller_name';
  static const String defaultKitchenId = 'kitchen_duncan';
  static const String defaultKitchenName = 'Duncan';
  static const String primaryKitchenId = defaultKitchenId;
  static const String primaryKitchenName = defaultKitchenName;

  static const List<SavedKitchen> defaultKitchens = <SavedKitchen>[
    SavedKitchen(id: defaultKitchenId, name: defaultKitchenName),
  ];

  static Future<SavedKitchenState> loadState() async {
    final preferences = await SharedPreferences.getInstance();
    final rawState = preferences.getString(_stateKey);
    if (rawState == null || rawState.trim().isEmpty) {
      return _loadLegacyState(preferences);
    }

    final decoded = jsonDecode(rawState);
    if (decoded is! Map) {
      throw const FormatException('Saved controller state payload is invalid.');
    }

    final stateJson = Map<String, Object?>.from(decoded as Map);
    final controllerJson = stateJson['controller'];
    if (controllerJson == null) {
      return _restoreFromLegacyKitchenState(stateJson);
    }
    if (controllerJson is! Map) {
      throw const FormatException('Saved controller payload is invalid.');
    }

    return _buildDefaultState(
      controller: SavedController.fromJson(
        Map<String, Object?>.from(controllerJson as Map),
      ),
    );
  }

  static Future<List<SavedKitchen>> loadKitchens() async {
    return (await loadState()).kitchens;
  }

  static Future<SavedKitchen> loadActiveKitchen() async {
    return (await loadState()).activeKitchen;
  }

  static Future<SavedController?> load() async {
    return (await loadState()).activeKitchen.controller;
  }

  static Future<void> setActiveKitchen(String kitchenId) async {
    if (kitchenId != defaultKitchenId) {
      throw StateError('Unknown Duncan kitchen id "$kitchenId".');
    }
  }

  static Future<void> saveControllerForKitchen({
    required String kitchenId,
    required SavedController controller,
  }) async {
    if (kitchenId != defaultKitchenId) {
      throw StateError(
          'Cannot save controller for unknown kitchen "$kitchenId".');
    }

    await saveState(_buildDefaultState(controller: controller));
  }

  static Future<void> saveState(SavedKitchenState state) async {
    final activeKitchen = state.activeKitchen;
    final preferences = await SharedPreferences.getInstance();

    if (activeKitchen.controller == null) {
      await preferences.remove(_stateKey);
      return;
    }

    final encoded = jsonEncode(<String, Object?>{
      'controller': activeKitchen.controller!.toJson(),
    });
    await preferences.setString(_stateKey, encoded);
  }

  static SavedKitchenState _buildDefaultState({SavedController? controller}) {
    return SavedKitchenState(
      kitchens: <SavedKitchen>[
        SavedKitchen(
          id: defaultKitchenId,
          name: defaultKitchenName,
          controller: controller,
        ),
      ],
      activeKitchenId: defaultKitchenId,
    );
  }

  static Future<SavedKitchenState> _loadLegacyState(
    SharedPreferences preferences,
  ) async {
    final legacyId = preferences.getString(_legacyIdKey);
    final controller = legacyId == null || legacyId.trim().isEmpty
        ? null
        : SavedController(
            id: legacyId,
            name: preferences.getString(_legacyNameKey) ?? '',
          );

    final state = _buildDefaultState(controller: controller);
    await saveState(state);
    return state;
  }

  static Future<SavedKitchenState> _restoreFromLegacyKitchenState(
    Map<String, Object?> stateJson,
  ) async {
    final kitchensJson = stateJson['kitchens'];
    if (kitchensJson is! List<Object?>) {
      throw const FormatException('Legacy kitchen state is invalid.');
    }

    SavedController? controller;
    for (final kitchenJson in kitchensJson) {
      if (kitchenJson is! Map) {
        throw const FormatException('Legacy kitchen entry is invalid.');
      }

      final kitchen =
          SavedKitchen.fromJson(Map<String, Object?>.from(kitchenJson as Map));
      if (kitchen.controller != null) {
        controller = kitchen.controller;
      }
    }

    final state = _buildDefaultState(controller: controller);
    await saveState(state);
    return state;
  }
}
