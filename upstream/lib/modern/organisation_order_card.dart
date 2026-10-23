import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// Facts and read-only hints prepared by the journal for its current order.
/// Source readers, draft validation and navigation remain in the journal.
@immutable
class OrganisationOrderCardData {
  const OrganisationOrderCardData({
    required this.scope,
    required this.title,
    required this.stateLabel,
    required this.prepared,
    required this.timing,
    this.previousOrder,
    this.currentAssignment,
    this.showAssignedOrderHint = false,
    this.juiceHint,
    this.travelNotice,
    this.readinessSummary,
    this.calculationResult,
    this.factors,
    this.cost,
    this.risk,
    this.unavailableReason,
    this.destinationUnavailableReason,
  });

  final String scope;
  final String title;
  final String stateLabel;
  final bool prepared;
  final String timing;
  final Widget? previousOrder;
  final String? currentAssignment;
  final bool showAssignedOrderHint;
  final Widget? juiceHint;
  final String? travelNotice;
  final String? readinessSummary;
  final String? calculationResult;
  final String? factors;
  final String? cost;
  final String? risk;
  final String? unavailableReason;
  final String? destinationUnavailableReason;
}

/// The ordinary order card. Required follow-up readers have their own cards.
/// Visibility and callback availability are separate so unavailable source
/// choices remain visible, with the same disabled controls as before.
class OrganisationOrderCard extends StatelessWidget {
  const OrganisationOrderCard({
    super.key,
    required this.data,
    required this.onDetails,
    required this.showConfirm,
    required this.showFinish,
    required this.showQueueVisit,
    required this.showCancel,
    required this.cancelPrepared,
    this.scrollHeading = false,
    this.onConfirm,
    this.onFinish,
    this.onQueueVisit,
    this.onCancel,
  });

  final OrganisationOrderCardData data;
  final VoidCallback onDetails;
  final bool showConfirm;
  final bool showFinish;
  final bool showQueueVisit;
  final bool showCancel;
  final bool cancelPrepared;
  final bool scrollHeading;
  final VoidCallback? onConfirm;
  final VoidCallback? onFinish;
  final VoidCallback? onQueueVisit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final heading = <Widget>[
      Text(
        data.title,
        key: const ValueKey('journal-current-order'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: JournalPalette.heading.copyWith(fontSize: 14),
      ),
      Text(
        data.stateLabel,
        key: const ValueKey('journal-order-state'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: JournalPalette.small.copyWith(
          fontSize: 9.5,
          height: 1.1,
          color: data.prepared ? JournalPalette.binding : JournalPalette.olive,
        ),
      ),
      const SizedBox(height: 2),
    ];
    return JournalSurface(
      key: const ValueKey('journal-job-card'),
      lined: true,
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.push_pin,
                size: 18,
                color: JournalPalette.brassDark,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  data.scope,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JournalPalette.heading.copyWith(fontSize: 11),
                ),
              ),
              IconButton(
                key: const ValueKey('journal-order-details'),
                tooltip: 'Order mechanics',
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (!scrollHeading) ...heading,
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('journal-order-mechanics'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (scrollHeading) ...heading,
                  ?data.previousOrder,
                  Text(data.timing, style: JournalPalette.small),
                  if (data.currentAssignment case final assignment?)
                    Text(
                      assignment,
                      key: const ValueKey('journal-assigned-order'),
                      style: JournalPalette.small,
                    ),
                  if (data.showAssignedOrderHint)
                    const Text(
                      'This describes the assigned order. Prepare a choice to review it.',
                      style: JournalPalette.small,
                    ),
                  ?data.juiceHint,
                  if (data.travelNotice case final notice?)
                    Text(
                      notice,
                      key: const ValueKey('journal-travel-notices'),
                      style: JournalPalette.small,
                    ),
                  if (data.readinessSummary case final summary?) ...[
                    Text(
                      'Readiness: $summary',
                      key: const ValueKey('journal-readiness-summary'),
                      style: JournalPalette.small,
                    ),
                    TextButton(
                      key: const ValueKey('journal-review-readiness'),
                      onPressed: onDetails,
                      child: const Text(
                        'Review weapons, ammunition and medical support',
                      ),
                    ),
                  ],
                  if (data.calculationResult case final result?)
                    Text(
                      result,
                      key: const ValueKey('journal-calculation-result'),
                      style: JournalPalette.small.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (data.factors case final factors?)
                    Text('Uses: $factors', style: JournalPalette.small),
                  if (data.cost case final cost?)
                    Text('Cost: $cost', style: JournalPalette.small),
                  if (data.risk case final risk?)
                    Text(
                      risk,
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.danger,
                      ),
                    ),
                  if (data.unavailableReason case final reason?)
                    Text(
                      reason,
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.danger,
                      ),
                    ),
                  if (data.destinationUnavailableReason case final reason?)
                    Text(
                      reason,
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.danger,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              if (showConfirm)
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('journal-confirm-order'),
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      textStyle: JournalPalette.small.copyWith(
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirm order'),
                  ),
                )
              else if (showFinish)
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('journal-finish-orders'),
                    onPressed: onFinish,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      textStyle: JournalPalette.small.copyWith(
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Finish orders'),
                  ),
                ),
              if (showQueueVisit)
                Expanded(
                  child: TextButton.icon(
                    key: const ValueKey('journal-prepare-map-visit'),
                    onPressed: onQueueVisit,
                    icon: const Icon(Icons.place, size: 16),
                    label: const Text('Queue visit'),
                  ),
                ),
              if (showCancel)
                IconButton(
                  key: cancelPrepared
                      ? const ValueKey('journal-cancel-order')
                      : null,
                  tooltip: cancelPrepared
                      ? 'Cancel prepared order'
                      : 'Return to planning; keep assigned orders',
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
