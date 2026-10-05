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

    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Proposal: ${proposal.action.replaceAll('_', ' ')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(proposal.confidence),
                  backgroundColor: isHigh ? Colors.green.shade100 : Colors.red.shade100,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(proposal.reason),
            const SizedBox(height: 4),
            Text(
              'Expires in ${_remaining}s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onApprove,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('APPROVE'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onDecline,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('DECLINE'),
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
