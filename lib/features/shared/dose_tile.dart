import 'package:flutter/material.dart';

import '../../domain/models/dose.dart';
import '../../l10n/app_localizations.dart';
import 'dose_actions.dart';
import 'dose_status.dart';
import 'formatters.dart';
import 'medication_avatar.dart';

/// One row in a list of doses. Tap for all actions; a quick "take" button is
/// shown while the dose is pending.
class DoseTile extends StatelessWidget {
  const DoseTile({required this.dose, this.showQuickTake = true, super.key});

  final DoseInstance dose;
  final bool showQuickTake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final medication = dose.medication;
    final color = dose.status.color(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDoseActionsSheet(context, dose),
        child: Container(
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: color, width: 5),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              MedicationAvatar(medication: medication),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.dosageText(medication),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              context.formatTime(dose.effectiveAt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        DoseStatusChip(status: dose.status),
                        if (dose.isRescheduled)
                          Text(
                            l10n.rescheduledFrom(
                              context.formatTime(dose.scheduledAt),
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showQuickTake && !dose.isDone)
                IconButton.filledTonal(
                  tooltip: l10n.actionTake,
                  iconSize: 30,
                  onPressed: () async {
                    await DoseActions.of(context).take(dose);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.doseMarkedTaken)),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
