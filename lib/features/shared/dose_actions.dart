import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../core/notifications/reminder_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../domain/models/dose.dart';
import '../../l10n/app_localizations.dart';
import 'dose_status.dart';
import 'formatters.dart';
import 'medication_avatar.dart';

/// Records actions on a dose from anywhere in the app. The person acting
/// may be the patient or a caregiver (stored in `actedBy`).
class DoseActions {
  DoseActions.of(BuildContext context)
    : _logs = context.read<DoseLogRepository>(),
      _reminders = context.read<ReminderService>(),
      _userId = context.read<AuthRepository>().ownerId;

  final DoseLogRepository _logs;
  final ReminderService _reminders;
  final String _userId;

  Future<void> take(DoseInstance dose) => _record(dose, DoseLogStatus.taken);

  Future<void> skip(DoseInstance dose) => _record(dose, DoseLogStatus.skipped);

  Future<void> reschedule(DoseInstance dose, DateTime newTime) =>
      _record(dose, DoseLogStatus.rescheduled, rescheduledTo: newTime);

  Future<void> undo(DoseInstance dose) async {
    await _logs.clear(dose.logId);
  }

  Future<void> _record(
    DoseInstance dose,
    DoseLogStatus status, {
    DateTime? rescheduledTo,
  }) async {
    await _logs.record(
      ownerId: dose.medication.ownerId,
      medicationId: dose.medication.id,
      scheduledAt: dose.scheduledAt,
      status: status,
      actedBy: _userId,
      rescheduledTo: rescheduledTo,
    );
    if (status != DoseLogStatus.rescheduled) {
      await _reminders.cancelDose(dose.logId);
    }
  }
}

/// Bottom sheet with everything you can do with one dose.
Future<void> showDoseActionsSheet(BuildContext context, DoseInstance dose) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _DoseActionsSheet(dose: dose),
  );
}

class _DoseActionsSheet extends StatelessWidget {
  const _DoseActionsSheet({required this.dose});

  final DoseInstance dose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = DoseActions.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final medication = dose.medication;

    Future<void> run(Future<void> Function() action, String message) async {
      Navigator.of(context).pop();
      await action();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MedicationAvatar(medication: medication, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medication.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${context.dosageText(medication)} • ${context.formatTime(dose.effectiveAt)}',
                      ),
                    ],
                  ),
                ),
                DoseStatusChip(status: dose.status),
              ],
            ),
            const SizedBox(height: 20),
            if (!dose.isDone) ...[
              FilledButton.icon(
                onPressed: () =>
                    run(() => actions.take(dose), l10n.doseMarkedTaken),
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.actionTake),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          run(() => actions.skip(dose), l10n.doseMarkedSkipped),
                      icon: const Icon(Icons.skip_next_rounded),
                      label: Text(l10n.actionSkip),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reschedule(context, actions, messenger),
                      icon: const Icon(Icons.update_rounded),
                      label: Text(l10n.actionReschedule),
                    ),
                  ),
                ],
              ),
            ] else
              OutlinedButton.icon(
                onPressed: () =>
                    run(() => actions.undo(dose), l10n.doseMarkedPending),
                icon: const Icon(Icons.undo_rounded),
                label: Text(l10n.actionUndo),
              ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(
                  Routes.medication(medication.id, doseAt: dose.scheduledAt),
                );
              },
              icon: const Icon(Icons.info_outline_rounded),
              label: Text(l10n.actionMedicationDetails),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reschedule(
    BuildContext context,
    DoseActions actions,
    ScaffoldMessengerState messenger,
  ) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final picked = await pickRescheduleTime(context, dose);
    if (picked == null) return;
    navigator.pop();
    await actions.reschedule(dose, picked);
    messenger.showSnackBar(SnackBar(content: Text(l10n.doseRescheduled)));
  }
}

/// Asks for a new time for [dose] on the same day as it was planned.
/// Returns the new instant in UTC.
Future<DateTime?> pickRescheduleTime(
  BuildContext context,
  DoseInstance dose,
) async {
  final current = dose.effectiveAt.toLocal();
  final now = DateTime.now();
  final initial = current.isBefore(now)
      ? now.add(const Duration(minutes: 30))
      : current;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: AppLocalizations.of(context).rescheduleHelp,
  );
  if (time == null) return null;
  final base = dose.scheduledAt.toLocal();
  var result = DateTime(
    base.year,
    base.month,
    base.day,
    time.hour,
    time.minute,
  );
  // A time already past today means tomorrow (e.g. moving 23:00 to 00:30).
  if (result.isBefore(now) && base.day == now.day) {
    result = result.add(const Duration(days: 1));
  }
  return result.toUtc();
}
