import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';
import '../services/voice_service.dart';

/// Talk to the house. Commands and status questions are answered by local
/// rules, open questions by the small language model on the laptop, and the
/// rest is escalated through the AHDT gateway.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _text = TextEditingController();
  final _voice = VoiceService();
  bool _voiceReady = false;
  bool _listening = false;

  static const _suggestions = [
    'How is the house?',
    'What is the battery level?',
    'Turn on the bedroom light',
    'Lock the front door',
    'Why should we pump water at noon?',
  ];

  @override
  void initState() {
    super.initState();
    _voice.init().then((ok) {
      if (mounted) setState(() => _voiceReady = ok);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _voice.stopDictation(onText: (_) {});
    super.dispose();
  }

  void _send(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    context.read<MqttService>().ask(t);
    _text.clear();
  }

  void _onHeard(String words) {
    if (!mounted) return;
    setState(() => _listening = false);
    if (words.trim().isNotEmpty) _send(words);
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final slm = mqtt.home?.slm ?? const {};
    final answers = mqtt.answers;
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(10),
          child: Text(
            slm['available'] == true
                ? 'Answers come from the home server: local rules first, then the local language model '
                    '(${slm['model']}). Nothing leaves the house unless it must be escalated.'
                : 'Local language model not available - commands and status questions still work.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: answers.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Try asking:'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _suggestions
                          .map((s) => ActionChip(label: Text(s), onPressed: () => _send(s)))
                          .toList(),
                    ),
                  ],
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: answers.length,
                  itemBuilder: (_, i) => _exchange(context, answers[i]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTapDown: (_) async {
                    if (!_voiceReady) return;
                    setState(() => _listening = true);
                    await _voice.startDictation(onText: _onHeard);
                  },
                  onTapUp: (_) => _voice.stopDictation(onText: _onHeard),
                  onTapCancel: () => _voice.stopDictation(onText: _onHeard),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: _listening ? Colors.red : (_voiceReady ? Colors.indigo : Colors.grey),
                    child: Icon(_listening ? Icons.mic : Icons.mic_none, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _text,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: _voiceReady ? 'Type, or hold the mic to speak' : 'Ask your home...',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(icon: const Icon(Icons.send_rounded), onPressed: () => _send(_text.text)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble({required Widget child, required Color color, required bool mine}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: child,
    );
  }

  Widget _exchange(BuildContext context, Map<String, dynamic> a) {
    final scheme = Theme.of(context).colorScheme;
    final answer = a['answer']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _bubble(
            mine: true,
            color: scheme.primary,
            child: Text(a['question']?.toString() ?? '', style: TextStyle(color: scheme.onPrimary)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _bubble(
            mine: false,
            color: scheme.surfaceContainerHigh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(answer ?? 'Thinking...'),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 12, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text(a['source']?.toString() ?? '', style: Theme.of(context).textTheme.labelSmall),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
