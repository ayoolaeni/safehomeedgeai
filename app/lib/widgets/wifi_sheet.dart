import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_state.dart';
import '../models/wifi_network.dart';
import '../services/mqtt_service.dart';

/// Bottom sheet that lists the networks the ESP32 can see and lets the user
/// move the device to one of them. Opened from the Wi-Fi card on the home
/// screen. Scans as soon as it opens, and again on the refresh button.
class WifiSheet extends StatefulWidget {
  const WifiSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<MqttService>(),
        child: const WifiSheet(),
      ),
    );
  }

  @override
  State<WifiSheet> createState() => _WifiSheetState();
}

class _WifiSheetState extends State<WifiSheet> {
  @override
  void initState() {
    super.initState();
    context.read<MqttService>().requestWifiScan();
  }

  Future<void> _onNetworkTapped(MqttService mqtt, WifiNetwork network) async {
    String password = '';
    if (network.secure) {
      final entered = await showDialog<String>(
        context: context,
        builder: (context) => _PasswordDialog(ssid: network.ssid),
      );
      if (entered == null) return;
      password = entered;
    }

    mqtt.switchWifi(network.ssid, password);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final canSwitch = mqtt.deviceState.mode == OperatingMode.manual;
    final networks = mqtt.wifiNetworks;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose Wi-Fi network',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Scan again',
                  icon: const Icon(Icons.refresh),
                  onPressed: mqtt.requestWifiScan,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!canSwitch)
              Card(
                color: Colors.amber.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Wi-Fi can only be changed in MANUAL mode. Switch the mode to '
                    'MANUAL on the home screen first.',
                  ),
                ),
              ),
            if (canSwitch) ...[
              Text(
                'The laptop running the broker must be on the new network too, '
                'or the app will lose the device. If the ESP32 cannot reach the '
                'broker within a minute, it returns to the previous network.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: networks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Scanning... waiting for the ESP32.')),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: networks.length,
                      itemBuilder: (context, i) {
                        final network = networks[i];
                        final isCurrent = network.ssid == mqtt.wifiSsid;
                        return ListTile(
                          enabled: canSwitch && !isCurrent,
                          leading: Icon(_signalIcon(network.bars)),
                          title: Text(network.ssid),
                          subtitle: Text(isCurrent ? 'Current network' : '${network.rssi} dBm'),
                          trailing: Icon(network.secure ? Icons.lock : Icons.lock_open, size: 18),
                          onTap: canSwitch && !isCurrent
                              ? () => _onNetworkTapped(mqtt, network)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _signalIcon(int bars) {
    switch (bars) {
      case 4:
        return Icons.signal_wifi_4_bar;
      case 3:
        return Icons.network_wifi_3_bar;
      case 2:
        return Icons.network_wifi_2_bar;
      case 1:
        return Icons.network_wifi_1_bar;
      default:
        return Icons.signal_wifi_0_bar;
    }
  }
}

class _PasswordDialog extends StatefulWidget {
  final String ssid;

  const _PasswordDialog({required this.ssid});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Join ${widget.ssid}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: 'Wi-Fi password',
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onSubmitted: (_) => Navigator.of(context).pop(_controller.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
