import 'package:flutter/material.dart';

/// What the user typed into the broker dialog.
class BrokerSettings {
  final String host;
  final String user;
  final String pass;

  const BrokerSettings({
    required this.host,
    required this.user,
    required this.pass,
  });
}

/// Dialog for the laptop's address and the broker login. Entered once on
/// the phone; the app remembers it.
class BrokerDialog extends StatefulWidget {
  final String host;
  final String user;
  final String pass;

  const BrokerDialog({
    super.key,
    required this.host,
    required this.user,
    required this.pass,
  });

  @override
  State<BrokerDialog> createState() => _BrokerDialogState();
}

class _BrokerDialogState extends State<BrokerDialog> {
  late final TextEditingController _host;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.host);
    _user = TextEditingController(text: widget.user);
    _pass = TextEditingController(text: widget.pass);
  }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      BrokerSettings(host: _host.text, user: _user.text, pass: _pass.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Laptop (broker) settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Laptop name or IP address',
                hintText: 'e.g. LAPTOP-SONIA or 192.168.1.20',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'Broker username',
                hintText: 'Leave empty if the broker has no login',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'Broker password',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
