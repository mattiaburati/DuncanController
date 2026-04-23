# BLE Relay Controller (Flutter)

App Flutter minima per scansione BLE, connessione a un device e controllo di 4 relè.

## File principali

- `lib/main.dart`
- `lib/models/ble_device_config.dart`
- `lib/services/ble_service.dart`
- `lib/screens/device_scan_screen.dart`
- `lib/screens/device_control_screen.dart`

## Configurazione UUID e protocollo

1. Apri `lib/models/ble_device_config.dart`.
2. Sostituisci gli UUID placeholder:
   - `serviceUuid`
   - `controlCharacteristicUuid`
   - `scanServiceUuids`
3. Adatta l'encoder comandi in `encodeRelayCommand(...)`.
   - Formato attuale placeholder: `R1:ON`, `R2:OFF`, ecc.

## Scan SH-BT04B (stato attuale)

- Il profilo `DSD TECH SH-BT04B` in `lib/models/ble_device_config.dart` distingue ora tra varianti `FFE0/FFE1` e `FFF0/FFF1`, con fallback prudente quando il device espone solo il nome ma non i servizi in advertising.
- La scansione in `lib/services/ble_service.dart` parte con filtro servizi candidati e passa automaticamente a scansione non filtrata, per ridurre i falsi negativi su advertising incompleto.
- La UI `lib/screens/device_scan_screen.dart` mostra tutti i device ma evidenzia quelli consigliati per SH-BT04B.
- Se la connessione avviene solo tramite nome e non tramite servizi advertised, la schermata relè resta prudenzialmente disabilitata finche' il percorso BLE non e' confermato.
- Il protocollo relè resta placeholder e va confermato sul dispositivo reale.

## Permessi BLE

- Android: `android/app/src/main/AndroidManifest.xml` include permessi BLE Android 12+ e fallback compatibile per Android <= 11.
- iOS: `ios/Runner/Info.plist` include `NSBluetoothAlwaysUsageDescription` e `NSBluetoothPeripheralUsageDescription`.

## Avvio progetto

Quando Flutter CLI e' disponibile:

```bash
flutter pub get
flutter run
```

Se mancano file platform/tooling nel tuo ambiente, genera lo scaffold standard Flutter e mantieni i file `lib/` e i permessi BLE gia' configurati.
