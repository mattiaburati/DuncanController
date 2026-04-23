import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rele_controller/main.dart';
import 'package:rele_controller/services/ble_service.dart';

void main() {
  testWidgets('renders BLE scan screen', (WidgetTester tester) async {
    await tester.pumpWidget(ReleControllerApp(bleService: BleService()));

    expect(find.text('Scansione BLE'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);
  });
}
