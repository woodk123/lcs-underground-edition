import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/squad_readiness.dart';

/// Read-only details for the order already selected by the journal.
/// The journal owns the route, reading scale and return focus.
class OrderMechanicsDialog extends StatelessWidget {
  const OrderMechanicsDialog({
    super.key,
    required this.help,
    required this.onClose,
    this.visitReadiness,
    this.visitMemberNames = const [],
  });

  final ActivityMechanics help;
  final VoidCallback onClose;
  final SquadReadiness? visitReadiness;
  final List<String> visitMemberNames;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
    child: AlertDialog(
      key: const ValueKey('journal-order-details-dialog'),
      title: Text(help.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(help.summary),
              const SizedBox(height: 8),
              Text(help.timing),
              if (help.factors.isNotEmpty) Text('Uses: ${help.factors}'),
              if (help.cost.isNotEmpty) Text('Cost: ${help.cost}'),
              if (help.requirements.isNotEmpty)
                Text('Needs: ${help.requirements}'),
              if (help.unavailableReason case final reason?)
                Text('Unavailable: $reason'),
              if (help.risk.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(help.risk),
              ],
              if (visitReadiness case final readiness?) ...[
                const SizedBox(height: 8),
                SquadReadinessView(readiness: readiness),
                const SizedBox(height: 8),
                Text(
                  'Members: ${visitMemberNames.join(', ')}',
                  key: const ValueKey('journal-visit-members'),
                ),
                const Text(
                  'Travel to another area needs a car; intercity travel also needs enough cash. '
                  'The site must be open and free of siege.',
                ),
              ],
              if (help.calculation case final calculation?) ...[
                const SizedBox(height: 12),
                ActivityCalculationView(calculation: calculation),
              ],
              if (help.details.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(help.details),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('journal-order-details-close'),
          autofocus: true,
          onPressed: onClose,
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
