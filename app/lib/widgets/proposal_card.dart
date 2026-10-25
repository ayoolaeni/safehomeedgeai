import 'dart:async';

import 'package:flutter/material.dart';

import '../models/proposal.dart';

/// Appears only while a proposal is pending. Shows the reason, the
/// confidence, APPROVE/DECLINE buttons, and a countdown to when the ESP32
/// will expire the proposal itself (PROPOSAL_TIMEOUT_MS in config.h - keep
/// this in sync if you change that constant).
class ProposalCard extends StatefulWidget {
  final Proposal proposal;
  final DateTime receivedAt;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  final VoidCallback onExpire;

  static const int timeoutSeconds = 60;

  const ProposalCard({
    super.key,
    required this.proposal,
    required this.receivedAt,
    required this.onApprove,
    required this.onDecline,
    required this.onExpire,
  });

  @override
  State<ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends State<ProposalCard> {
  late Timer _timer;
  int _remaining = ProposalCard.timeoutSeconds;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final elapsed = DateTime.now().difference(widget.receivedAt).inSeconds;
    final remaining = ProposalCard.timeoutSeconds - elapsed;
    if (!mounted) return;
    setState(() => _remaining = remaining.clamp(0, ProposalCard.timeoutSeconds));
    if (remaining <= 0) {
      _timer.cancel();
      widget.onExpire();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.proposal;
    final isHigh = proposal.isHighConfidence;

    final scheme = Theme.of(context).colorScheme;
    const amber = Color(0xFFF59E0B);
    final confColor = isHigh ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Card(
      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.lightbulb_rounded, color: amber, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Lamp proposes: ${proposal.action.replaceAll('_', ' ').toLowerCase()}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: confColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                  child: Text(proposal.confidence,
                      style: TextStyle(fontSize: 10, color: confColor, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(proposal.reason),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _remaining / ProposalCard.timeoutSeconds,
                minHeight: 4,
                color: amber,
                backgroundColor: amber.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 4),
            Text('Expires in ${_remaining}s', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onApprove,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onDecline,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
