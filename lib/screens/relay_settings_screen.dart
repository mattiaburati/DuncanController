import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/relay_settings.dart';

class RelaySettingsScreen extends StatefulWidget {
  const RelaySettingsScreen({super.key, required this.initialSettings});

  final List<RelaySettings> initialSettings;

  @override
  State<RelaySettingsScreen> createState() => _RelaySettingsScreenState();
}

class _RelaySettingsScreenState extends State<RelaySettingsScreen> {
  static const List<int> _pulseChoices = <int>[100, 300, 500, 1000, 1500, 2000];
  static const List<RelayInteractionMode> _availableModes = <RelayInteractionMode>[
    RelayInteractionMode.pulseHold,
    RelayInteractionMode.pulseDouble,
  ];

  late final List<TextEditingController> _nameControllers;
  late final List<TextEditingController> _pulseControllers;
  late final List<RelaySettings> _draftSettings;

  @override
  void initState() {
    super.initState();
    _draftSettings = widget.initialSettings
        .map(
          (settings) => settings.copyWith(
            displayName: settings.displayName,
            mode: settings.mode,
            timerDuration: settings.timerDuration,
            pulseDuration: settings.pulseDuration,
          ),
        )
        .toList();
    _nameControllers = List<TextEditingController>.generate(
      _draftSettings.length,
      (index) => TextEditingController(text: _draftSettings[index].displayName),
    );
    _pulseControllers = List<TextEditingController>.generate(
      _draftSettings.length,
      (index) => TextEditingController(
        text: _draftSettings[index].pulseDuration.inMilliseconds.toString(),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    for (final controller in _pulseControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateRelay(int relayIndex, RelaySettings settings) {
    setState(() {
      _draftSettings[relayIndex - 1] = settings;
    });
  }

  void _save() {
    final updated = List<RelaySettings>.generate(_draftSettings.length, (index) {
      return _draftSettings[index].copyWith(
        displayName: _nameControllers[index].text.trim(),
      );
    });

    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni relè'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Salva'),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _draftSettings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final relayIndex = index + 1;
          final settings = _draftSettings[index];
          final pulseRawValue = _pulseControllers[index].text.trim();
          final parsedPulseValue = int.tryParse(pulseRawValue);
          final hasPulseValidationError =
              pulseRawValue.isNotEmpty &&
              (parsedPulseValue == null ||
                  parsedPulseValue < RelaySettings.minimumPulseMilliseconds ||
                  parsedPulseValue > RelaySettings.maximumPulseMilliseconds);

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Canale $relayIndex',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameControllers[index],
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nome relè',
                      hintText: 'Relè $relayIndex',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      _updateRelay(
                        relayIndex,
                        settings.copyWith(displayName: value.trim()),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Modalità',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                    SegmentedButton<RelayInteractionMode>(
                      segments: _availableModes
                          .map(
                            (mode) => ButtonSegment<RelayInteractionMode>(
                              value: mode,
                            label: Text(mode.label),
                          ),
                        )
                        .toList(),
                    selected: <RelayInteractionMode>{settings.mode},
                    onSelectionChanged: (selection) {
                      _updateRelay(
                        relayIndex,
                        settings.copyWith(mode: selection.first),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(settings.mode.description),
                  if (settings.mode == RelayInteractionMode.pulseHold ||
                      settings.mode == RelayInteractionMode.pulseDouble) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Durata impulso',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _pulseChoices.map((milliseconds) {
                        return ChoiceChip(
                          label: Text('${milliseconds}ms'),
                          selected:
                              settings.pulseDuration.inMilliseconds == milliseconds,
                          onSelected: (_) {
                            _pulseControllers[index].text = milliseconds.toString();
                            _updateRelay(
                              relayIndex,
                              settings.copyWith(
                                pulseDuration:
                                    Duration(milliseconds: milliseconds),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pulseControllers[index],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Durata personalizzata (ms)',
                        helperText:
                            'Valori ammessi: ${RelaySettings.minimumPulseMilliseconds}-${RelaySettings.maximumPulseMilliseconds} ms',
                        errorText: hasPulseValidationError
                            ? 'Inserisci un valore tra ${RelaySettings.minimumPulseMilliseconds} e ${RelaySettings.maximumPulseMilliseconds} ms'
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {});
                        final milliseconds = int.tryParse(value.trim());
                        if (milliseconds == null ||
                            milliseconds < RelaySettings.minimumPulseMilliseconds ||
                            milliseconds > RelaySettings.maximumPulseMilliseconds) {
                          return;
                        }

                        _updateRelay(
                          relayIndex,
                          settings.copyWith(
                            pulseDuration: Duration(milliseconds: milliseconds),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
