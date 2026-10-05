import 'package:flutter/material.dart';

import '../models/device_state.dart';

/// Three chips: Manual / Assisted / Autonomous. Publishes home/mode/set
/// when tapped, but the chip shown as selected always reflects
/// `currentMode` (which comes from home/mode/state, the ESP32's
/// confirmation) - the device is the source of truth, not the tap.
class ModeSelector extends StatelessWidget {
  final OperatingMode currentMode;
  final void Function(OperatingMode) onModeSelected;

  const ModeSelector({
    super.key,
    required this.currentMode,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: OperatingMode.values.map((mode) {
        final selected = mode == currentMode;
        return ChoiceChip(
          label: Text(_label(mode)),
          selected: selected,
          onSelected: (_) => onModeSelected(mode),
        );
      }).toList(),
    );
  }

  String _label(OperatingMode mode) {
    switch (mode) {
      case OperatingMode.manual:
        return 'Manual';
      case OperatingMode.assisted:
        return 'Assisted';
      case OperatingMode.autonomous:
        return 'Autonomous';
    }
  }
}
