import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models/dose.dart';
import '../../l10n/app_localizations.dart';

extension DoseStatusStyle on DoseStatus {
  Color color(BuildContext context) => switch (this) {
    DoseStatus.taken => AppColors.success,
    DoseStatus.skipped => AppColors.muted,
    DoseStatus.missed => AppColors.danger,
    DoseStatus.due => AppColors.warning,
    DoseStatus.upcoming => Theme.of(context).colorScheme.primary,
  };

  IconData get icon => switch (this) {
    DoseStatus.taken => Icons.check_circle_rounded,
    DoseStatus.skipped => Icons.remove_circle_rounded,
    DoseStatus.missed => Icons.error_rounded,
    DoseStatus.due => Icons.notifications_active_rounded,
    DoseStatus.upcoming => Icons.schedule_rounded,
  };

  String label(AppLocalizations l10n) => switch (this) {
    DoseStatus.taken => l10n.statusTaken,
    DoseStatus.skipped => l10n.statusSkipped,
    DoseStatus.missed => l10n.statusMissed,
    DoseStatus.due => l10n.statusDue,
    DoseStatus.upcoming => l10n.statusUpcoming,
  };
}

class DoseStatusChip extends StatelessWidget {
  const DoseStatusChip({required this.status, super.key});

  final DoseStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            status.label(AppLocalizations.of(context)),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
